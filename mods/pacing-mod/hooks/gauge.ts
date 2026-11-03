// SVG bar for the graphical surfaces (Desktop, VS Code), in the status bar's
// own theme colours. Drawn as an image, so it cannot follow the app's light or
// dark mode: the track is a translucent mid-grey and the fills are saturated,
// so both read on either background. The gradient spans the full width, as
// the bar's per-cell ramp does, so the fill's end colour says how far along
// you are. The marker `│` sits where an even spend (or the auto-compact point)
// would be, labelled with its percent on the full-size bar.

import type { Look } from './theme'
import { fillFor } from './theme'

let seq = 0

export type GaugeSize = 'full' | 'mini'

export function gaugeSvg(look: Look, used: number, marker: number | null, size: GaugeSize = 'full'): string {
  const full = size === 'full'
  const W = full ? 300 : 96
  const BAR = full ? 8 : 6
  const Y = full ? 16 : 5
  const H = full ? 28 : 16
  const r = BAR / 2
  const id = `g${++seq}`
  const u = Math.max(0, Math.min(100, used))
  const fillW = (u / 100) * W
  const colours = fillFor(look, used)
  const paint = colours.length > 1 ? `url(#${id})` : colours[0]!
  const defs = colours.length > 1
    ? `<defs><linearGradient id="${id}" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="${W}" y2="0">` +
      colours.map((c, i) => `<stop offset="${(i / (colours.length - 1)) * 100}%" stop-color="${c}"/>`).join('') +
      `</linearGradient></defs>`
    : ''
  let tick = ''
  if (marker !== null && marker >= 0 && marker <= 100) {
    const px = Math.max(1.5, Math.min(W - 1.5, (marker / 100) * W))
    const pc = look.theme.pace
    tick =
      `<line x1="${px}" y1="${Y - 4}" x2="${px}" y2="${Y + BAR + 3}" stroke="${pc}" stroke-width="2" stroke-linecap="round"/>`
    if (full) {
      const lx = Math.max(12, Math.min(W - 12, px))
      tick +=
        `<text x="${lx}" y="9" text-anchor="middle" font-family="ui-sans-serif, system-ui, sans-serif" ` +
        `font-size="10" font-weight="600" fill="${pc}">${Math.round(marker)}%</text>`
    }
  }
  const fill = fillW > 0
    ? `<rect x="0" y="${Y}" width="${Math.max(BAR, fillW)}" height="${BAR}" rx="${r}" fill="${paint}"/>`
    : ''
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">` +
    defs +
    `<rect x="0" y="${Y}" width="${W}" height="${BAR}" rx="${r}" fill="#8a919c" fill-opacity="0.22"/>` +
    fill +
    tick +
    `</svg>`
  )
}
