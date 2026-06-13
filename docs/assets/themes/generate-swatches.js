#!/usr/bin/env node
// Generates one SVG palette swatch per colour theme into this directory.
// Run: node docs/assets/themes/generate-swatches.js
//
// The hex values are derived from the xterm-256 codes used by apply_theme()
// in statusline-command.sh. If a theme's palette changes there, update the
// matching row below and re-run this script. Swatch order matches the role
// labels in the README table: dir, branch, model, opus, add, warn, del, pace.

const fs = require('fs');
const path = require('path');

// Palettes resolved to hex. The 256-colour themes are exact; `default` uses a
// representative modern ANSI palette (the real colours come from the user's
// terminal) and `mono` is a neutral grey ramp (it emits no colour at all).
const ROLES = ['dir', 'branch', 'model', 'opus', 'add', 'warn', 'del', 'pace'];
const THEMES = {
  default:       ['#11a8cd', '#bc3fbc', '#2472c8', '#ff8700', '#0dbc79', '#e5e510', '#cd3131', '#ff00af'],
  nord:          ['#5fd7ff', '#af87af', '#87afff', '#d7875f', '#87af87', '#d7af5f', '#d78787', '#ff00af'],
  dracula:       ['#af87ff', '#ff87d7', '#87d7ff', '#ffaf5f', '#5fff87', '#ffff87', '#ff8787', '#ff87d7'],
  solarized:     ['#00afaf', '#5f5faf', '#0087ff', '#d75f00', '#5f8700', '#af8700', '#d70000', '#af005f'],
  'tokyo-night': ['#87afff', '#af87ff', '#87d7ff', '#ffaf5f', '#afd75f', '#d7af5f', '#ff5f87', '#ff0087'],
  catppuccin:    ['#87afff', '#d7afff', '#87d7d7', '#ffaf87', '#afd787', '#ffd7af', '#ff87af', '#ffafd7'],
  matrix:        ['#00ff5f', '#00ff87', '#00d700', '#afff87', '#00ff00', '#afff00', '#008700', '#d7ffd7'],
  mono:          ['#e6edf3', '#c9d1d9', '#adbac7', '#8b949e', '#6e7681', '#545d68', '#444c56', '#373e47'],
};

const W = 400, H = 56, SW = 26, START = 118, STEP = 34, SY = 15;

function svg(name, colours) {
  const swatches = colours.map((c, i) =>
    `  <rect x="${START + i * STEP}" y="${SY}" width="${SW}" height="${SW}" rx="5" fill="${c}"/>`
  ).join('\n');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" role="img" aria-label="${name} colour theme palette">
  <rect x="0.5" y="0.5" width="${W - 1}" height="${H - 1}" rx="8" fill="#0d1117" stroke="#30363d"/>
  <text x="14" y="33" font-family="ui-monospace,SFMono-Regular,Menlo,Consolas,monospace" font-size="14" font-weight="600" fill="#e6edf3">${name}</text>
${swatches}
</svg>
`;
}

for (const [name, colours] of Object.entries(THEMES)) {
  const out = path.join(__dirname, `${name}.svg`);
  fs.writeFileSync(out, svg(name, colours));
  console.log('wrote', out);
}
