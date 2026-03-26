#!/usr/bin/env node
//
// statusline-helper.js — Transcript activity parser for claude-code-status-bar
//
// Reads Claude Code's JSONL transcript file and extracts live activity data
// (tool calls, subagent status, todo progress). Writes a simple cache file
// that the bash statusline script can read.
//
// Usage: node statusline-helper.js <transcript_path> <cache_path>
//
// Cache format (one line): <epoch> <json>
//   json: {"tools":"Read x3 | Edit x2","agents":"research 12s","todos":"3/7","speed":"42 tok/s"}
//
// Security: all output is sanitized — no ANSI escapes, no control characters.

'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// ── CLI args ────────────────────────────────────────────────
const transcriptPath = process.argv[2];
const cachePath = process.argv[3];

if (!transcriptPath || !cachePath) {
  process.exit(1);
}

if (!fs.existsSync(transcriptPath)) {
  process.exit(0);
}

// ── Transcript cache (avoid re-parsing unchanged files) ─────
const PARSED_CACHE_DIR = path.join(path.dirname(cachePath), '.statusline-transcript-cache');

function getCacheKey(filePath) {
  return crypto.createHash('sha256').update(path.resolve(filePath)).digest('hex').slice(0, 16);
}

function readParsedCache(transcriptPath, stat) {
  try {
    const cacheFile = path.join(PARSED_CACHE_DIR, getCacheKey(transcriptPath) + '.json');
    if (!fs.existsSync(cacheFile)) return null;
    const cached = JSON.parse(fs.readFileSync(cacheFile, 'utf8'));
    if (cached.mtimeMs === stat.mtimeMs && cached.size === stat.size) {
      return cached.data;
    }
  } catch { /* cache miss */ }
  return null;
}

function writeParsedCache(transcriptPath, stat, data) {
  try {
    if (!fs.existsSync(PARSED_CACHE_DIR)) {
      fs.mkdirSync(PARSED_CACHE_DIR, { recursive: true, mode: 0o700 });
    }
    const cacheFile = path.join(PARSED_CACHE_DIR, getCacheKey(transcriptPath) + '.json');
    fs.writeFileSync(cacheFile, JSON.stringify({
      mtimeMs: stat.mtimeMs,
      size: stat.size,
      data
    }), { mode: 0o600 });
  } catch { /* non-fatal */ }
}

// ── Sanitize output ─────────────────────────────────────────
function sanitize(str) {
  if (!str) return '';
  return str
    .replace(/\x1b\[[0-9;]*[a-zA-Z]/g, '')     // CSI sequences
    .replace(/\x1b\][^\x07]*\x07/g, '')          // OSC with BEL
    .replace(/\x1b\][^\x1b]*\x1b\\/g, '')        // OSC with ST
    .replace(/[\x00-\x1f\x7f]/g, '')             // control chars
    .replace(/[\u200b-\u200f\u2028-\u202f]/g, '') // Unicode bidi/zero-width
    .slice(0, 200);                                // hard length limit
}

// ── Parse transcript ────────────────────────────────────────
function parseTranscript(filePath) {
  const rawContent = fs.readFileSync(filePath, 'utf8');
  const lines = rawContent.split('\n').filter(l => l.trim());

  // Tool tracking: Map<id, {name, target, status, startTime}>
  const toolMap = new Map();
  // Agent tracking: Map<id, {type, model, description, status, startTime}>
  const agentMap = new Map();
  // Todo tracking
  let todos = [];
  const taskIdToIndex = new Map();
  // Session info
  let sessionStart = null;
  let sessionName = null;

  for (const line of lines) {
    let entry;
    try {
      entry = JSON.parse(line);
    } catch {
      continue;
    }

    // Track session start time (validate to avoid Invalid Date)
    if (!sessionStart && entry.timestamp) {
      const d = new Date(entry.timestamp);
      if (!isNaN(d.getTime())) sessionStart = d;
    }

    // Track session name
    if (entry.type === 'custom-title' && entry.customTitle) {
      sessionName = entry.customTitle;
    } else if (entry.slug && !sessionName) {
      sessionName = entry.slug;
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
          agentMap.set(block.id, {
            type: String(input.subagent_type || input.type || 'general'),
            model: input.model ? String(input.model) : undefined,
            description: input.description ? sanitize(String(input.description)).slice(0, 50) : undefined,
            status: 'running',
            startTime: timestamp
          });
        } else {
          toolMap.set(block.id, {
            name,
            target: target ? sanitize(target).slice(0, 40) : null,
            status: 'running',
            startTime: timestamp
          });
        }
      } else if (block.type === 'tool_result') {
        const id = block.tool_use_id;
        if (toolMap.has(id)) {
          toolMap.get(id).status = block.is_error ? 'error' : 'completed';
          toolMap.get(id).endTime = timestamp;
        }
        if (agentMap.has(id)) {
          agentMap.get(id).status = block.is_error ? 'error' : 'completed';
          agentMap.get(id).endTime = timestamp;
        }
      }

      // Todo tracking
      if (block.type === 'tool_use' && block.name === 'TodoWrite') {
        const input = block.input || {};
        if (Array.isArray(input.todos)) {
          todos = input.todos.map(t => ({
            content: sanitize(String(t.content || '')).slice(0, 50),
            status: normalizeStatus(t.status)
          }));
          taskIdToIndex.clear();
        }
      } else if (block.type === 'tool_use' && block.name === 'TaskCreate') {
        const input = block.input || {};
        const content = sanitize(String(input.subject || input.description || 'Task')).slice(0, 50);
        const status = normalizeStatus(input.status) || 'pending';
        todos.push({ content, status });
        if (block.id) taskIdToIndex.set(block.id, todos.length - 1);
      } else if (block.type === 'tool_use' && block.name === 'TaskUpdate') {
        const input = block.input || {};
        const index = resolveTaskIndex(input.taskId, taskIdToIndex, todos);
        if (index !== null) {
          if (input.status) todos[index].status = normalizeStatus(input.status);
          if (input.content) todos[index].content = sanitize(String(input.content)).slice(0, 50);
        }
      }
    }
  }

  // Build results from last N entries
  const tools = Array.from(toolMap.values()).slice(-30);
  const agents = Array.from(agentMap.values()).slice(-10);

  return { tools, agents, todos, sessionStart, sessionName };
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
function formatActivity(data) {
  const parts = [];
  const now = Date.now();

  // Tool activity: count completed by name, track running + last completed
  const toolCounts = {};
  const runningTools = [];
  let lastCompleted = null;

  for (const t of data.tools) {
    if (t.status === 'running') {
      const label = t.target ? `${t.name} ${t.target}` : t.name;
      runningTools.push(label);
    } else if (t.status === 'completed') {
      toolCounts[t.name] = (toolCounts[t.name] || 0) + 1;
      lastCompleted = t;
    }
  }

  const totalTools = Object.values(toolCounts).reduce((a, b) => a + b, 0);

  // Running tools — show with spinner-style indicator
  if (runningTools.length > 0) {
    const label = runningTools.slice(-2).join(', ');
    parts.push(`\u25B6 ${label}...`);
  }

  // Last completed tool + compact total count
  if (totalTools > 0) {
    // Show what just happened (last tool + target)
    let lastLabel = '';
    if (lastCompleted) {
      lastLabel = lastCompleted.target
        ? `${lastCompleted.name} ${lastCompleted.target}`
        : lastCompleted.name;
    }

    // Compact summary: "last tool | 30 calls (Edit 13, Read 4, ...)"
    const sorted = Object.entries(toolCounts)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 3)
      .map(([name, count]) => `${name} ${count}`)
      .join(' \u00B7 ');

    if (runningTools.length === 0 && lastLabel) {
      // Nothing running — lead with the last action
      parts.push(`\u2192 ${lastLabel}  [${sorted}]`);
    } else {
      // Something running — just show the summary
      parts.push(`[${sorted}]`);
    }
  }

  // Agent activity
  const runningAgents = data.agents.filter(a => a.status === 'running');
  const completedAgents = data.agents.filter(a => a.status === 'completed');
  if (runningAgents.length > 0) {
    for (const a of runningAgents.slice(-2)) {
      const elapsed = a.startTime ? Math.round((now - new Date(a.startTime).getTime()) / 1000) : 0;
      const time = elapsed > 0 ? ` ${formatDuration(elapsed)}` : '';
      const desc = a.description || a.type;
      parts.push(`\u2692 ${desc}${time}`);
    }
  } else if (completedAgents.length > 0) {
    const count = completedAgents.length;
    const last = completedAgents[completedAgents.length - 1];
    const desc = last.description || last.type;
    parts.push(`\u2692 ${desc} \u2713${count > 1 ? ` (${count})` : ''}`);
  }

  // Todo progress
  if (data.todos.length > 0) {
    const done = data.todos.filter(t => t.status === 'completed').length;
    const total = data.todos.length;
    const inProgress = data.todos.find(t => t.status === 'in_progress');
    // Mini progress bar: ██░░ 2/5
    const barW = Math.min(total, 8);
    const filled = Math.round((done / total) * barW);
    const bar = '\u2588'.repeat(filled) + '\u2591'.repeat(barW - filled);
    let todoText = `${bar} ${done}/${total}`;
    if (inProgress) {
      todoText += ` ${inProgress.content}`;
    }
    parts.push(todoText);
  }

  return parts.join('  \u2502  ');
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

// ── Main ────────────────────────────────────────────────────
function main() {
  try {
    const stat = fs.statSync(transcriptPath);

    // Check parsed cache first
    let data = readParsedCache(transcriptPath, stat);
    if (!data) {
      data = parseTranscript(transcriptPath);
      writeParsedCache(transcriptPath, stat, data);
    }

    const activity = sanitize(formatActivity(data));

    // Write cache: "epoch json"
    const epoch = Math.floor(Date.now() / 1000);
    const json = JSON.stringify({ activity });
    fs.writeFileSync(cachePath, `${epoch} ${json}\n`, { mode: 0o600 });
  } catch {
    // Non-fatal — status bar works without activity line
    process.exit(0);
  }
}

main();
