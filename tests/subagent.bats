#!/usr/bin/env bats
#
# Subagent panel rows (statusline-subagent.js, v2.5.0). Needs node; skips
# without it. The script reads JSON on stdin and emits one JSON line per row.

load test_helper

SUBAGENT="${BATS_TEST_DIRNAME}/../statusline-subagent.js"

require_node() {
  command -v node > /dev/null 2>&1 || skip "node not available"
}

now_ms() {
  echo "$(( $(date +%s) * 1000 ))"
}

run_subagent() {
  output="$(printf '%s' "$1" | node "$SUBAGENT")"
  status=$?
  # JSON.stringify encodes ESC as literal backslash-u-001b text, so strip
  # that form as well as real escape bytes
  plain="$(printf '%s' "$output" | sed -e 's/\\u001b\[[0-9;]*m//g' | strip_ansi)"
}

@test "running task renders icon, description, elapsed, tokens, and rate" {
  require_node
  now="$(now_ms)"
  run_subagent "{\"columns\":110,\"tasks\":[{\"id\":\"t1\",\"type\":\"local_agent\",\"status\":\"running\",\"label\":\"Audit usage parsing\",\"startTime\":$((now - 90000)),\"tokenCount\":12400,\"tokenSamples\":[0,2050,4100,6150,8200,10250,12400]}]}"
  [[ "$plain" == *'"id":"t1"'* ]]
  [[ "$plain" == *"⚒ Audit usage parsing"* ]]
  [[ "$plain" == *"1m3"* ]]  # 1m30s..1m39s; tolerant of seconds ticking over
  [[ "$plain" == *"12.4k tok"* ]]
  [[ "$plain" == *"tok/s"* ]]
}

@test "completed and failed tasks get ✓ and ✗" {
  require_node
  now="$(now_ms)"
  run_subagent "{\"columns\":110,\"tasks\":[{\"id\":\"a\",\"status\":\"completed\",\"label\":\"done thing\",\"startTime\":$((now - 5000)),\"tokenCount\":500},{\"id\":\"b\",\"status\":\"failed\",\"label\":\"broken thing\",\"startTime\":$((now - 5000)),\"tokenCount\":100}]}"
  [[ "$plain" == *"✓ done thing"* ]]
  [[ "$plain" == *"✗ broken thing"* ]]
}

@test "NO_COLOR output contains no ANSI escapes" {
  require_node
  now="$(now_ms)"
  raw="$(printf '%s' "{\"columns\":110,\"tasks\":[{\"id\":\"t1\",\"status\":\"running\",\"label\":\"x\",\"startTime\":$((now - 5000)),\"tokenCount\":100}]}" | NO_COLOR=1 node "$SUBAGENT")"
  [[ "$raw" != *$'\x1b'* ]]
  [[ "$raw" == *'"id":"t1"'* ]]
}

@test "narrow columns drop the rate before truncating the description" {
  require_node
  now="$(now_ms)"
  run_subagent "{\"columns\":30,\"tasks\":[{\"id\":\"t1\",\"status\":\"running\",\"label\":\"a quite long subagent description here\",\"startTime\":$((now - 90000)),\"tokenCount\":12400,\"tokenSamples\":[0,2050,4100,6150,8200,10250,12400]}]}"
  [[ "$plain" != *"tok/s"* ]]
}

@test "invalid input produces no output and exits 0" {
  require_node
  run_subagent "not json at all"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "tasks without an id are left to default rendering" {
  require_node
  now="$(now_ms)"
  run_subagent "{\"columns\":110,\"tasks\":[{\"status\":\"running\",\"label\":\"no id row\",\"startTime\":$((now - 5000)),\"tokenCount\":100},{\"id\":\"keep\",\"status\":\"running\",\"label\":\"styled row\",\"startTime\":$((now - 5000)),\"tokenCount\":100}]}"
  [[ "$plain" != *"no id row"* ]]
  [[ "$plain" == *"styled row"* ]]
}

@test "subagent_rows=false in statusline.conf disables row styling" {
  require_node
  cp "$SUBAGENT" "${TEST_HOME}/.claude/statusline-subagent.js"
  printf 'subagent_rows=false\n' > "${TEST_HOME}/.claude/statusline.conf"
  now="$(now_ms)"
  out="$(printf '%s' "{\"columns\":110,\"tasks\":[{\"id\":\"t1\",\"status\":\"running\",\"label\":\"x\",\"startTime\":$((now - 5000)),\"tokenCount\":100}]}" | node "${TEST_HOME}/.claude/statusline-subagent.js")"
  [ -z "$out" ]
}

@test "every output line is valid JSON with id and content" {
  require_node
  now="$(now_ms)"
  run_subagent "{\"columns\":110,\"tasks\":[{\"id\":\"x1\",\"status\":\"running\",\"label\":\"alpha\",\"startTime\":$((now - 5000)),\"tokenCount\":100},{\"id\":\"x2\",\"status\":\"completed\",\"label\":\"beta\",\"startTime\":$((now - 5000)),\"tokenCount\":200}]}"
  printf '%s\n' "$output" | node -e "
    const lines = require('fs').readFileSync(0, 'utf8').trim().split('\n');
    if (lines.length !== 2) process.exit(1);
    for (const l of lines) {
      const d = JSON.parse(l);
      if (typeof d.id !== 'string' || typeof d.content !== 'string') process.exit(1);
    }
  "
}
