#!/usr/bin/env node
// Emits a Claude Code JSONL transcript for one demo frame (argv[2] = 0..5) to
// stdout. capture-demo-frames.sh feeds each through statusline-helper.js so the
// demo's line 2 (live activity) is REAL helper output, not hand-faked text.
//
// The six frames tell one coherent session: tool counts climb, a subagent runs
// then finishes, and the todo bar fills 0/5 -> 5/5 alongside line 1's context
// bar. Timestamps are relative to now so the helper's elapsed times ("8s") and
// the just-finished "flash" land correctly when it runs moments later.
//
// Each frame stays at or under the helper's 30-tool display window so no
// completed tool is dropped from the counts.

'use strict';

const frame = parseInt(process.argv[2], 10) || 0;
const now = Date.now();
const iso = ms => new Date(ms).toISOString();

const out = [];
let idc = 0;
const push = (ts, content) => out.push(JSON.stringify({ timestamp: iso(ts), message: { content } }));

const inputFor = (name, target) =>
  (name === 'Read' || name === 'Edit' || name === 'Write') ? { file_path: target }
    : (name === 'Grep' || name === 'Glob') ? { pattern: target }
      : (name === 'Bash') ? { command: target }
        : {};

// A completed tool: tool_use then tool_result, finishing `endAgoS` seconds ago.
function completed(name, target, endAgoS) {
  const id = 'u' + (idc++);
  push(now - (endAgoS + 2) * 1000, [{ type: 'tool_use', id, name, input: inputFor(name, target) }]);
  push(now - endAgoS * 1000, [{ type: 'tool_result', tool_use_id: id }]);
}
// `count` completed calls of one tool, finishing within the last ~2 minutes.
const bulk = (name, count, target) => { for (let k = 0; k < count; k++) completed(name, target, 120 - k); };

// A still-running tool (no tool_result), started `elapsedS` seconds ago.
function running(name, target, elapsedS) {
  push(now - elapsedS * 1000, [{ type: 'tool_use', id: 'u' + (idc++), name, input: inputFor(name, target) }]);
}
// A running / finished subagent (Task tool).
function agentRunning(desc, elapsedS) {
  push(now - elapsedS * 1000, [{ type: 'tool_use', id: 'a' + (idc++), name: 'Task', input: { subagent_type: 'general', description: desc } }]);
}
function agentDone(desc, endAgoS) {
  const id = 'a' + (idc++);
  push(now - (endAgoS + 10) * 1000, [{ type: 'tool_use', id, name: 'Task', input: { subagent_type: 'general', description: desc } }]);
  push(now - endAgoS * 1000, [{ type: 'tool_result', tool_use_id: id }]);
}

const TODO_LABELS = ['Map the auth flow', 'Add form validation', 'Wire up the API', 'Write tests', 'Ship it'];
function todos(done) {
  const items = TODO_LABELS.map((content, idx) => ({
    content,
    status: idx < done ? 'completed' : idx === done ? 'in_progress' : 'pending'
  }));
  const id = 't' + (idc++);
  push(now - 1500, [{ type: 'tool_use', id, name: 'TodoWrite', input: { todos: items } }]);
  push(now - 1400, [{ type: 'tool_result', tool_use_id: id }]);
}

// Emission order matters: the helper's "last action" (shown with a ->) is the
// last COMPLETED tool in order, so the headline tool is emitted after the bulk
// counts and after TodoWrite. Frames with a running tool show no headline.
switch (frame) {
  case 0: // just starting: a couple of reads, the last one flashing green
    bulk('Read', 2, 'tsconfig.json');
    completed('Read', 'package.json', 2);
    break;
  case 1: // exploring: a grep running, todo list just created (0/5)
    bulk('Read', 6, 'authSlice.ts');
    bulk('Grep', 3, 'useAuth');
    bulk('Bash', 2, 'npm run lint');
    todos(0);
    running('Grep', 'useAuth', 3);
    break;
  case 2: // editing, a research subagent spun up, 2/5 done
    bulk('Read', 8, 'SignupForm.tsx');
    bulk('Edit', 2, 'authSlice.ts');
    bulk('Bash', 2, 'npm run lint');
    bulk('Grep', 3, 'validate');
    todos(2);
    completed('Edit', 'SignupForm.tsx', 15);
    agentRunning('research', 8);
    break;
  case 3: // tests running, subagent still going, 3/5 done
    bulk('Read', 10, 'api.ts');
    bulk('Edit', 5, 'SignupForm.tsx');
    bulk('Grep', 3, 'validate');
    bulk('Bash', 3, 'npm test');
    todos(3);
    running('Bash', 'npm test', 6);
    agentRunning('research', 19);
    break;
  case 4: // subagent just finished, 4/5 done
    bulk('Read', 11, 'api.ts');
    bulk('Edit', 6, 'SignupForm.tsx');
    bulk('Bash', 4, 'npm test');
    bulk('Grep', 3, 'validate');
    todos(4);
    completed('Edit', 'api.ts', 15);
    agentDone('research', 30);
    break;
  case 5: // wrapping up: all todos done, final write flashing
    bulk('Read', 12, 'api.ts');
    bulk('Edit', 8, 'SignupForm.tsx');
    bulk('Bash', 5, 'npm test');
    bulk('Grep', 3, 'validate');
    todos(5);
    completed('Write', 'README.md', 2);
    break;
}

process.stdout.write(out.join('\n') + '\n');
