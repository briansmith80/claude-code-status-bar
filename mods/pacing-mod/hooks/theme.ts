// The status bar's themes, mirrored from apply_theme / apply_palette in
// statusline-command.sh (roles: bar_ok bar_med bar_high pace ramp0..3).
// tests/pacing_mod.bats in the repo fails when the two drift apart.

export type Theme = {
  ok: string
  med: string
  high: string
  pace: string
  ramp: string[] | null // null = no gradient (mono)
}

const HEAT = ['#2ecc40', '#ffdc00', '#ff851b', '#ff4136']

const p = (s: string) => s.split(' ').map(h => `#${h}`)
const named = (ok: string, med: string, high: string, pace: string, ramp: string): Theme => ({
  ok: `#${ok}`, med: `#${med}`, high: `#${high}`, pace: `#${pace}`, ramp: p(ramp),
})

export const THEMES: Record<string, Theme> = {
  default: { ok: '#2ecc40', med: '#ffdc00', high: '#ff4136', pace: '#ff00af', ramp: HEAT },
  nord: named('a3be8c', 'ebcb8b', 'bf616a', '5e81ac', 'a3be8c ebcb8b d08770 bf616a'),
  dracula: named('50fa7b', 'f1fa8c', 'ff5555', 'ff79c6', '50fa7b f1fa8c ffb86c ff5555'),
  solarized: named('859900', 'b58900', 'dc322f', 'd33682', '859900 b58900 cb4b16 dc322f'),
  'tokyo-night': named('9ece6a', 'e0af68', 'f7768e', 'ff007c', '9ece6a e0af68 ff9e64 f7768e'),
  catppuccin: named('a6e3a1', 'f9e2af', 'f38ba8', 'f5c2e7', 'a6e3a1 94e2d5 f9e2af fab387'),
  matrix: named('008f11', '00ff00', '9eff5e', 'd6ffd6', '005f00 008f11 00cc33 00ff00'),
  mono: { ok: '#9aa4b2', med: '#9aa4b2', high: '#9aa4b2', pace: '#8a919c', ramp: null }, // mid-greys read on light and dark
}

export const THEME_NAMES = Object.keys(THEMES)

// The pane's theme picker: follow the status bar's conf, or pin one.
export const FOLLOW_BAR = 'status-bar'

export type Look = { theme: Theme; gradient: 'true' | 'false' | 'heat' }

export const DEFAULT_LOOK: Look = { theme: THEMES.default!, gradient: 'true' }

// Reads colour_theme and bar_gradient the way the bar does: the conf is
// sourced as shell, so the last uncommented assignment wins.
export function parseConf(text: string): Look {
  let themeName = 'default'
  let gradient: Look['gradient'] = 'true'
  for (const line of text.split(/\r?\n/)) {
    const m = /^\s*(colour_theme|bar_gradient)\s*=\s*["']?([A-Za-z-]+)["']?/.exec(line)
    if (!m) continue
    if (m[1] === 'colour_theme') themeName = m[2]!
    else if (m[2] === 'true' || m[2] === 'false' || m[2] === 'heat') gradient = m[2]
  }
  return { theme: THEMES[themeName] ?? THEMES.default!, gradient }
}

// The conf's look, with the plugin's own theme option pinned over it when set.
export function resolveLook(confText: string | null, override: string): Look {
  const base = confText === null ? DEFAULT_LOOK : parseConf(confText)
  const pinned = override === FOLLOW_BAR ? null : THEMES[override]
  return pinned ? { ...base, theme: pinned } : base
}

// What the fill is painted with: a gradient's stops, or one flat colour.
export function fillFor(look: Look, used: number): string[] {
  const t = look.theme
  if (look.gradient === 'heat' && t.ramp) return HEAT
  if (look.gradient === 'true' && t.ramp) return t.ramp
  return [used >= 80 ? t.high : used >= 50 ? t.med : t.ok]
}
