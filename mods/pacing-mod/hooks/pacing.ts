// Pacing maths. Mirrors calc_pacing_target / calc_forecast / build_progress_bar
// in statusline-command.sh (integer maths, same floors), so the mod and the
// bar agree. tests/vectors.ts holds the shared cases; tests/pacing_mod.bats in
// the repo runs the same vectors through the bash functions.

export const WINDOW_SECS: Record<string, number> = {
  five_hour: 5 * 3600,
  seven_day: 7 * 86400,
}

// Percent of the window elapsed, rounded: where usage "should" be.
export function pacingTarget(resetEpoch: number, windowSecs: number, now: number): number {
  const start = resetEpoch - windowSecs
  let elapsed = now - start
  if (elapsed < 0) elapsed = 0
  if (elapsed > windowSecs) elapsed = windowSecs
  return Math.floor((elapsed * 100 + Math.floor(windowSecs / 2)) / windowSecs)
}

// Time to hit 100% at the current burn rate, only when that is before the
// reset (over pace). null otherwise.
export function forecast(resetEpoch: number, windowSecs: number, usedPct: number, now: number): string | null {
  if (!Number.isInteger(usedPct) || usedPct <= 0) return null
  const toReset = resetEpoch - now
  if (toReset <= 0) return null
  let elapsed = now - (resetEpoch - windowSecs)
  if (elapsed < 120) return null
  if (elapsed > windowSecs) elapsed = windowSecs
  if (usedPct >= 100) return 'now'
  const secs = Math.floor(((100 - usedPct) * elapsed) / usedPct)
  if (secs >= toReset) return null
  return duration(secs)
}

// Countdown label, same shape as the bar's usage_label=countdown.
export function duration(secs: number): string {
  if (secs <= 0) return 'now'
  const dd = Math.floor(secs / 86400)
  const hh = Math.floor((secs % 86400) / 3600)
  const mm = Math.floor((secs % 3600) / 60)
  if (dd > 0) return `${dd}d${hh}h`
  if (hh > 0) return `${hh}h${mm}m`
  if (mm > 0) return `${mm}m`
  return '<1m'
}

// Short token counts, as the apps print them: 99.2k, 350k, 1.2M.
export function fmtTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1).replace(/\.0$/, '')}M`
  if (n >= 100_000) return `${Math.round(n / 1000)}k`
  if (n >= 1_000) return `${(n / 1000).toFixed(1).replace(/\.0$/, '')}k`
  return String(n)
}

export function toEpoch(iso: string | undefined): number | null {
  if (!iso) return null
  const ms = Date.parse(iso)
  return Number.isFinite(ms) ? Math.floor(ms / 1000) : null
}

export type BarSegment = { kind: 'fill' | 'rest' | 'pace'; text: string }

// Text bar for the terminal, cell for cell as build_progress_bar draws it:
// the pace marker `│` sits at its cell whether that cell is filled or not.
export function barSegments(used: number, pace: number | null, width: number): BarSegment[] {
  const filled = Math.floor((Math.max(0, Math.min(100, used)) * width) / 100)
  let target = -1
  if (pace !== null && pace >= 0 && pace <= 100) target = Math.min(width - 1, Math.floor((pace * width) / 100))
  const out: BarSegment[] = []
  for (let i = 0; i < width; i++) {
    const kind: BarSegment['kind'] = i === target ? 'pace' : i < filled ? 'fill' : 'rest'
    const ch = kind === 'pace' ? '│' : kind === 'fill' ? '█' : '░'
    const last = out[out.length - 1]
    if (last && last.kind === kind) last.text += ch
    else out.push({ kind, text: ch })
  }
  return out
}
