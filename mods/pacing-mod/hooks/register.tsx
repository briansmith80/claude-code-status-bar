import { atom, read, update } from 'claude-code'
import type { PluginOptions, Register } from 'claude-code'

import type { Ctx, Limit, Sess } from '../types'
import { WINDOW_SECS, barSegments, duration, fmtTokens, forecast, pacingTarget, toEpoch } from './pacing'
import { gaugeSvg } from './gauge'
import { DEFAULT_LOOK, FOLLOW_BAR, THEME_NAMES, resolveLook } from './theme'
import type { Look } from './theme'

const PLUGIN = 'pacing-mod'
const PANE = 'pacing'
const TITLE = 'Usage pacing'
const SCOPED_MAX_AGE = 3600 // matches the bar: 6 x usage_cache_seconds
const FILE_MEMO_MS = 30_000
const COMPACT_WARN_TOKENS = 20_000 // the bar's ▲ fires this close to the compact point

const limits = atom({ plugin: 'pacing-mod', key: 'limits' } as const, [], { shape: 'limits-1' })
const NO_CTX: Ctx = { percent: null, tokens: null, window: 0, compactAt: null, autoCompact: true, model: null }
const context = atom({ plugin: 'pacing-mod', key: 'context' } as const, NO_CTX, { shape: 'context-1' })
const toasted = atom({ plugin: 'pacing-mod', key: 'toasted' } as const, [], { shape: 'toasted-1' })
const NO_SESS: Sess = { startedAt: null, usd: null }
const sess = atom({ plugin: 'pacing-mod', key: 'session' } as const, NO_SESS, { shape: 'session-1' })
// Set when the person closes the pane; drives the "Open pacing" buttons.
const isClosed = atom({ plugin: 'pacing-mod', key: 'isClosed' } as const, false)
// The transcript row that carries the reopen button (one per close, so it
// lands at the end of the chat; older ones draw nothing).
const reopenRow = atom({ plugin: 'pacing-mod', key: 'reopenRow' } as const, '')

type Options = { theme: string; band: boolean; toasts: boolean; notify: boolean; context: boolean; session: boolean }

function readOptions(o: PluginOptions): Options {
  return {
    theme: typeof o.theme === 'string' && (o.theme === FOLLOW_BAR || THEME_NAMES.includes(o.theme)) ? o.theme : FOLLOW_BAR,
    band: o.band !== false,
    toasts: o.toasts !== false,
    notify: o.notify === true,
    context: o.context !== false,
    session: o.session !== false,
  }
}

type Row = {
  kind: string
  label: string
  short: string
  used: number
  pace: number | null
  elapsed: number | null
  resetIn: string | null
  forecast: string | null
  resetEpoch: number | null
}

const THEME_OPTIONS = [
  { value: FOLLOW_BAR, label: 'Match status bar' },
  ...THEME_NAMES.map(n => ({ value: n, label: n })),
]

// `/pacing demo` shows sample data in every state (over pace, past 90%, the
// per-model weekly swap, near auto-compact) so the look can be reviewed
// without waiting for real usage. `/pacing` goes back to live.
let demo = false
function demoLimits(now: number): Limit[] {
  const iso = (s: number) => new Date(s * 1000).toISOString()
  return [
    { kind: 'five_hour', percentUsed: 80, resetsAt: iso(now + 2 * 3600) },
    { kind: 'seven_day', percentUsed: 40, resetsAt: iso(now + 2 * 86400) },
    { kind: 'seven_day_fable', percentUsed: 92, resetsAt: iso(now + 2 * 86400) },
  ]
}
const DEMO_CTX: Ctx = { percent: 88, tokens: 350_000, window: 400_000, compactAt: 367_000, autoCompact: true, model: 'Opus 5.5' }

// Files of the status bar's install, read at most every FILE_MEMO_MS.
let home: string | null | undefined
let memo: Record<string, { at: number; text: string | null }> = {}
async function readHomeFile($: any, name: string, nowMs: number): Promise<string | null> {
  const hit = memo[name]
  if (hit && nowMs - hit.at < FILE_MEMO_MS) return hit.text
  let text: string | null = null
  try {
    if (home === undefined) home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE')) || null
    if (home) text = await $.fs.read(`${home}/.claude/${name}`)
  } catch {
    text = null
  }
  memo[name] = { at: nowMs, text }
  return text
}

// The status bar's own colour_theme / bar_gradient, so the pane matches it,
// unless the plugin's theme option pins one.
let look: Look = DEFAULT_LOOK
let themeChoice = FOLLOW_BAR
async function loadLook($: any, nowMs: number): Promise<void> {
  look = resolveLook(await readHomeFile($, 'statusline.conf', nowMs), themeChoice)
}

// The model-scoped weekly cap is not in $.session.usage(). The status bar's
// OAuth cache carries it; read it when present, silently skip when not.
async function scopedWeekly($: any, now: number): Promise<{ model: string; percent: number; resetsAt?: string } | null> {
  try {
    const raw = await readHomeFile($, '.statusline-usage-cache', now * 1000)
    if (!raw) return null
    const space = raw.indexOf(' ')
    const stamp = Number(raw.slice(0, space))
    if (!Number.isFinite(stamp) || now - stamp > SCOPED_MAX_AGE) return null
    const body = JSON.parse(raw.slice(space + 1))
    const hit = (body.limits ?? []).find((l: any) => l?.kind === 'weekly_scoped')
    const model = String(hit?.scope?.model?.display_name ?? '').slice(0, 12)
    if (!hit || !model || typeof hit.percent !== 'number') return null
    return { model, percent: hit.percent, resetsAt: hit.resets_at }
  } catch {
    return null
  }
}

// The context window with its auto-compact point. The summary breakdown is a
// local estimate (no API call) and is the only place the threshold is given.
async function fetchContext($: any): Promise<Ctx> {
  let u: any
  try {
    u = await $.session.usage({ breakdown: 'summary' })
  } catch {
    u = await $.session.usage()
  }
  return ctxFrom(u?.context, null)
}

function ctxFrom(c: any, prev: Ctx | null): Ctx {
  const b = c?.breakdown
  const window = typeof c?.window === 'number' && c.window > 0 ? c.window : b?.rawMaxTokens ?? prev?.window ?? 0
  const tokens = typeof c?.tokens === 'number' ? c.tokens : typeof b?.totalTokens === 'number' ? b.totalTokens : prev?.tokens ?? null
  let percent = typeof c?.percent === 'number' ? c.percent : null
  if (percent === null && tokens !== null && window > 0) percent = (tokens / window) * 100
  return {
    percent,
    tokens,
    window,
    compactAt: b ? (b.isAutoCompactEnabled === false ? null : b.autoCompactThreshold ?? null) : prev?.compactAt ?? null,
    autoCompact: b ? b.isAutoCompactEnabled !== false : prev?.autoCompact ?? true,
    model: typeof b?.model === 'string' ? b.model : prev?.model ?? null,
  }
}

function toRow(kind: string, label: string, short: string, lim: Limit, now: number): Row {
  const used = Math.round(lim.percentUsed)
  const reset = toEpoch(lim.resetsAt)
  const win = WINDOW_SECS[kind]!
  const elapsed = reset === null ? null : Math.max(0, Math.min(win, now - (reset - win)))
  return {
    kind,
    label,
    short,
    used,
    pace: reset === null ? null : pacingTarget(reset, win, now),
    elapsed,
    resetIn: reset === null ? null : duration(reset - now),
    forecast: reset === null ? null : forecast(reset, win, used, now),
    resetEpoch: reset,
  }
}

async function rows($: any, list: Limit[], now: number): Promise<Row[]> {
  const out: Row[] = []
  const five = list.find(l => l.kind === 'five_hour')
  if (five) out.push(toRow('five_hour', '5-hour', '5h', five, now))
  const weekly = list.find(l => l.kind === 'seven_day')
  if (weekly) {
    // Some plans cap one model's weekly use below the all-models cap. Claude
    // Code may forward it as seven_day_<model>; the status bar's OAuth cache
    // carries it as weekly_scoped. Whichever binds first (higher %) is shown.
    let pick: Limit = weekly
    let label = 'Weekly'
    let short = 'wk'
    for (const l of list) {
      const m = /^seven_day_([a-z]+)$/.exec(l.kind)
      if (m && l.percentUsed > pick.percentUsed) {
        const name = m[1]![0]!.toUpperCase() + m[1]!.slice(1)
        pick = l
        label = `Weekly (${name})`
        short = `wk:${name}`
      }
    }
    const scoped = demo ? null : await scopedWeekly($, now)
    if (scoped && scoped.percent > pick.percentUsed) {
      pick = { kind: 'seven_day', percentUsed: scoped.percent, resetsAt: scoped.resetsAt ?? weekly.resetsAt }
      label = `Weekly (${scoped.model})`
      short = `wk:${scoped.model}`
    }
    out.push(toRow('seven_day', label, short, pick, now))
  }
  return out
}

async function currentRows($: any, list: Limit[]): Promise<Row[]> {
  const now = Math.floor((await $.clock.now()) / 1000)
  return rows($, demo ? demoLimits(now) : list, now)
}

function tone(r: Row): 'error' | 'warning' | 'success' {
  if (r.used >= 90) return 'error'
  if (r.forecast) return 'warning'
  return 'success'
}

// The one verdict beside the big number.
function paceChip(r: Row): { text: string; color: string } | null {
  if (r.pace === null) return null
  const delta = r.used - r.pace
  if (Math.abs(delta) <= 2) return { text: 'on pace', color: 'subtle' }
  if (delta > 0) return { text: `over pace by ${delta}`, color: 'warning' }
  return { text: `under pace by ${-delta}`, color: 'success' }
}

// The one fact the chip and bar do not carry: what happens at this rate.
function paceFooter(r: Row): { text: string; warn: boolean } {
  if (r.forecast) return { text: `▲ At this rate you hit the limit in ${r.forecast}`, warn: true }
  if (r.used <= 0) return { text: 'Nothing used in this window yet', warn: false }
  if (r.elapsed !== null && r.elapsed < 120) return { text: 'Window just started', warn: false }
  return { text: 'Limit not reached before reset at this rate', warn: false }
}

type CtxView = {
  percent: number
  tokens: number | null
  marker: number | null
  chip: { text: string; color: string } | null
  footer: string
  tone: 'error' | 'warning' | 'success'
}

function ctxView(c: Ctx): CtxView | null {
  if (c.percent === null) return null
  const percent = Math.round(c.percent)
  const marker = c.compactAt !== null && c.window > 0 ? (c.compactAt / c.window) * 100 : null
  let chip: CtxView['chip'] = null
  let tone: CtxView['tone'] = 'success'
  if (!c.autoCompact) {
    chip = { text: 'auto-compact off', color: 'subtle' }
    if (percent >= 80) tone = 'warning'
  } else if (c.compactAt !== null && c.tokens !== null) {
    const left = c.compactAt - c.tokens
    if (left <= 0) {
      chip = { text: 'auto-compact due', color: 'error' }
      tone = 'error'
    } else if (left <= COMPACT_WARN_TOKENS) {
      chip = { text: `▲ compacts in ${fmtTokens(left)} tokens`, color: 'warning' }
      tone = 'warning'
    } else {
      chip = { text: `${fmtTokens(left)} tokens to auto-compact`, color: 'subtle' }
    }
  }
  const parts = []
  if (c.model) parts.push(c.model)
  if (c.window > 0) parts.push(`${fmtTokens(c.window)} window`)
  if (!c.autoCompact) parts.push('auto-compact is off')
  return { percent, tokens: c.tokens, marker, chip, footer: parts.join(' · '), tone }
}

function sessionLine(s: Sess, nowMs: number): string | null {
  const parts: string[] = []
  if (s.startedAt !== null && nowMs > s.startedAt) parts.push(`Session ${duration(Math.floor((nowMs - s.startedAt) / 1000))}`)
  if (s.usd !== null && s.usd > 0) parts.push(`$${s.usd.toFixed(2)}`)
  return parts.length ? parts.join(' · ') : null
}

// One line for `/pacing status`, and the terminal fallback when no pane fits.
function summaryLine(list: Row[], ctx: CtxView | null, session: string | null): string {
  const parts: string[] = []
  for (const r of list) {
    const chip = paceChip(r)
    const bits = [chip?.text, r.resetIn ? `resets in ${r.resetIn}` : null, r.forecast ? `limit in ${r.forecast} at this rate` : null].filter(Boolean)
    parts.push(`${r.short} ${r.used}%${bits.length ? ` (${bits.join(', ')})` : ''}`)
  }
  if (ctx) parts.push(`ctx ${ctx.percent}%${ctx.chip ? ` (${ctx.chip.text.replace('▲ ', '')})` : ''}`)
  if (session) parts.push(session)
  return parts.length ? parts.join(' · ') : 'No usage figures yet (they arrive with the first reply).'
}

async function openPane($: any): Promise<void> {
  await update($, isClosed, () => false)
  await $.ui.open({ id: PANE, title: TITLE })
  $.ui.invalidate('ui.render')
}

// The theme picker writes the plugin's own option, so /config shows the
// same value and the module reloads with it. The look changes at once too.
async function pickTheme($: any, value: string): Promise<void> {
  themeChoice = value
  memo = {}
  await loadLook($, await $.clock.now())
  $.ui.invalidate('ui.render')
  const set = await $.config.set({ key: `${PLUGIN}.theme`, value })
  if (set?.deny) $.ui.toast(`Theme not saved: ${set.deny}`)
}

// Toasts stay in the app; native notifications go through the person's own
// channel (their preferredNotifChannel), so they reach them when the window
// is not in front. Fail-silent: a surface with no channel just drops it.
let alerts: { toasts: boolean; notify: boolean } = { toasts: true, notify: false }
function alert($: any, text: string): void {
  if (alerts.toasts) $.ui.toast(text)
  if (alerts.notify) void $.ui.notify(text, { title: TITLE }).catch(() => undefined)
}

export const register: Register = (on, options) => {
  const opts = readOptions(options)
  alerts = { toasts: opts.toasts, notify: opts.notify }
  themeChoice = opts.theme

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'pacing',
      description: 'Show usage pacing in a pane (`/pacing demo` previews every state)',
    })
    const usage = await $.session.usage()
    await update($, limits, () => usage.rateLimits.map(l => ({ ...l })))
    await update($, sess, () => ({
      startedAt: typeof usage.startedAt === 'number' ? usage.startedAt : null,
      usd: typeof usage.cost?.usd === 'number' ? usage.cost.usd : null,
    }))
    const refreshContext = async () => {
      if (!opts.context) return
      try {
        const ctx = await fetchContext($)
        await update($, context, () => ctx)
      } catch {
        // the card just keeps what the last measure gave it
      }
    }
    await refreshContext()
    await loadLook($, await $.clock.now())
    // The terminal has the status line, so the pane opens there only on `/pacing`.
    if (e.surface !== 'terminal' && !(await read($, isClosed))) void $.ui.open({ id: PANE, title: TITLE })
    // Countdowns and the pace marker move with the clock, not just with
    // replies; the auto-compact threshold (breakdown-only) is re-read here too.
    $.clock.every(60_000, async () => {
      await loadLook($, await $.clock.now())
      await refreshContext()
      $.ui.invalidate('ui.render')
    })
    return next(e)
  })

  on('command.run', { command: 'pacing' }, async ($, e) => {
    const arg = (e.args ?? '').trim().toLowerCase()
    if (arg === 'status') {
      const nowMs = await $.clock.now()
      const list = await currentRows($, await read($, limits))
      const ctx = opts.context ? ctxView(demo ? DEMO_CTX : await read($, context)) : null
      return { text: summaryLine(list, ctx, opts.session ? sessionLine(await read($, sess), nowMs) : null) }
    }
    demo = arg === 'demo'
    await openPane($)
    return { text: demo ? 'Usage pacing pane: sample data. `/pacing` returns to live.' : 'Usage pacing pane opened.' }
  })


  // Never call $.session.usage from here: measuring raises this event again
  // beneath the call, and the engine ends the re-entered hook. The limits
  // land first so nothing after them can keep them from the pane; the
  // auto-compact threshold is refreshed on the timer instead.
  on('session.measure', async ($, e, next) => {
    let before: Limit[] = []
    if (e.changed.includes('rateLimits')) {
      before = await read($, limits)
      await update($, limits, () => e.rateLimits.map(l => ({ ...l })))
    }
    if (opts.context && e.changed.includes('context')) {
      const prev = await read($, context)
      await update($, context, () => ctxFrom(e.context, prev))
    }
    if (e.changed.includes('cost') && typeof e.cost?.usd === 'number') {
      const usd = e.cost.usd
      await update($, sess, s => ({ ...s, usd }))
    }
    if ((!opts.toasts && !opts.notify) || !e.changed.includes('rateLimits')) return next(e)
    // One alert per window per reason: a window reset, the forecast firing,
    // or usage passing 90%.
    const seen = await read($, toasted)
    const fresh: string[] = []
    for (const r of await currentRows($, e.rateLimits)) {
      const id = `${r.kind}@${r.resetEpoch === null ? '' : Math.floor(r.resetEpoch / 300)}`
      const was = toEpoch(before.find(l => l.kind === r.kind)?.resetsAt)
      if (was !== null && r.resetEpoch !== null && r.resetEpoch > was + 60 && !seen.includes(`${id}:reset`)) {
        alert($, `${r.label} window reset: ${r.used}% used, resets in ${r.resetIn ?? '?'}`)
        fresh.push(`${id}:reset`)
      }
      if (r.used >= 90 && !seen.includes(`${id}:90`)) {
        alert($, `${r.label} limit at ${r.used}%, resets in ${r.resetIn ?? '?'}`)
        fresh.push(`${id}:90`)
      } else if (r.forecast && !seen.includes(`${id}:fc`)) {
        alert($, `${r.label}: at this rate you hit the limit in ${r.forecast}`)
        fresh.push(`${id}:fc`)
      }
    }
    if (fresh.length) await update($, toasted, old => [...old, ...fresh].slice(-30))
    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Select, Svg } = $.ui.resolve(e) as any
    const list = await currentRows($, await read($, limits))
    const ctx = opts.context ? ctxView(demo ? DEMO_CTX : await read($, context)) : null
    const session = opts.session
      ? demo ? 'Session 2h14m · $3.40' : sessionLine(await read($, sess), await $.clock.now())
      : null
    const picker = (
      <Box flexDirection="row" alignItems="center" gap="sm" marginTop={1}>
        <Select
          key="theme"
          label="Theme"
          options={THEME_OPTIONS}
          value={themeChoice}
          onSelect={(value: string) => pickTheme($, value)}
        />
      </Box>
    )
    if (list.length === 0 && ctx === null) {
      return (
        <Box flexDirection="column">
          <Text dimColor>Waiting for the first reply.</Text>
          <Text dimColor>Limits show once Claude answers (subscription plans only).</Text>
          {picker}
        </Box>
      )
    }
    if (e.surface !== 'terminal') {
      const card = (
        label: string,
        right: string,
        big: string,
        bigTone: string,
        chip: { text: string; color: string } | null,
        svg: string,
        alt: string,
        footer: { text: string; warn: boolean },
      ) => (
        <Box flexDirection="column" gap="xs">
          <Box flexDirection="row" justifyContent="space-between">
            <Text size="caption" weight="semibold" dimColor>{label}</Text>
            <Text size="caption" dimColor tabular>{right}</Text>
          </Box>
          <Box flexDirection="row" alignItems="flex-end" gap="sm">
            <Text size="title" weight="bold" tabular color={bigTone}>{big}</Text>
            {chip && <Text size="footnote" weight="medium" color={chip.color}>{chip.text}</Text>}
          </Box>
          <Svg source={svg} alt={alt} />
          {footer.warn
            ? <Text size="footnote" weight="medium" color="warning">{footer.text}</Text>
            : <Text size="footnote" dimColor>{footer.text}</Text>}
        </Box>
      )
      return (
        <Box flexDirection="column" gap="lg" paddingY="sm">
          {list.map(r =>
            card(
              r.label.toUpperCase(),
              r.resetIn ? `resets in ${r.resetIn}` : '',
              `${r.used}%`,
              tone(r),
              paceChip(r),
              gaugeSvg(look, r.used, r.pace),
              `${r.label}: ${r.used}% used, even pace ${r.pace ?? '?'}%`,
              paceFooter(r),
            ),
          )}
          {ctx &&
            card(
              'CONTEXT',
              ctx.tokens === null ? '' : `${fmtTokens(ctx.tokens)} used`,
              `${ctx.percent}%`,
              ctx.tone,
              ctx.chip,
              gaugeSvg(look, ctx.percent, ctx.marker),
              `Context: ${ctx.percent}% used, auto-compact at ${ctx.marker === null ? 'off' : Math.round(ctx.marker) + '%'}`,
              { text: ctx.footer, warn: false },
            )}
          {list.length === 0 && (
            <Text size="footnote" dimColor>Limits show once Claude answers (subscription plans only).</Text>
          )}
          {session && <Text size="footnote" dimColor tabular>{session}</Text>}
          {picker}
        </Box>
      )
    }
    const width = Math.max(10, Math.min(30, (e.viewport?.columns ?? 40) - 12))
    const textBar = (used: number, marker: number | null, colour: string) => (
      <Text mono>
        {barSegments(used, marker, width).map(s =>
          s.kind === 'fill' ? <Text color={colour}>{s.text}</Text>
          : s.kind === 'pace' ? <Text color={look.theme.pace}>{s.text}</Text>
          : <Text dimColor>{s.text}</Text>,
        )}
        <Text> {used}%</Text>
      </Text>
    )
    return (
      <Box flexDirection="column">
        {list.map(r => {
          const chip = paceChip(r)
          const footer = paceFooter(r)
          return (
            <Box flexDirection="column" marginBottom={1}>
              <Text weight="semibold">{r.label}</Text>
              {textBar(r.used, r.pace, tone(r))}
              <Text dimColor>
                {chip ? `${chip.text}  ` : ''}
                {r.resetIn ? `resets in ${r.resetIn}` : ''}
              </Text>
              {footer.warn ? <Text color="warning">{footer.text}</Text> : <Text dimColor>{footer.text}</Text>}
            </Box>
          )
        })}
        {ctx && (
          <Box flexDirection="column" marginBottom={1}>
            <Text weight="semibold">Context</Text>
            {textBar(ctx.percent, ctx.marker, ctx.tone)}
            <Text dimColor>
              {ctx.chip ? `${ctx.chip.text}  ` : ''}
              {ctx.tokens === null ? '' : `${fmtTokens(ctx.tokens)} used`}
            </Text>
            <Text dimColor>{ctx.footer}</Text>
          </Box>
        )}
        {session && <Text dimColor>{session}</Text>}
        {picker}
      </Box>
    )
  })

  // The person closed the pane: leave a reopen button where they will see it.
  // Desktop and VS Code get it in the band; every surface also gets a
  // one-line row at the end of the chat.
  on('ui.close', async ($, e, next) => {
    const done = await next(e)
    if (e.id === PANE && e.origin.kind === 'person') {
      await update($, isClosed, () => true)
      const id = `reopen-${Math.floor((await $.clock.now()) / 1000)}`
      await update($, reopenRow, () => id)
      await $.ui.place({ id })
      $.ui.invalidate('ui.render')
    }
    return done
  })

  on('ui.render', { component: 'Placed' }, async ($, e, next) => {
    if (e.props.plugin !== PLUGIN) return next(e)
    const isLatest = e.props.id === (await read($, reopenRow))
    if (!isLatest || !(await read($, isClosed))) return next(e)
    const { Box, Button, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="row" alignItems="center" gap="sm">
        <Text dimColor>Usage pacing pane closed.</Text>
        <Button key="reopen" label="Open pacing" onPress={() => openPane($)} />
      </Box>
    )
  })

  // Band: Desktop and VS Code (VS Code adds its own "From the pacing-mod
  // plugin" caption). The terminal already has the status line.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (!opts.band || e.surface === 'terminal' || e.props.hasSurvey) return next(e)
    const list = await currentRows($, await read($, limits))
    const ctx = opts.context ? ctxView(demo ? DEMO_CTX : await read($, context)) : null
    const closed = await read($, isClosed)
    if (list.length === 0 && ctx === null && !closed) return next(e)
    const { Box, Button, Text, Svg } = $.ui.resolve(e) as any
    return (
      <Box flexDirection="row" alignItems="center" gap="md">
        {list.map(r => (
          <Box flexDirection="row" alignItems="center" gap="xs">
            <Text size="caption" weight="semibold" dimColor>{r.short}</Text>
            <Svg source={gaugeSvg(look, r.used, r.pace, 'mini')} alt={`${r.label} ${r.used}%`} />
            <Text size="caption" weight="semibold" tabular color={tone(r)}>{r.used}%</Text>
            {r.forecast
              ? <Text size="caption" color="warning">▲{r.forecast}</Text>
              : <Text size="caption" dimColor tabular>{r.resetIn ?? ''}</Text>}
          </Box>
        ))}
        {ctx && (
          <Box flexDirection="row" alignItems="center" gap="xs">
            <Text size="caption" weight="semibold" dimColor>ctx</Text>
            <Svg source={gaugeSvg(look, ctx.percent, ctx.marker, 'mini')} alt={`Context ${ctx.percent}%`} />
            <Text size="caption" weight="semibold" tabular color={ctx.tone}>{ctx.percent}%</Text>
          </Box>
        )}
        {closed && <Button key="open" label="Open pacing" onPress={() => openPane($)} />}
      </Box>
    )
  })
}
