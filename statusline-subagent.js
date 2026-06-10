#!/usr/bin/env node
//
// statusline-subagent.js - Subagent panel row renderer for claude-code-status-bar
//
// Claude Code's agent panel (the rows below the prompt while agents run)
// can delegate row rendering to a command via the "subagentStatusLine"
// setting. As of Claude Code 2.1.170 only Task-tool subagent rows (task
// type "local_agent") are delegated; workflow and background-task rows are
// drawn by a separate panel path and never reach this script. Claude Code
// pipes one JSON object per refresh tick (every ~5s):
//
//   { ..., "columns": <usable row width>, "tasks": [
//       { "id", "name", "type", "status", "description", "label",
//         "startTime" (epoch ms), "tokenCount",
//         "tokenSamples" (cumulative token counts, one per tick, max 16),
//         "cwd" } ] }
//
// This script prints one JSON line per row: {"id": "...", "content": "..."}.
// Content renders as-is, ANSI colours included. Any error exits silently,
// which makes Claude Code fall back to its default row rendering.
//
// Reads colour_theme (and subagent_rows=false to disable) from the
// statusline.conf next to this script. Honours NO_COLOR.

'use strict';

const fs = require('fs');
const path = require('path');

// Claude Code samples tokenCount once per panel refresh tick (~5 seconds,
// constant jT4 in CC 2.1.170). Used to turn samples into a tok/s rate.
const TICK_SECONDS = 5;
const SPARK_CHARS = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];

// ── Config (shared with the bash status bar) ────────────────
function readConf() {
  const conf = {};
  try {
    const text = fs.readFileSync(path.join(__dirname, 'statusline.conf'), 'utf8');
    for (const line of text.split('\n')) {
      const m = line.match(/^\s*([a-z_]+)\s*=\s*("?)([^"#]*)\2\s*(#.*)?$/);
      if (m) conf[m[1]] = m[3].trim();
    }
  } catch { /* defaults */ }
  return conf;
}

const THEMES = {
  'default':     { ok: '\x1b[0;32m',      warn: '\x1b[0;33m',      err: '\x1b[0;31m',      dim: '\x1b[0;90m' },
  'nord':        { ok: '\x1b[38;5;108m',  warn: '\x1b[38;5;179m',  err: '\x1b[38;5;174m',  dim: '\x1b[38;5;60m' },
  'dracula':     { ok: '\x1b[38;5;84m',   warn: '\x1b[38;5;228m',  err: '\x1b[38;5;210m',  dim: '\x1b[38;5;61m' },
  'solarized':   { ok: '\x1b[38;5;64m',   warn: '\x1b[38;5;136m',  err: '\x1b[38;5;160m',  dim: '\x1b[38;5;240m' },
  'tokyo-night': { ok: '\x1b[38;5;149m',  warn: '\x1b[38;5;179m',  err: '\x1b[38;5;204m',  dim: '\x1b[38;5;59m' },
  'catppuccin':  { ok: '\x1b[38;5;150m',  warn: '\x1b[38;5;223m',  err: '\x1b[38;5;211m',  dim: '\x1b[38;5;243m' },
  'mono':        { ok: '', warn: '', err: '', dim: '' }
};

function palette(conf) {
  if (process.env.NO_COLOR) return { ...THEMES.mono, reset: '' };
  const theme = THEMES[conf.colour_theme] || THEMES['default'];
  const mono = theme === THEMES.mono;
  return { ...theme, reset: mono ? '' : '\x1b[0m' };
}

// ── Sanitize (same rules as statusline-helper.js) ───────────
function sanitize(str) {
  if (!str) return '';
  return String(str)
    .replace(/\x1b\[[0-9;]*[a-zA-Z]/g, '')
    .replace(/\x1b\][^\x07]*\x07/g, '')
    .replace(/\x1b\][^\x1b]*\x1b\\/g, '')
    .replace(/[\x00-\x1f\x7f]/g, '')
    .slice(0, 60);
}

function visibleLength(s) {
  return s.replace(/\x1b\[[0-9;]*m/g, '').length;
}

// ── Formatting helpers ──────────────────────────────────────
function formatDuration(secs) {
  if (secs >= 3600) return `${Math.floor(secs / 3600)}h${Math.floor((secs % 3600) / 60)}m`;
  if (secs >= 60) return `${Math.floor(secs / 60)}m${secs % 60}s`;
  return `${secs}s`;
}

function formatTokens(n) {
  if (!Number.isFinite(n) || n <= 0) return '';
  if (n < 1000) return `${n} tok`;
  const k = n / 1000;
  return `${k >= 100 ? Math.round(k) : k.toFixed(1).replace(/\.0$/, '')}k tok`;
}

// Rate over the sample window. Samples are cumulative counts, one per tick.
function tokenRate(samples) {
  if (!Array.isArray(samples)) return 0;
  const nums = samples.filter(v => Number.isFinite(v));
  if (nums.length < 2) return 0;
  const span = nums[nums.length - 1] - nums[0];
  if (span <= 0) return 0;
  return span / ((nums.length - 1) * TICK_SECONDS);
}

// Mini sparkline from the last few per-tick deltas
function sparkline(samples) {
  if (!Array.isArray(samples)) return '';
  const nums = samples.filter(v => Number.isFinite(v));
  if (nums.length < 3) return '';
  const deltas = [];
  for (let i = 1; i < nums.length; i++) deltas.push(Math.max(0, nums[i] - nums[i - 1]));
  const recent = deltas.slice(-8);
  const max = Math.max(...recent);
  if (max <= 0) return '';
  return recent.map(d => SPARK_CHARS[Math.min(7, Math.floor((d / max) * 7.999))]).join('');
}

function statusIcon(status, clr) {
  const s = String(status || '').toLowerCase();
  if (s === 'running' || s === 'in_progress' || s === 'started' || s === 'working') {
    return { icon: '⚒', colour: clr.warn };
  }
  if (s === 'completed' || s === 'success' || s === 'done') {
    return { icon: '✓', colour: clr.ok };
  }
  if (s === 'failed' || s === 'error' || s === 'cancelled' || s === 'killed') {
    return { icon: '✗', colour: clr.err };
  }
  if (s === 'pending' || s === 'queued') {
    return { icon: '◌', colour: clr.dim };
  }
  return { icon: '⚒', colour: clr.dim };
}

// ── Row rendering ───────────────────────────────────────────
function renderRow(task, descWidth, columns, clr, now) {
  const { icon, colour } = statusIcon(task.status, clr);
  let desc = sanitize(task.label || task.description || task.name || task.type || 'task');
  if (desc.length > descWidth) desc = desc.slice(0, descWidth - 1) + '…';

  const meta = [];
  const started = Number(task.startTime);
  if (Number.isFinite(started) && started > 0 && now > started) {
    meta.push(formatDuration(Math.round((now - started) / 1000)));
  }
  const tok = formatTokens(Number(task.tokenCount));
  if (tok) meta.push(tok);

  const rate = tokenRate(task.tokenSamples);
  const rateText = rate >= 1 ? `${Math.round(rate)} tok/s` : '';
  const spark = sparkline(task.tokenSamples);

  const build = (withRate, withSpark) => {
    const parts = meta.slice();
    if (withRate && rateText) parts.push(withSpark && spark ? `${rateText} ${spark}` : rateText);
    const metaText = parts.length ? `  ${clr.dim}${parts.join(' · ')}${clr.reset}` : '';
    return `${colour}${icon}${clr.reset} ${desc.padEnd(descWidth)}${metaText}`;
  };

  // Fit to the provided row width: drop the sparkline first, then the rate
  let content = build(true, true);
  if (visibleLength(content) > columns) content = build(true, false);
  if (visibleLength(content) > columns) content = build(false, false);
  if (visibleLength(content) > columns) {
    const over = visibleLength(content) - columns;
    const shrunk = Math.max(8, descWidth - over);
    desc = desc.slice(0, shrunk - 1) + '…';
    content = `${colour}${icon}${clr.reset} ${desc}`;
  }
  return content.replace(/\s+$/, '');
}

// ── Main ────────────────────────────────────────────────────
function main(inputText) {
  let input;
  try {
    input = JSON.parse(inputText);
  } catch {
    return;
  }
  const tasks = Array.isArray(input.tasks) ? input.tasks : [];
  if (tasks.length === 0) return;

  const conf = readConf();
  if (conf.subagent_rows === 'false') return; // keep Claude Code's default rows

  const clr = palette(conf);
  const columns = Number.isFinite(Number(input.columns)) && Number(input.columns) > 10
    ? Number(input.columns) : 80;
  const now = Date.now();

  // Common description width so the metadata columns line up across rows
  const descWidth = Math.min(
    44,
    Math.max(...tasks.map(t => sanitize(t.label || t.description || t.name || t.type || 'task').length), 8)
  );

  const out = [];
  for (const task of tasks) {
    if (task.id === undefined || task.id === null) continue; // default rendering
    const content = renderRow(task, descWidth, columns, clr, now);
    out.push(JSON.stringify({ id: String(task.id), content }));
  }
  if (out.length) process.stdout.write(out.join('\n') + '\n');
}

try {
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', d => { raw += d; });
  process.stdin.on('end', () => {
    try { main(raw); } catch { /* silent: defaults */ }
  });
} catch {
  process.exit(0);
}
