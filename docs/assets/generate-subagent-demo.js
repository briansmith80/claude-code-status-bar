#!/usr/bin/env node
// Generates docs/assets/subagent-panel-demo.svg: a REAL render of the subagent
// panel rows produced by statusline-subagent.js, fed a canned set of running /
// completed / failed / queued Task subagents (the running one carries
// tokenSamples so the tok/s rate and sparkline appear), then converted to SVG
// by themes/ansi-to-svg.js. No drift: the rows are the renderer's own output.
//   node docs/assets/generate-subagent-demo.js
//
// Pure node; no npm deps. Timestamps are relative to now so the elapsed times
// render correctly.

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { toSvg } = require('./themes/ansi-to-svg.js');

const now = Date.now();
const input = {
  columns: 96,
  tasks: [
    { id: 't1', status: 'running',   description: 'research auth patterns', startTime: now - 52000, tokenCount: 13500, tokenSamples: [8000, 9200, 10800, 12000, 13500] },
    { id: 't2', status: 'completed', description: 'audit error handling',   startTime: now - 95000, tokenCount: 42000 },
    { id: 't3', status: 'failed',    description: 'migrate config loader',  startTime: now - 30000, tokenCount: 8200 },
    { id: 't4', status: 'queued',    description: 'write integration tests' },
  ],
};

const subagent = path.join(__dirname, '..', '..', 'statusline-subagent.js');
const stdout = execFileSync('node', [subagent], {
  input: JSON.stringify(input),
  encoding: 'utf8',
  env: { ...process.env, NO_COLOR: '' },
});
const rows = stdout.trim().split('\n').filter(Boolean).map(l => JSON.parse(l).content);

const outFile = path.join(__dirname, 'subagent-panel-demo.svg');
fs.writeFileSync(outFile, toSvg(rows.join('\n'), { label: 'subagent panel' }));
console.log('wrote', outFile, rows.length + ' rows');
