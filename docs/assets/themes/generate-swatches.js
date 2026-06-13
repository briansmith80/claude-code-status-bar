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
  // BOLD — bright primary ANSI (representative; default tracks your terminal)
  default:       ['#11a8cd', '#bc3fbc', '#2472c8', '#ff8700', '#0dbc79', '#e5e510', '#cd3131', '#ff00af'],
  // MUTED — cool steel/slate (Nord)
  nord:          ['#81a1c1', '#b48ead', '#88c0d0', '#d08770', '#a3be8c', '#ebcb8b', '#bf616a', '#5e81ac'],
  // NEON — electric, maximum saturation (Dracula)
  dracula:       ['#bd93f9', '#ff79c6', '#8be9fd', '#ffb86c', '#50fa7b', '#f1fa8c', '#ff5555', '#ff79c6'],
  // EARTHY — vintage, desaturated, teal + amber (Solarized)
  solarized:     ['#2aa198', '#6c71c4', '#268bd2', '#cb4b16', '#859900', '#b58900', '#dc322f', '#d33682'],
  // DEEP — midnight royal-blue + violet base, neon accents (Tokyo Night)
  'tokyo-night': ['#5a7bf0', '#9d7cd8', '#7dcfff', '#ff9e64', '#9ece6a', '#e0af68', '#f7768e', '#ff007c'],
  // SOFT PASTEL — warm lavender/peach (Catppuccin Mocha)
  catppuccin:    ['#b4befe', '#cba6f7', '#89dceb', '#fab387', '#a6e3a1', '#f9e2af', '#f38ba8', '#f5c2e7'],
  // MONOCHROME — phosphor digital-rain green
  matrix:        ['#00ff41', '#22ff88', '#00cc33', '#aaffaa', '#00ff00', '#9eff5e', '#008f11', '#d6ffd6'],
  // GREYSCALE — no colour
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
