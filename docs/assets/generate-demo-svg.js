#!/usr/bin/env node
// Encodes captured ANSI frames into the animated demo SVG (hero-demo.svg).
//   node docs/assets/generate-demo-svg.js <frames-dir> [out.svg]
// Usually invoked by generate-demo-svg.sh, which captures the frames first.
//
// Unlike the GIF generator this needs NO npm deps: it is pure node + the local
// ansi-to-svg.js converter. The result is a crisp, true-colour vector that
// flip-books through the same session the GIF shows, and it animates on GitHub
// when referenced via <img> (SMIL, no JavaScript).

const fs = require('fs');
const path = require('path');
const { toAnimatedSvg } = require('./themes/ansi-to-svg.js');

const dir = process.argv[2];
const out = process.argv[3] || path.join(__dirname, 'hero-demo.svg');
if (!dir) { console.error('usage: generate-demo-svg.js <frames-dir> [out.svg]'); process.exit(1); }

const frames = fs.readdirSync(dir)
  .filter(f => f.endsWith('.ansi')).sort()
  .map(f => fs.readFileSync(path.join(dir, f), 'utf8'));

fs.writeFileSync(out, toAnimatedSvg(frames, { label: 'claude-code-status-bar' }));
console.log('wrote', out, frames.length + ' frames');
