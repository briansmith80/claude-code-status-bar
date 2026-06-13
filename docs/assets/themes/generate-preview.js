#!/usr/bin/env node
// PREVIEW ONLY — does not touch the live swatches or the script.
// Renders the *proposed* palettes (official theme hexes, each leaned into a
// distinct character) into ./preview/ plus a PREVIEW.md comparing them to the
// current swatches. If we adopt these, they fold into generate-swatches.js and
// this file + the preview/ dir are deleted.
//
// Run: node docs/assets/themes/generate-preview.js

const fs = require('fs');
const path = require('path');

// Proposed palettes — each theme's *official* colours, in role order:
// dir, branch, model, opus accent, additions, warnings/cost, removals, pacing.
const PROPOSED = {
  // unchanged: tracks the terminal's own ANSI palette (representative set)
  default:       ['#11a8cd', '#bc3fbc', '#2472c8', '#ff8700', '#0dbc79', '#e5e510', '#cd3131', '#ff00af'],
  // MUTED — cool steel/slate, the lowest-saturation palette (Nord), led by
  // steel #81a1c1 (not the lighter frost) so it reads clearly subdued
  nord:          ['#81a1c1', '#b48ead', '#88c0d0', '#d08770', '#a3be8c', '#ebcb8b', '#bf616a', '#5e81ac'],
  // NEON — electric, maximum saturation (Dracula official)
  dracula:       ['#bd93f9', '#ff79c6', '#8be9fd', '#ffb86c', '#50fa7b', '#f1fa8c', '#ff5555', '#ff79c6'],
  // EARTHY — vintage, desaturated, teal + amber (Solarized official)
  solarized:     ['#2aa198', '#6c71c4', '#268bd2', '#cb4b16', '#859900', '#b58900', '#dc322f', '#d33682'],
  // DEEP — saturated blue night with hot neon accents (Tokyo Night official)
  'tokyo-night': ['#7aa2f7', '#bb9af7', '#7dcfff', '#ff9e64', '#9ece6a', '#e0af68', '#f7768e', '#ff007c'],
  // SOFT PASTEL — warm + light, led by lavender/sky (Catppuccin), distinct
  // from nord's cool steel on hue, lightness and temperature
  catppuccin:    ['#b4befe', '#cba6f7', '#89dceb', '#fab387', '#a6e3a1', '#f9e2af', '#f38ba8', '#f5c2e7'],
  // digital-rain phosphor green — monochrome, separated by brightness
  matrix:        ['#00ff41', '#22ff88', '#00cc33', '#aaffaa', '#00ff00', '#9eff5e', '#008f11', '#d6ffd6'],
  // unchanged: no colour, neutral grey ramp
  mono:          ['#e6edf3', '#c9d1d9', '#adbac7', '#8b949e', '#6e7681', '#545d68', '#444c56', '#373e47'],
};

const CHARACTER = {
  default: 'BOLD — bright primary ANSI (your terminal’s own palette)',
  nord: 'MUTED — cool steel/slate, the most subdued theme',
  dracula: 'NEON — electric, maximum saturation',
  solarized: 'EARTHY — vintage, desaturated, teal + amber',
  'tokyo-night': 'DEEP — saturated blue night with hot neon accents',
  catppuccin: 'SOFT PASTEL — warm lavender, peach, pink',
  matrix: 'MONOCHROME — phosphor digital-rain green',
  mono: 'GREYSCALE — no colour',
};

const W = 400, H = 56, SW = 26, START = 118, STEP = 34, SY = 15;

function svg(name, colours) {
  const swatches = colours.map((c, i) =>
    `  <rect x="${START + i * STEP}" y="${SY}" width="${SW}" height="${SW}" rx="5" fill="${c}"/>`
  ).join('\n');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" role="img" aria-label="${name} proposed colour theme palette">
  <rect x="0.5" y="0.5" width="${W - 1}" height="${H - 1}" rx="8" fill="#0d1117" stroke="#30363d"/>
  <text x="14" y="33" font-family="ui-monospace,SFMono-Regular,Menlo,Consolas,monospace" font-size="14" font-weight="600" fill="#e6edf3">${name}</text>
${swatches}
</svg>
`;
}

const dir = path.join(__dirname, 'preview');
fs.mkdirSync(dir, { recursive: true });

let md = `# Theme palette preview — current vs proposed\n\n`;
md += `Proposed = each theme's **official** palette, deliberately spread across a `;
md += `saturation/temperature ladder so no two read alike: **NEON** (dracula) · `;
md += `**BOLD** (default) · **DEEP** (tokyo-night) · **SOFT PASTEL** (catppuccin) · `;
md += `**EARTHY** (solarized) · **MUTED** (nord) · **MONOCHROME** (matrix) · `;
md += `**GREYSCALE** (mono). Shown here in truecolour (the best case; terminals `;
md += `without truecolour fall back to the nearest 256-colour). Swatch order: `;
md += `directory · branch · model · Opus accent · additions · warnings/cost · `;
md += `removals · pacing.\n\n`;
md += `| Theme | Current | Proposed | Character |\n|---|---|---|---|\n`;

for (const [name, colours] of Object.entries(PROPOSED)) {
  fs.writeFileSync(path.join(dir, `${name}.svg`), svg(name, colours));
  md += `| \`${name}\` | <img src="../${name}.svg" width="360"> | <img src="${name}.svg" width="360"> | ${CHARACTER[name]} |\n`;
  console.log('wrote', path.join(dir, `${name}.svg`));
}

fs.writeFileSync(path.join(dir, 'PREVIEW.md'), md);
console.log('wrote', path.join(dir, 'PREVIEW.md'));
