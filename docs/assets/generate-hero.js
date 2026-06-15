#!/usr/bin/env node
// README hero graphic -> docs/assets/hero.svg
// A marketing-hero layout (logo + headline + subtitle + product panel +
// feature columns + footer) where the product panel is the REAL status bar,
// lifted verbatim from terminal-demo.svg so it cannot drift from what the tool
// prints. This is the image at the top of the README.
//   node docs/assets/generate-hero.js

const fs = require('fs');
const path = require('path');
const dir = __dirname;

// Pull the two real status-bar lines out of terminal-demo.svg.
const td = fs.readFileSync(path.join(dir, 'terminal-demo.svg'), 'utf8');
const texts = [...td.matchAll(/<text[^>]*>([\s\S]*?)<\/text>/g)].map(m => m[1]);
const metrics = texts.find(t => t.includes('Opus 4.8'));   // line 1
const activity = texts.find(t => t.includes('SignupForm')); // line 2

const MONO = "ui-monospace, 'Cascadia Code', Consolas, 'SF Mono', Menlo, monospace";
const SANS = "'Segoe UI', -apple-system, Roboto, Helvetica, Arial, sans-serif";
const W = 1280, H = 790, CX = W / 2;

// Feature columns use the product's own glyphs as icons.
const FEATURES = [
  { g: '│', c: '#bc8cff', t: 'Stay on pace',     d: ['Usage bars with pacing', 'markers keep you aligned with', 'your 5-hour and weekly quotas'] },
  { g: '▲', c: '#d29922', t: 'Protect quality',  d: ['A context-window marker', 'warns you before the', 'auto-compact danger zone'] },
  { g: '⚒', c: '#39c5cf', t: 'See the activity', d: ['A live line shows running', 'tools, subagents, and', 'real-time task progress'] },
  { g: '$', c: '#3fb950', t: 'Track your spend', d: ['Real-time session cost and', 'burn rate, so there are', 'no surprises'] },
];
const colX = [160, 480, 800, 1120];

let feat = '';
FEATURES.forEach((f, i) => {
  const cx = colX[i], iy = 512;
  feat += `\n  <circle cx="${cx}" cy="${iy}" r="23" fill="${f.c}" fill-opacity="0.14" stroke="${f.c}" stroke-opacity="0.55"/>`;
  feat += `\n  <text x="${cx}" y="${iy + 7}" text-anchor="middle" font-family="${MONO}" font-size="20" fill="${f.c}">${f.g}</text>`;
  feat += `\n  <text x="${cx}" y="${iy + 58}" text-anchor="middle" font-family="${SANS}" font-size="18" font-weight="700" fill="#e6edf3">${f.t}</text>`;
  f.d.forEach((line, j) => {
    feat += `\n  <text x="${cx}" y="${iy + 84 + j * 20}" text-anchor="middle" font-family="${SANS}" font-size="13.5" fill="#8b949e">${line}</text>`;
  });
});

const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-labelledby="heroTitle">
  <title id="heroTitle">claude-code-status-bar: stop discovering limits when it's too late</title>
  <defs>
    <radialGradient id="glow" cx="50%" cy="4%" r="72%">
      <stop offset="0%" stop-color="#d97757" stop-opacity="0.18"/>
      <stop offset="55%" stop-color="#7c5cff" stop-opacity="0.06"/>
      <stop offset="100%" stop-color="#d97757" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="${W}" height="${H}" fill="#0b0e16"/>
  <rect width="${W}" height="${H}" fill="url(#glow)"/>

  <!-- logo + wordmark (roughly centred) -->
  <rect x="${CX - 165}" y="34" width="30" height="30" rx="8" fill="#d97757"/>
  <text x="${CX - 150}" y="56" text-anchor="middle" font-family="${MONO}" font-size="17" fill="#0b0e16">◆</text>
  <text x="${CX - 120}" y="58" font-family="${MONO}" font-size="22" font-weight="700"><tspan fill="#d97757">claude</tspan><tspan fill="#e6edf3">-code-status-bar</tspan></text>

  <!-- headline -->
  <text x="${CX}" y="150" text-anchor="middle" font-family="${SANS}" font-size="56" font-weight="800" fill="#e6edf3">Stop discovering limits</text>
  <text x="${CX}" y="212" text-anchor="middle" font-family="${SANS}" font-size="56" font-weight="800" fill="#d97757">when it's too late.</text>

  <!-- subtitle -->
  <text x="${CX}" y="256" text-anchor="middle" font-family="${SANS}" font-size="18" fill="#9aa4b2">Real-time visibility into your Claude Code usage, context window, active work, and session cost, right where you can see it.</text>

  <!-- product panel: the real status bar -->
  <rect x="40" y="300" width="1200" height="150" rx="14" fill="#0d1117" stroke="#30363d" stroke-width="1"/>
  <circle cx="68" cy="326" r="5" fill="#f85149"/><circle cx="88" cy="326" r="5" fill="#d29922"/><circle cx="108" cy="326" r="5" fill="#3fb950"/>
  <text x="1212" y="331" text-anchor="end" font-family="${MONO}" font-size="12" fill="#8b949e">Claude Code</text>
  <line x1="40" y1="344" x2="1240" y2="344" stroke="#30363d" stroke-opacity="0.6"/>
  <text x="64" y="386" font-family="${MONO}" font-size="12.5" xml:space="preserve">${metrics}</text>
  <text x="64" y="416" font-family="${MONO}" font-size="12.5" fill="#8b949e" xml:space="preserve">${activity}</text>
${feat}

  <!-- footer -->
  <text x="${CX}" y="730" text-anchor="middle" font-family="${SANS}" font-size="17"><tspan fill="#9aa4b2">Better visibility. </tspan><tspan fill="#e6edf3">Smarter sessions. </tspan><tspan fill="#d97757">Better outcomes.</tspan></text>
</svg>
`;
fs.writeFileSync(path.join(dir, 'hero.svg'), svg);
console.log('wrote hero.svg', W + 'x' + H);
