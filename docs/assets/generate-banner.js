#!/usr/bin/env node
// Regenerates the README banners (banner-dark.svg + banner-light.svg).
//
//   node docs/assets/generate-banner.js
//
// The banner is a slim wordmark + tagline over a terminal panel that showcases
// the real status bar in several themes. Each row's bar is lifted verbatim from
// the matching docs/assets/themes/<theme>-demo.svg, so the banner can never
// drift from what `--demo` actually prints. Regenerate the theme demos first
// (docs/assets/themes/generate-theme-demos.sh) if the scene or palettes change.

const fs = require('fs');
const path = require('path');

const THEMES = ['default', 'tokyo-night', 'dracula', 'matrix'];
const FONT = "ui-monospace, 'Cascadia Code', Consolas, 'SF Mono', Menlo, monospace";
const SANS = "'Segoe UI', -apple-system, Roboto, Helvetica, Arial, sans-serif";
const themesDir = path.join(__dirname, 'themes');

// Inner tspans (the rendered bar) and the dir colour (first fill) per theme.
function bar(theme) {
  const svg = fs.readFileSync(path.join(themesDir, `${theme}-demo.svg`), 'utf8');
  const inner = svg.match(/<text[^>]*>([\s\S]*?)<\/text>/)[1];
  const dirColour = (inner.match(/fill="(#[0-9a-fA-F]+)"/) || [, '#8b949e'])[1];
  return { inner, dirColour };
}

const W = 1200;
const PANEL_TOP = 96, ROW_H = 40, TITLEBAR = 36, PANEL_PAD_B = 18;
const PANEL_H = TITLEBAR + THEMES.length * ROW_H + PANEL_PAD_B;
const H = PANEL_TOP + PANEL_H + 20;

function banner({ cardFill, cardStroke, titleRest, tagline, meta }) {
  let rows = '';
  THEMES.forEach((t, i) => {
    const { inner, dirColour } = bar(t);
    const y = PANEL_TOP + TITLEBAR + 30 + i * ROW_H;
    rows +=
      `\n  <text x="44" y="${y}" font-family="${FONT}" font-size="12" font-weight="600" fill="${dirColour}">${t}</text>` +
      `\n  <g transform="translate(168,${y - 14})"><text font-family="${FONT}" font-size="13.5" xml:space="preserve">${inner}</text></g>`;
  });
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-labelledby="bannerTitle">
  <title id="bannerTitle">claude-code-status-bar: usage limits, context, git state and live activity in your Claude Code status bar, shown across four colour themes</title>
  <rect x="2" y="2" width="${W - 4}" height="${H - 4}" rx="16" fill="${cardFill}" stroke="${cardStroke}" stroke-width="1"/>
  <text x="40" y="52" font-family="${FONT}" font-size="27" font-weight="700" letter-spacing="-1"><tspan fill="#d97757">claude</tspan><tspan fill="${titleRest}">-code-status-bar</tspan></text>
  <text x="42" y="78" font-family="${SANS}" font-size="14" fill="${tagline}">Usage limits, context, git state &amp; live activity under every response</text>
  <text x="${W - 40}" y="52" text-anchor="end" font-family="${FONT}" font-size="12.5" fill="${meta}">8 themes · pure bash · macOS / Linux / Windows</text>
  <rect x="24" y="${PANEL_TOP}" width="${W - 48}" height="${PANEL_H}" rx="10" fill="#161b22" stroke="#30363d" stroke-width="1"/>
  <circle cx="46" cy="${PANEL_TOP + 20}" r="4.5" fill="#f85149"/><circle cx="62" cy="${PANEL_TOP + 20}" r="4.5" fill="#d29922"/><circle cx="78" cy="${PANEL_TOP + 20}" r="4.5" fill="#3fb950"/>
  <text x="${W - 40}" y="${PANEL_TOP + 24}" text-anchor="end" font-family="${FONT}" font-size="11" fill="#8b949e">Claude Code</text>
  <line x1="24" y1="${PANEL_TOP + TITLEBAR}" x2="${W - 24}" y2="${PANEL_TOP + TITLEBAR}" stroke="#30363d" stroke-opacity="0.6"/>${rows}
</svg>
`;
}

const dark = banner({ cardFill: '#0d1117', cardStroke: '#30363d', titleRest: '#e6edf3', tagline: '#8b949e', meta: '#6e7681' });
const light = banner({ cardFill: '#ffffff', cardStroke: '#d0d7de', titleRest: '#1f2328', tagline: '#57606a', meta: '#6e7681' });
fs.writeFileSync(path.join(__dirname, 'banner-dark.svg'), dark);
fs.writeFileSync(path.join(__dirname, 'banner-light.svg'), light);
console.log('wrote banner-dark.svg + banner-light.svg');
