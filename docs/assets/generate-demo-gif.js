#!/usr/bin/env node
// Encodes captured ANSI frames into the animated demo GIF.
//   node docs/assets/generate-demo-gif.js <frames-dir> [out.gif]
// Usually invoked by generate-demo-gif.sh, which captures the frames first.
//
// Requires a one-time install of the rasteriser + GIF encoder (not committed):
//   npm i @resvg/resvg-js gifenc
//
// Each frame is the REAL bar output (no screen recording): the captured ANSI is
// converted to SVG by themes/ansi-to-svg.js, rasterised with resvg, and encoded
// with gifenc. Frames are padded to an equal width so the animation is stable.

const fs = require('fs');
const path = require('path');
const { Resvg } = require('@resvg/resvg-js');
const { GIFEncoder, quantize, applyPalette } = require('gifenc');
const { toSvg, visibleCols } = require('./themes/ansi-to-svg.js');

const dir = process.argv[2];
const out = process.argv[3] || path.join(__dirname, 'hero-demo.gif');
if (!dir) { console.error('usage: generate-demo-gif.js <frames-dir> [out.gif]'); process.exit(1); }

const raw = fs.readdirSync(dir)
  .filter(f => f.endsWith('.ansi')).sort()
  .map(f => fs.readFileSync(path.join(dir, f), 'utf8').split('\n')[0]);
const maxCols = Math.max(...raw.map(visibleCols));

const gif = GIFEncoder();
let W, H;
raw.forEach((line, i) => {
  const padded = line + ' '.repeat(Math.max(0, maxCols - visibleCols(line)));
  const r = new Resvg(toSvg(padded, {}), { background: '#0d1117', font: { loadSystemFonts: true } }).render();
  W = r.width; H = r.height;
  const palette = quantize(r.pixels, 256);
  // Hold the first and last (warning) frames a little longer.
  const delay = i === raw.length - 1 ? 1700 : (i === 0 ? 900 : 680);
  gif.writeFrame(applyPalette(r.pixels, palette), W, H, { palette, delay });
});
gif.finish();
fs.writeFileSync(out, Buffer.from(gif.bytes()));
console.log('wrote', out, `${W}x${H}`, raw.length + ' frames');
