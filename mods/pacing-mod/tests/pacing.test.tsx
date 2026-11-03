import { expect, test } from 'claude-code/testing'

import { barSegments, forecast, pacingTarget } from '../hooks/pacing'
import { VECTORS } from './vectors'

const NOW = 1_793_700_000 // fixed clock, seconds
const iso = (s: number) => new Date(s * 1000).toISOString()

// 5h window, 3h in (60% pace), 80% used: over pace, forecast fires.
// Weekly, 1 day in (14% pace), 8% used: under pace.
const LIMITS = [
  { kind: 'five_hour', percentUsed: 80, resetsAt: iso(NOW + 2 * 3600) },
  { kind: 'seven_day', percentUsed: 8, resetsAt: iso(NOW + 6 * 86400) },
]

const PANE = {
  plugin: 'pacing-mod',
  component: 'Pane',
  requestId: 'pacing',
  props: {
    title: 'Usage pacing',
    isFocused: false,
    bodyColumns: 40,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 20 },
    view: {},
  },
} as const

const BAND = {
  plugin: 'pacing-mod',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 6, bodyColumns: 80 },
} as const

const CONTEXT = {
  window: 400_000,
  tokens: 100_000,
  percent: 25,
  breakdown: { rawMaxTokens: 400_000, totalTokens: 100_000, autoCompactThreshold: 367_000, isAutoCompactEnabled: true, model: 'Opus 5.5' },
}

function engine(on: any, limits: unknown[], opened: string[] = [], context: unknown = CONTEXT) {
  on('command.register', () => ({ value: { command: 'pacing' } }))
  on('ui.open', (_: unknown, e: any) => (opened.push(e.id), { value: { isPlaced: true } }))
  on('session.usage', (_: unknown, e: any) => ({
    value: {
      startedAt: (NOW - 2 * 3600 - 14 * 60) * 1000,
      cost: { usd: 2.5 },
      context: e?.breakdown ? context : { ...(context as any), breakdown: undefined },
      rateLimits: limits,
    },
  }))
  on('clock.now', () => ({ value: NOW * 1000 }))
  on('env.get', () => ({ value: undefined }))
  on('session.start', (_: unknown, e: any) => ({ cwd: e.cwd }))
}

function engineDraws(on: any) {
  on('ui.render', ($: any, e: any) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
}

test('maths matches the bar on every shared vector', () => {
  for (const [off, win, used, pace, fc] of VECTORS) {
    expect(pacingTarget(NOW + off, win, NOW)).toBe(pace)
    expect(forecast(NOW + off, win, used, NOW)).toBe(fc)
  }
})

test('the terminal bar keeps the pace marker inside the fill', () => {
  // 10 cells, 80% used, pace 60%: marker at cell 6, inside the 8 filled cells.
  expect(barSegments(80, 60, 10)).toEqual([
    { kind: 'fill', text: '██████' },
    { kind: 'pace', text: '│' },
    { kind: 'fill', text: '█' },
    { kind: 'rest', text: '░░' },
  ])
  expect(barSegments(0, null, 4)).toEqual([{ kind: 'rest', text: '░░░░' }])
})

test('the pane shows both windows on every surface', async ($, on) => {
  engine(on, LIMITS)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  const term = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await term.find({ type: 'Text', text: /limit in/ }))?.text).toBe('▲ At this rate you hit the limit in 45m')
  await term.unmount()
  for (const surface of ['desktop', 'vscode'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /^5-HOUR$/ }))?.text).toBe('5-HOUR')
    expect((await ui.find({ type: 'Text', text: /over pace by/ }))?.text).toBe('over pace by 20')
    expect((await ui.find({ type: 'Text', text: /hit the limit/ }))?.text).toBe('▲ At this rate you hit the limit in 45m')
    expect((await ui.find({ type: 'Text', text: /under pace by/ }))?.text).toBe('under pace by 6')
    expect((await ui.find({ type: 'Text', text: /not reached/ }))?.text).toBe('Limit not reached before reset at this rate')
    expect((await ui.find({ type: 'Text', text: /resets in 6d/ }))?.text).toBe('resets in 6d0h')
    // the pace marker carries its own label on the drawn bar
    expect(JSON.stringify(await ui.drawn()).includes('>60%</text>')).toBe(true)
    await ui.unmount()
  }
})

test('the pane waits before the first reply', async ($, on) => {
  engine(on, [], [], { window: 400_000 })
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'vscode' })
  expect((await ui.find({ type: 'Text', text: /Waiting/ }))?.text).toBe('Waiting for the first reply.')
  await ui.unmount()
})

test('a per-model weekly cap replaces the all-models bar when it binds first', async ($, on) => {
  engine(on, [...LIMITS, { kind: 'seven_day_opus', percentUsed: 41, resetsAt: iso(NOW + 6 * 86400) }])
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'vscode' })
  expect((await ui.find({ type: 'Text', text: /WEEKLY/ }))?.text).toBe('WEEKLY (OPUS)')
  expect((await ui.find({ type: 'Text', text: /^41%$/ }))?.text).toBe('41%')
  await ui.unmount()
})

test('the band draws on desktop and stays out of the terminal', async ($, on) => {
  engine(on, LIMITS)
  engineDraws(on)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  const desk = await $.ui.mount({ ...BAND, surface: 'desktop' } as any)
  expect((await desk.find({ type: 'Text', text: /▲45m/ }))?.text).toBe('▲45m')
  await desk.unmount()
  const term = await $.ui.mount({ ...BAND, surface: 'terminal' } as any)
  expect((await term.find({ type: 'Text', text: /engine/ }))?.text).toBe('engine')
  await term.unmount()
})

test('band=false leaves the band to the engine', { options: { band: false } }, async ($, on) => {
  engine(on, LIMITS)
  engineDraws(on)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  const desk = await $.ui.mount({ ...BAND, surface: 'desktop' } as any)
  expect((await desk.find({ type: 'Text', text: /engine/ }))?.text).toBe('engine')
  await desk.unmount()
})

test('a pinned theme option paints the bars in that palette', { options: { theme: 'dracula' } }, async ($, on) => {
  engine(on, LIMITS)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  const drawn = JSON.stringify(await ui.drawn())
  expect(drawn.includes('#50fa7b')).toBe(true) // dracula ramp start
  expect(drawn.includes('#2ecc40')).toBe(false) // not the default heat ramp
  await ui.unmount()
})

test('the theme picker saves the plugin option and repaints at once', async ($, on) => {
  engine(on, LIMITS)
  const sets: any[] = []
  on('config.set', (_: unknown, e: any) => (sets.push({ key: e.key, value: e.value }), { value: e.value }))
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'vscode' })
  expect(JSON.stringify(await ui.drawn()).includes('#2ecc40')).toBe(true)
  await $.ui.select({ plugin: 'pacing-mod', key: 'theme', value: 'nord' })
  expect(sets).toEqual([{ key: 'pacing-mod.theme', value: 'nord' }])
  expect(JSON.stringify(await ui.drawn()).includes('#a3be8c')).toBe(true) // nord ramp start
  await ui.unmount()
})

test('toasts fire once per window and never with toasts=false', async ($, on) => {
  engine(on, LIMITS)
  const toasts: string[] = []
  on('ui.toast', (_: unknown, e: any) => (toasts.push(e.text), { value: undefined }))
  on('session.measure', () => ({ changed: ['rateLimits'] }))
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  const measure = { context: {}, rateLimits: LIMITS, changed: ['rateLimits'] } as any
  await $.session.measure(measure)
  await $.session.measure(measure)
  expect(toasts).toEqual(['5-hour: at this rate you hit the limit in 45m'])
})

test('toasts=false stays silent', { options: { toasts: false } }, async ($, on) => {
  engine(on, LIMITS)
  const toasts: string[] = []
  on('ui.toast', (_: unknown, e: any) => (toasts.push(e.text), { value: undefined }))
  on('session.measure', () => ({ changed: ['rateLimits'] }))
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.session.measure({ context: {}, rateLimits: LIMITS, changed: ['rateLimits'] } as any)
  expect(toasts).toEqual([])
})

test('the context card shows the fill, tokens and the auto-compact point', async ($, on) => {
  engine(on, LIMITS)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  for (const surface of ['desktop', 'vscode'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /^CONTEXT$/ }))?.text).toBe('CONTEXT')
    expect((await ui.find({ type: 'Text', text: /^25%$/ }))?.text).toBe('25%')
    expect((await ui.find({ type: 'Text', text: /100k used/ }))?.text).toBe('100k used')
    expect((await ui.find({ type: 'Text', text: /to auto-compact/ }))?.text).toBe('267k tokens to auto-compact')
    expect((await ui.find({ type: 'Text', text: /window/ }))?.text).toBe('Opus 5.5 · 400k window')
    expect(JSON.stringify(await ui.drawn()).includes('>92%</text>')).toBe(true)
    await ui.unmount()
  }
  const term = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await term.find({ type: 'Text', text: /^Context$/ }))?.text).toBe('Context')
  await term.unmount()
})

test('context=false leaves the card out', { options: { context: false } }, async ($, on) => {
  engine(on, LIMITS)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await ui.find({ type: 'Text', text: /^CONTEXT$/ })).toBe(undefined)
  await ui.unmount()
})

test('/pacing demo shows every state and /pacing goes back to live', async ($, on) => {
  engine(on, LIMITS)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.command.run({ command: 'pacing', args: 'demo' } as any)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /^WEEKLY/ }))?.text).toBe('WEEKLY (FABLE)')
  expect((await ui.find({ type: 'Text', text: /^92%$/ }))?.text).toBe('92%')
  expect((await ui.find({ type: 'Text', text: /compacts in/ }))?.text).toBe('▲ compacts in 17k tokens')
  await ui.unmount()
  await $.command.run({ command: 'pacing', args: '' } as any)
  const live = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await live.find({ type: 'Text', text: /^WEEKLY/ }))?.text).toBe('WEEKLY')
  await live.unmount()
})

test('a closed pane leaves an Open pacing button that reopens it', async ($, on) => {
  const opened: string[] = []
  engine(on, LIMITS, opened)
  // The test kit cannot raise a person's close, so seed what the ui.close hook
  // writes: the pane closed, and the id of the transcript row it placed.
  let closed = true
  let version = 1
  on('state.get', ((_: unknown, e: any) => {
    if (e.key === 'isClosed') return { value: { value: closed, version } }
    if (e.key === 'reopenRow') return { value: { value: 'reopen-1', version: 1 } }
    return { value: undefined }
  }) as any)
  on('state.set', (_: unknown, e: any) => {
    if (e.key === 'isClosed') {
      closed = e.value
      version += 1
    }
    return { value: { isSet: true, version } }
  })
  engineDraws(on)

  const row = { plugin: 'pacing-mod', component: 'Placed', props: { id: 'reopen-1', plugin: 'pacing-mod' } } as const
  for (const surface of ['vscode', 'desktop', 'terminal'] as const) {
    const ui = await $.ui.mount({ ...row, surface } as any)
    expect((await ui.find({ type: 'Text', text: /pane closed/ }))?.text).toBe('Usage pacing pane closed.')
    await ui.unmount()
  }

  const ui = await $.ui.mount({ ...row, surface: 'vscode' } as any)
  await $.ui.press({ plugin: 'pacing-mod', key: 'reopen' } as any)
  expect(opened).toEqual(['pacing'])
  expect(closed).toBe(false)
  await ui.unmount()

  // An older row, or once reopened, draws nothing of ours.
  const old = await $.ui.mount({ ...row, props: { id: 'reopen-0', plugin: 'pacing-mod' }, surface: 'vscode' } as any)
  expect((await old.find({ type: 'Text', text: /engine/ }))?.text).toBe('engine')
  await old.unmount()
})

test('limits arriving with the first reply reach the pane, with no usage call inside measure', async ($, on) => {
  // A new chat: nothing at session start, then one measure carrying both units.
  let measuring = false
  let usageWhileMeasuring = 0
  on('command.register', () => ({ value: { command: 'pacing' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('clock.now', () => ({ value: NOW * 1000 }))
  on('env.get', () => ({ value: undefined }))
  on('session.start', (_: unknown, e: any) => ({ cwd: e.cwd }))
  on('session.usage', () => {
    if (measuring) usageWhileMeasuring += 1
    return { value: { startedAt: 0, context: { window: 400_000 }, rateLimits: [] } }
  })
  on('session.measure', () => ({ changed: ['context', 'rateLimits'] }))
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  measuring = true
  await $.session.measure({ context: { window: 400_000, tokens: 120_000, percent: 30 }, rateLimits: LIMITS, changed: ['context', 'rateLimits'] } as any)
  measuring = false
  expect(usageWhileMeasuring).toBe(0)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /^5-HOUR$/ }))?.text).toBe('5-HOUR')
  expect((await ui.find({ type: 'Text', text: /^30%$/ }))?.text).toBe('30%')
  expect((await ui.find({ type: 'Text', text: /^120k used$/ }))?.text).toBe('120k used')
  await ui.unmount()
})


test('/pacing status answers one line without opening the pane', async ($, on) => {
  const opened: string[] = []
  engine(on, LIMITS, opened)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  opened.length = 0
  const r: any = await $.command.run({ command: 'pacing', args: 'status' } as any)
  expect(r.text).toBe('5h 80% (over pace by 20, resets in 2h0m, limit in 45m at this rate) · wk 8% (under pace by 6, resets in 6d0h) · ctx 25% (267k tokens to auto-compact) · Session 2h14m · $2.50')
  expect(opened).toEqual([])
})

test('the session row shows duration and cost, and cost follows measure', async ($, on) => {
  engine(on, LIMITS)
  on('session.measure', () => ({ changed: ['cost'] }))
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /^Session/ }))?.text).toBe('Session 2h14m · $2.50')
  await ui.unmount()
  await $.session.measure({ context: {}, rateLimits: LIMITS, cost: { usd: 3.1 }, changed: ['cost'] } as any)
  const again = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await again.find({ type: 'Text', text: /^Session/ }))?.text).toBe('Session 2h14m · $3.10')
  await again.unmount()
})

test('a window reset is announced once, and notify=true also raises a native notification', { options: { notify: true } }, async ($, on) => {
  engine(on, LIMITS)
  const toasts: string[] = []
  const sent: string[] = []
  on('ui.toast', (_: unknown, e: any) => (toasts.push(e.text), { value: undefined }))
  on('ui.notify', (_: unknown, e: any) => (sent.push(e.text), { value: { isSent: true, channel: 'terminal_bell' } }))
  on('session.measure', () => ({ changed: ['rateLimits'] }))
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  const reset = [{ kind: 'five_hour', percentUsed: 0, resetsAt: iso(NOW + 7 * 3600) }, LIMITS[1]]
  await $.session.measure({ context: {}, rateLimits: reset, changed: ['rateLimits'] } as any)
  await $.session.measure({ context: {}, rateLimits: reset, changed: ['rateLimits'] } as any)
  expect(toasts).toEqual(['5-hour window reset: 0% used, resets in 7h0m'])
  expect(sent).toEqual(['5-hour window reset: 0% used, resets in 7h0m'])
})
