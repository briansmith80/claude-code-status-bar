#!/usr/bin/env node
// Converts a single line of ANSI-coloured terminal output (truecolour, 256, or
// basic SGR) into a self-contained SVG "chip" that renders the same colours.
//
//   <ansi producer> | node ansi-to-svg.js > out.svg
//   node ansi-to-svg.js in.ansi out.svg
//
// Used by generate-theme-demos.sh to turn the real `statusline-command.sh`
// output into the per-theme preview images in the README. Rendering the actual
// script output (rather than re-deriving the palette here) keeps the previews
// honest: the gradient cells are exactly the bytes the bar prints.

const fs = require('fs');

// ── Palette for basic SGR codes (truecolour/256 carry their own RGB) ─────
// A representative dark-terminal palette so the `default` theme (which uses the
// terminal's own ANSI colours) and any basic-ANSI output look like a real
// modern terminal. Truecolour themes don't touch this.
const BASIC = ['#484f58', '#f85149', '#3fb950', '#d29922', '#58a6ff', '#bc8cff', '#39c5cf', '#b1bac4'];
const BRIGHT = ['#6e7681', '#ff7b72', '#56d364', '#e3b341', '#79c0ff', '#d2a8ff', '#56d4dd', '#f0f6fc'];
const DEFAULT_FG = '#c9d1d9'; // reset / no colour (also the whole `mono` theme)
const CUBE = [0, 95, 135, 175, 215, 255];

const hex = (r, g, b) => '#' + [r, g, b].map(n => n.toString(16).padStart(2, '0')).join('');

function xterm256(n) {
  if (n < 8) return BASIC[n];
  if (n < 16) return BRIGHT[n - 8];
  if (n >= 232) { const v = 8 + (n - 232) * 10; return hex(v, v, v); }
  n -= 16;
  return hex(CUBE[Math.floor(n / 36)], CUBE[Math.floor((n % 36) / 6)], CUBE[n % 6]);
}

// Resolve one SGR escape's parameter list to a foreground colour (or null=reset).
// Returns {fg} only for the codes line 1 of the status bar emits.
function applySgr(params, fg) {
  for (let i = 0; i < params.length; i++) {
    const p = params[i];
    if (p === 0 || Number.isNaN(p)) fg = null;
    else if (p === 39) fg = null;
    else if (p === 38 && params[i + 1] === 5) { fg = xterm256(params[i + 2]); i += 2; }
    else if (p === 38 && params[i + 1] === 2) { fg = hex(params[i + 2], params[i + 3], params[i + 4]); i += 4; }
    else if (p >= 30 && p <= 37) fg = BASIC[p - 30];
    else if (p >= 90 && p <= 97) fg = BRIGHT[p - 90];
    // bold/faint (1/2/22) ignored: line 1 of the bar doesn't use them.
  }
  return fg;
}

const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function ansiToRuns(input) {
  // Tokenise into {text, fg} runs, merging adjacent same-colour text.
  const runs = [];
  let fg = null, buf = '';
  const flush = () => { if (buf) { runs.push({ text: buf, fg }); buf = ''; } };
  for (let i = 0; i < input.length; i++) {
    const c = input[i];
    if (c === '\x1b' && input[i + 1] === '[') {
      let j = i + 2, raw = '';
      while (j < input.length && input[j] !== 'm') { raw += input[j]; j++; }
      flush();
      fg = applySgr(raw.split(';').map(x => x === '' ? 0 : parseInt(x, 10)), fg);
      i = j; // skip to the 'm'
    } else if (c === '\n' || c === '\r') {
      break; // first line only
    } else {
      buf += c;
    }
  }
  flush();
  return runs;
}

const FONT = "ui-monospace, 'Cascadia Code', Consolas, 'SF Mono', Menlo, monospace";
const CW = 8.4, FS = 14, PAD_X = 16, PAD_TOP = 13;
const colsOf = runs => runs.reduce((n, r) => n + [...r.text].length, 0);
const runsToTspans = runs =>
  runs.map(r => `<tspan fill="${r.fg || DEFAULT_FG}">${esc(r.text)}</tspan>`).join('');

function toSvg(input, opts = {}) {
  const runs = ansiToRuns(input);
  const W = Math.ceil(PAD_X * 2 + colsOf(runs) * CW);
  const H = opts.height || 44;
  const baseline = PAD_TOP + FS;
  const tspans = runsToTspans(runs);
  const label = opts.label
    ? `<title>${esc(opts.label)} theme preview</title>` : '';
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(opts.label || 'status bar')} preview">
  ${label}
  <rect x="0.5" y="0.5" width="${W - 1}" height="${H - 1}" rx="8" fill="#0d1117" stroke="#30363d"/>
  <text x="${PAD_X}" y="${baseline}" xml:space="preserve" font-family="${FONT}" font-size="${FS}">${tspans}</text>
</svg>
`;
}

// Build ONE self-contained SVG that flip-books through several ANSI frames, the
// way generate-demo-gif.js does but as a crisp, dependency-free vector. Each
// frame is a <g> layer whose opacity is toggled on for its time slot with a
// discrete SMIL <animate>, so the frames swap with no cross-fade (a true
// flipbook). SMIL plays in <img>-embedded SVG on GitHub (no JS needed).
//   frames: array of raw ANSI strings (first line of each is used)
//   opts.delays: per-frame ms (defaults mirror the GIF: hold first/last longer)
function toAnimatedSvg(frames, opts = {}) {
  const runsPer = frames.map(f => ansiToRuns(f));
  const W = Math.ceil(PAD_X * 2 + Math.max(...runsPer.map(colsOf)) * CW);
  const H = opts.height || 44;
  const baseline = PAD_TOP + FS;
  const n = frames.length;
  const delays = opts.delays || frames.map((_, i) => (i === n - 1 ? 1700 : i === 0 ? 900 : 680));
  const total = delays.reduce((a, b) => a + b, 0);
  // Cumulative boundaries in [0,1]: keyTimes has n+1 entries, values match.
  const bounds = [0];
  let acc = 0;
  for (const d of delays) { acc += d; bounds.push(acc / total); }
  bounds[bounds.length - 1] = 1;
  const keyTimes = bounds.map(b => +b.toFixed(4)).join(';');
  const dur = (total / 1000).toFixed(2) + 's';
  const layers = runsPer.map((runs, i) => {
    const values = bounds.map((_, k) => (k === i ? 1 : 0)).join(';');
    return `  <g opacity="${i === 0 ? 1 : 0}">
    <text x="${PAD_X}" y="${baseline}" xml:space="preserve" font-family="${FONT}" font-size="${FS}">${runsToTspans(runs)}</text>
    <animate attributeName="opacity" calcMode="discrete" dur="${dur}" repeatCount="indefinite" keyTimes="${keyTimes}" values="${values}"/>
  </g>`;
  }).join('\n');
  const label = opts.label ? `<title>${esc(opts.label)}</title>` : '';
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(opts.label || 'status bar')} animated demo">
  ${label}
  <rect x="0.5" y="0.5" width="${W - 1}" height="${H - 1}" rx="8" fill="#0d1117" stroke="#30363d"/>
${layers}
</svg>
`;
}

// Visible column count (ignoring escapes / newlines), for padding frames to an
// equal width when assembling an animation.
function visibleCols(input) {
  return ansiToRuns(input).reduce((n, r) => n + [...r.text].length, 0);
}

if (require.main === module) {
  const inFile = process.argv[2];
  const outFile = process.argv[3];
  const label = process.argv[4];
  const input = (inFile && inFile !== '-') ? fs.readFileSync(inFile, 'utf8') : fs.readFileSync(0, 'utf8');
  const svg = toSvg(input, { label });
  if (outFile) { fs.writeFileSync(outFile, svg); console.log('wrote', outFile); }
  else process.stdout.write(svg);
}

module.exports = { toSvg, toAnimatedSvg, ansiToRuns, visibleCols };
