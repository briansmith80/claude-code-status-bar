#!/usr/bin/env node
//
// statusline-helper.js — Transcript activity parser for claude-code-status-bar
//
// Reads Claude Code's JSONL transcript file and extracts live activity data
// (tool calls, subagent status, todo progress). Writes a simple cache file
// that the bash statusline script can read.
//
// Usage: node statusline-helper.js <transcript_path> <cache_path> [--colour]
//
// Cache format (one line): <epoch> <json>
//   json: {"activity":"→ Edit main.ts  [Edit 5 · Read 4]  │  ⚒ research 12s"}
//
// With --colour the activity string carries zero-width tokens ({w},{o},{e},
// {i},{d},{O},{h1}-{h3},{r0}-{r3},{s}) that the bash script maps to theme
// colours after sanitization. Tokens are plain text, so they survive both
// sanitize layers; without the flag the output is byte-identical to before.
//
// Parsing is incremental: a per-transcript cache stores the parse state plus
// a byte offset, so each run only parses lines appended since the last one.
//
// Security: all output is sanitized — no ANSI escapes, no control characters.

'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// Completed/failed items older than this stop being displayed (counts remain)
const RECENT_MS = 5 * 60 * 1000;
// Running tools show elapsed time once they run at least this long
const TOOL_ELAPSED_MIN_S = 5;
// Completion flash: a just-finished tool stays highlighted this long
const FLASH_MS = 5 * 1000;
// Elapsed-time heat tiers (seconds): below first = ok, below second = warn
const HEAT_WARN_S = 30;
const HEAT_HIGH_S = 120;

// ── CLI args ────────────────────────────────────────────────
const transcriptPath = process.argv[2];
const cachePath = process.argv[3];
const colourMode = process.argv.includes('--colour');

if (!transcriptPath || !cachePath) {
  process.exit(1);
}

if (!fs.existsSync(transcriptPath)) {
  process.exit(0);
}

// ── Transcript cache (parse state + byte offset per transcript) ─
const PARSED_CACHE_DIR = path.join(path.dirname(cachePath), '.statusline-transcript-cache');

function getCacheKey(filePath) {
  return crypto.createHash('sha256').update(path.resolve(filePath)).digest('hex').slice(0, 16);
}

function readParsedCache(transcriptPath) {
  try {
    const cacheFile = path.join(PARSED_CACHE_DIR, getCacheKey(transcriptPath) + '.json');
    if (!fs.existsSync(cacheFile)) return null;
    return JSON.parse(fs.readFileSync(cacheFile, 'utf8'));
  } catch { /* cache miss */ }
  return null;
}

function writeParsedCache(transcriptPath, stat, offset, state) {
  try {
    if (!fs.existsSync(PARSED_CACHE_DIR)) {
      fs.mkdirSync(PARSED_CACHE_DIR, { recursive: true, mode: 0o700 });
    }
    const cacheFile = path.join(PARSED_CACHE_DIR, getCacheKey(transcriptPath) + '.json');
    fs.writeFileSync(cacheFile, JSON.stringify({
      mtimeMs: stat.mtimeMs,
      size: stat.size,
      offset,
      state: serializeState(state)
    }), { mode: 0o600 });
  } catch { /* non-fatal */ }
}

// ── Sanitize output ─────────────────────────────────────────
function sanitize(str, max) {
  if (!str) return '';
  return str
    .replace(/\x1b\[[0-9;]*[a-zA-Z]/g, '')     // CSI sequences
    .replace(/\x1b\][^\x07]*\x07/g, '')          // OSC with BEL
    .replace(/\x1b\][^\x1b]*\x1b\\/g, '')        // OSC with ST
    .replace(/[\x00-\x1f\x7f]/g, '')             // control chars
    .replace(/[\u200b-\u200f\u2028-\u202f]/g, '') // Unicode bidi/zero-width
    .slice(0, max || 200);                         // hard length limit
}

// ── Parse state ─────────────────────────────────────────────
// Tool entries:  Map<id, {name, target, status, startTime, endTime}>
// Agent entries: Map<id, {type, model, description, status, startTime, endTime}>
function newState() {
  return {
    toolMap: new Map(),
    agentMap: new Map(),
    todos: [],
    taskIdToIndex: new Map(),
    sessionStart: null,
    sessionName: null
  };
}

function serializeState(state) {
  pruneMap(state.toolMap, 60);
  pruneMap(state.agentMap, 20);
  return {
    tools: Array.from(state.toolMap.entries()),
    agents: Array.from(state.agentMap.entries()),
    todos: state.todos,
    taskIdToIndex: Array.from(state.taskIdToIndex.entries()),
    sessionStart: state.sessionStart,
    sessionName: state.sessionName
  };
}

function reviveState(s) {
  const state = newState();
  try {
    state.toolMap = new Map(s.tools || []);
    state.agentMap = new Map(s.agents || []);
    state.todos = Array.isArray(s.todos) ? s.todos : [];
    state.taskIdToIndex = new Map(s.taskIdToIndex || []);
    state.sessionStart = s.sessionStart || null;
    state.sessionName = s.sessionName || null;
  } catch {
    return newState();
  }
  return state;
}

// Drop oldest non-running entries once a map outgrows `keep`. Running entries
// survive so a tool_result arriving in a later chunk can still be correlated.
function pruneMap(map, keep) {
  if (map.size <= keep) return;
  for (const [id, v] of map) {
    if (map.size <= keep) break;
    if (v.status !== 'running') map.delete(id);
  }
}

// ── Incremental reading ─────────────────────────────────────
// Read bytes [start, end) and return {text, consumed} covering whole lines
// (through the last newline). A trailing line with no newline is included
// only when it parses as standalone JSON (a complete entry that just lacks
// its terminator); a genuinely partial write is left for the next run.
function readChunk(filePath, start, end) {
  const len = end - start;
  if (len <= 0) return { text: '', consumed: 0 };
  const fd = fs.openSync(filePath, 'r');
  let buf;
  try {
    buf = Buffer.alloc(len);
    fs.readSync(fd, buf, 0, len, start);
  } finally {
    fs.closeSync(fd);
  }
  let cut = buf.lastIndexOf(0x0a) + 1;
  if (cut < len) {
    const tail = buf.slice(cut).toString('utf8').trim();
    if (!tail) {
      cut = len;
    } else {
      try { JSON.parse(tail); cut = len; } catch { /* partial write — wait */ }
    }
  }
  return { text: buf.slice(0, cut).toString('utf8'), consumed: cut };
}

// ── Parse transcript lines into the state ───────────────────
function parseChunk(state, rawText) {
  const lines = rawText.split('\n').filter(l => l.trim());

  for (const line of lines) {
    let entry;
    try {
      entry = JSON.parse(line);
    } catch {
      continue;
    }

    // Track session start time (validate to avoid Invalid Date)
    if (!state.sessionStart && entry.timestamp) {
      const d = new Date(entry.timestamp);
      if (!isNaN(d.getTime())) state.sessionStart = d;
    }

    // Track session name
    if (entry.type === 'custom-title' && entry.customTitle) {
      state.sessionName = entry.customTitle;
    } else if (entry.slug && !state.sessionName) {
      state.sessionName = entry.slug;
    }

    // Process message content blocks
    const blocks = entry.message?.content;
    if (!Array.isArray(blocks)) continue;

    const ts = entry.timestamp ? new Date(entry.timestamp) : null;
    const timestamp = (ts && !isNaN(ts.getTime())) ? ts : new Date();

    for (const block of blocks) {
      if (block.type === 'tool_use') {
        const name = block.name || 'unknown';
        const target = extractTarget(name, block.input);

        // Special handling for Agent/Task tools
        if (name === 'Agent' || name === 'Task') {
          const input = block.input || {};
          state.agentMap.set(block.id, {
            type: String(input.subagent_type || input.type || 'general'),
            model: input.model ? String(input.model) : undefined,
            description: input.description ? sanitize(String(input.description)).slice(0, 50) : undefined,
            status: 'running',
            startTime: timestamp
          });
        } else {
          state.toolMap.set(block.id, {
            name,
            target: target ? sanitize(target).slice(0, 40) : null,
            status: 'running',
            startTime: timestamp
          });
        }
      } else if (block.type === 'tool_result') {
        const id = block.tool_use_id;
        if (state.toolMap.has(id)) {
          state.toolMap.get(id).status = block.is_error ? 'error' : 'completed';
          state.toolMap.get(id).endTime = timestamp;
        }
        if (state.agentMap.has(id)) {
          state.agentMap.get(id).status = block.is_error ? 'error' : 'completed';
          state.agentMap.get(id).endTime = timestamp;
        }
      }

      // Todo tracking
      if (block.type === 'tool_use' && block.name === 'TodoWrite') {
        const input = block.input || {};
        if (Array.isArray(input.todos)) {
          state.todos = input.todos.map(t => ({
            content: sanitize(String(t.content || '')).slice(0, 50),
            status: normalizeStatus(t.status)
          }));
          state.taskIdToIndex.clear();
        }
      } else if (block.type === 'tool_use' && block.name === 'TaskCreate') {
        const input = block.input || {};
        const content = sanitize(String(input.subject || input.description || 'Task')).slice(0, 50);
        const status = normalizeStatus(input.status) || 'pending';
        state.todos.push({ content, status });
        if (block.id) state.taskIdToIndex.set(block.id, state.todos.length - 1);
      } else if (block.type === 'tool_use' && block.name === 'TaskUpdate') {
        const input = block.input || {};
        const index = resolveTaskIndex(input.taskId, state.taskIdToIndex, state.todos);
        if (index !== null) {
          if (input.status) state.todos[index].status = normalizeStatus(input.status);
          if (input.content) state.todos[index].content = sanitize(String(input.content)).slice(0, 50);
        }
      }
    }
  }
}

function extractTarget(name, input) {
  if (!input) return null;
  switch (name) {
    case 'Read':
    case 'Write':
    case 'Edit':
      return basename(input.file_path || input.path || '');
    case 'Glob':
    case 'Grep':
      return String(input.pattern || '').slice(0, 30);
    case 'Bash':
      return String(input.command || '').slice(0, 30);
    default:
      return null;
  }
}

function basename(p) {
  if (!p) return '';
  return path.basename(String(p));
}

function normalizeStatus(s) {
  if (!s) return 'pending';
  s = String(s).toLowerCase();
  if (s === 'completed' || s === 'complete' || s === 'done') return 'completed';
  if (s === 'in_progress' || s === 'running') return 'in_progress';
  return 'pending';
}

function resolveTaskIndex(taskId, idMap, todos) {
  if (!taskId) return null;
  const id = String(taskId);
  if (idMap.has(id)) return idMap.get(id);
  // Try as 1-based numeric index
  const n = parseInt(id, 10);
  if (!isNaN(n) && n >= 1 && n <= todos.length) return n - 1;
  return null;
}

// ── Format output ───────────────────────────────────────────
function isRecent(t, now) {
  if (!t) return false;
  const ms = new Date(t).getTime();
  return !isNaN(ms) && (now - ms) <= RECENT_MS;
}

// Colour-token helpers. In plain mode every token collapses to '', keeping
// the output byte-identical to pre-colour releases.
function tk(token) {
  return colourMode ? token : '';
}

// Heat tier for an elapsed duration: {h1} fine, {h2} taking a while, {h3} stuck
function heatTk(elapsedS) {
  if (!colourMode) return '';
  if (elapsedS < HEAT_WARN_S) return '{h1}';
  if (elapsedS < HEAT_HIGH_S) return '{h2}';
  return '{h3}';
}

// Untrusted text could coincidentally contain colour tokens ({w}, {h1}, ...),
// which would recolour the line (cosmetic only — substitution injects fixed
// theme constants, never input). Defuse token lookalikes by swapping their
// opening brace for a fullwidth one (text stays readable, e.g. shell ${a}
// becomes $｛a}), looping to a fixed point so nested lookalikes like {h{x}1}
// cannot reassemble into a live token.
function defuse(str) {
  if (!colourMode || !str) return str;
  let s = String(str);
  let prev;
  do {
    prev = s;
    s = s.replace(/\{(?=[A-Za-z][0-9]?\})/g, '｛');
  } while (s !== prev);
  return s;
}

function formatActivity(data) {
  const parts = [];
  const now = Date.now();

  // Tool activity: count completed by name, track running + last completed/failed
  const toolCounts = {};
  const runningTools = [];
  let lastCompleted = null;
  let lastError = null;

  for (const t of data.tools) {
    if (t.status === 'running') {
      runningTools.push(t);
    } else if (t.status === 'completed') {
      toolCounts[t.name] = (toolCounts[t.name] || 0) + 1;
      lastCompleted = t;
    } else if (t.status === 'error') {
      lastError = t;
    }
  }

  // Running tools — elapsed time appears once a tool runs a few seconds.
  // Colour mode: tool name in warn yellow, target dim, elapsed heat-coloured,
  // and the ▶ bullet becomes a {s} spinner slot the bash side animates.
  if (runningTools.length > 0) {
    let anyElapsed = false;
    const labels = runningTools.slice(-2).map(t => {
      let label = `${tk('{w}')}${defuse(t.name)}${tk('{d}')}`;
      if (t.target) label += ` ${defuse(t.target)}`;
      const started = t.startTime ? new Date(t.startTime).getTime() : NaN;
      const elapsed = isNaN(started) ? 0 : Math.round((now - started) / 1000);
      if (elapsed >= TOOL_ELAPSED_MIN_S) {
        label += ` ${heatTk(elapsed)}${formatDuration(elapsed)}${tk('{d}')}`;
        anyElapsed = true;
      }
      return label;
    });
    parts.push(`${colourMode ? '{s}' : '▶'} ${labels.join(', ')}${anyElapsed ? '' : '...'}`);
  }

  const totalTools = Object.values(toolCounts).reduce((a, b) => a + b, 0);

  // Last completed tool (only while recent) + compact total count.
  // Colour mode: a tool that finished within the last few seconds gets a
  // bright green ✓ flash ({O}), then settles into the dim line.
  if (totalTools > 0) {
    let lastLabel = '';
    if (lastCompleted && isRecent(lastCompleted.endTime, now)) {
      lastLabel = lastCompleted.target
        ? `${defuse(lastCompleted.name)} ${defuse(lastCompleted.target)}`
        : defuse(lastCompleted.name);
    }

    const sorted = Object.entries(toolCounts)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 3)
      .map(([name, count]) => `${defuse(name)} ${count}`)
      .join(' · ');

    if (runningTools.length === 0 && lastLabel) {
      // Nothing running — lead with the last action
      const endMs = new Date(lastCompleted.endTime).getTime();
      const flashing = colourMode && !isNaN(endMs) && (now - endMs) <= FLASH_MS;
      if (flashing) {
        parts.push(`${tk('{i}')}→${tk('{d}')} {O}✓ ${lastLabel}{d}  [${sorted}]`);
      } else {
        parts.push(`${tk('{i}')}→${tk('{d}')} ${lastLabel}  [${sorted}]`);
      }
    } else {
      // Something running — just show the summary
      parts.push(`[${sorted}]`);
    }
  }

  // Most recent tool failure, shown briefly so errors don't pass unnoticed
  if (lastError && isRecent(lastError.endTime, now)) {
    const label = lastError.target
      ? `${defuse(lastError.name)} ${defuse(lastError.target)}`
      : defuse(lastError.name);
    parts.push(`${tk('{e}')}✗ ${label}${tk('{d}')}`);
  }

  // Agent activity: running agents, else recently completed ones
  const runningAgents = data.agents.filter(a => a.status === 'running');
  const recentDoneAgents = data.agents.filter(a => a.status === 'completed' && isRecent(a.endTime, now));
  if (runningAgents.length > 0) {
    for (const a of runningAgents.slice(-2)) {
      const started = a.startTime ? new Date(a.startTime).getTime() : NaN;
      const elapsed = isNaN(started) ? 0 : Math.round((now - started) / 1000);
      const time = elapsed > 0 ? ` ${heatTk(elapsed)}${formatDuration(elapsed)}${tk('{d}')}` : '';
      const desc = defuse(a.description) || defuse(a.type);
      parts.push(`${tk('{w}')}⚒ ${desc}${tk('{d}')}${time}`);
    }
  } else if (recentDoneAgents.length > 0) {
    const count = recentDoneAgents.length;
    const last = recentDoneAgents[recentDoneAgents.length - 1];
    const desc = defuse(last.description) || defuse(last.type);
    parts.push(`⚒ ${desc} ${tk('{o}')}✓${tk('{d}')}${count > 1 ? ` (${count})` : ''}`);
  }

  // Todo progress
  if (data.todos.length > 0) {
    const done = data.todos.filter(t => t.status === 'completed').length;
    const total = data.todos.length;
    const inProgress = data.todos.find(t => t.status === 'in_progress');
    // Mini progress bar: ██░░ 2/5. Colour mode shades the filled cells with
    // a 4-step theme ramp ({r0}-{r3}) stretched across the filled portion.
    const barW = Math.min(total, 8);
    const filled = Math.round((done / total) * barW);
    let bar;
    if (colourMode && filled > 0) {
      bar = '';
      let lastRamp = -1;
      for (let i = 0; i < filled; i++) {
        // Inclusive 0..3 mapping so the last filled cell reaches {r3}
        const ramp = filled > 1 ? Math.round((i * 3) / (filled - 1)) : 0;
        if (ramp !== lastRamp) { bar += `{r${ramp}}`; lastRamp = ramp; }
        bar += '█';
      }
      bar += `{d}${'░'.repeat(barW - filled)}`;
    } else {
      bar = '█'.repeat(filled) + '░'.repeat(barW - filled);
    }
    let todoText = `${bar} ${done}/${total}`;
    if (inProgress) {
      todoText += ` ${defuse(inProgress.content)}`;
    }
    parts.push(todoText);
  }

  return parts.join('  │  ');
}

function formatDuration(secs) {
  if (secs >= 3600) {
    const h = Math.floor(secs / 3600);
    const m = Math.floor((secs % 3600) / 60);
    return `${h}h${m}m`;
  }
  if (secs >= 60) {
    const m = Math.floor(secs / 60);
    const s = secs % 60;
    return `${m}m${s}s`;
  }
  return `${secs}s`;
}

// Earliest future epoch (seconds) at which the rendered line could change with
// NO further transcript activity: a running tool's per-second elapsed tick, a
// running tool about to cross TOOL_ELAPSED_MIN_S (when "..." becomes elapsed), a
// completion flash expiring, or a completed/error item ageing out of the recent
// window. 0 means nothing is time-sensitive (the line is static until the
// transcript changes). The bash side re-runs this helper only at that moment, so
// an idle line costs zero Node spawns. Bias EARLIER when unsure: an early re-run
// just reproduces the same line (cheap, harmless); a late one would show stale
// text. Uses the same sliced `data` the formatter renders, so it never points at
// something off-screen.
function computeNext(data, nowMs) {
  let next = Infinity;
  const consider = (ms) => { if (ms > nowMs && ms < next) next = ms; };
  let anyRunning = false;
  for (const t of data.tools) {
    if (t.status === 'running') {
      anyRunning = true;
      const s = t.startTime ? new Date(t.startTime).getTime() : NaN;
      if (!isNaN(s)) consider(s + TOOL_ELAPSED_MIN_S * 1000); // "..." -> elapsed
    } else if (t.endTime) {
      const e = new Date(t.endTime).getTime();
      if (!isNaN(e)) {
        if (t.status === 'completed') consider(e + FLASH_MS); // flash expiry
        consider(e + RECENT_MS);                              // recent age-out
      }
    }
  }
  for (const a of data.agents) {
    if (a.status === 'running') {
      anyRunning = true;
    } else if (a.status === 'completed' && a.endTime) {
      const e = new Date(a.endTime).getTime();
      if (!isNaN(e)) consider(e + RECENT_MS);
    }
  }
  if (anyRunning) consider(nowMs + 1000); // elapsed ticks every whole second
  return next === Infinity ? 0 : Math.ceil(next / 1000);
}

// ── Main ────────────────────────────────────────────────────
function main() {
  try {
    const stat = fs.statSync(transcriptPath);
    const cached = readParsedCache(transcriptPath);

    let state;
    if (cached && cached.state && cached.mtimeMs === stat.mtimeMs && cached.size === stat.size) {
      // Unchanged file — reuse the parsed state as-is
      state = reviveState(cached.state);
    } else if (cached && cached.state && typeof cached.offset === 'number' &&
               cached.offset > 0 && cached.offset <= stat.size && stat.size > cached.size) {
      // File grew — parse only the appended bytes
      state = reviveState(cached.state);
      const { text, consumed } = readChunk(transcriptPath, cached.offset, stat.size);
      parseChunk(state, text);
      writeParsedCache(transcriptPath, stat, cached.offset + consumed, state);
    } else {
      // New, truncated, or rewritten file — full parse
      state = newState();
      const { text, consumed } = readChunk(transcriptPath, 0, stat.size);
      parseChunk(state, text);
      writeParsedCache(transcriptPath, stat, consumed, state);
    }

    const data = {
      tools: Array.from(state.toolMap.values()).slice(-30),
      agents: Array.from(state.agentMap.values()).slice(-10),
      todos: state.todos
    };

    // Zero-width colour tokens eat into the cap, so allow extra headroom in
    // colour mode; the bash side trims to the terminal width regardless.
    const nowMs = Date.now();
    let activity = sanitize(formatActivity(data), colourMode ? 320 : 200);
    // The hard cap can land inside a colour token; drop a dangling fragment
    // like '{', '{w' or '{r2' so it never renders as literal text
    if (colourMode) activity = activity.replace(/\{[A-Za-z]?[0-9]?$/, '');

    // Write cache: "epoch json". `next` is the earliest epoch (seconds) the line
    // could change with no further transcript activity; the bash side reads it to
    // skip re-running this helper while nothing is changing (0 = nothing pending).
    const epoch = Math.floor(nowMs / 1000);
    const next = computeNext(data, nowMs);
    const json = JSON.stringify({ activity, next });
    fs.writeFileSync(cachePath, `${epoch} ${json}\n`, { mode: 0o600 });
  } catch {
    // Non-fatal — status bar works without activity line
    process.exit(0);
  }
}

main();
