#!/usr/bin/env bats
#
# Live activity line (v2.4.0) — age-out of completed items, failed-tool
# indicator, running-tool elapsed time, incremental parsing, activity_ttl,
# and terminal-width trimming. Helper tests need node; they skip without it.

load test_helper

HELPER="${BATS_TEST_DIRNAME}/../statusline-helper.js"

require_node() {
  command -v node > /dev/null 2>&1 || skip "node not available"
}

# Portable epoch -> ISO-8601 UTC (GNU date, falling back to BSD/macOS date)
iso_at() {
  date -ud "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null && return 0
  date -r "$1" -u +%Y-%m-%dT%H:%M:%SZ
}

# Run the helper on a transcript and load the produced activity string
run_helper() {
  local transcript="$1"
  local cache="${TEST_HOME}/.claude/.statusline-activity-cache"
  node "$HELPER" "$transcript" "$cache"
  activity="$(cat "$cache")"
}

@test "recently completed tool shows as last action with counts" {
  require_node
  now_iso="$(iso_at "$(date +%s)")"
  tr_file="${TEST_HOME}/t.jsonl"
  printf '{"timestamp":"%s","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/src/a.ts"}}]}}\n{"timestamp":"%s","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}\n' "$now_iso" "$now_iso" > "$tr_file"
  run_helper "$tr_file"
  [[ "$activity" == *"→ Read a.ts"* ]]
  [[ "$activity" == *"[Read 1]"* ]]
}

@test "completed agent older than five minutes ages out" {
  require_node
  old_iso="$(iso_at "$(( $(date +%s) - 3600 ))")"
  tr_file="${TEST_HOME}/t.jsonl"
  printf '{"timestamp":"%s","message":{"content":[{"type":"tool_use","id":"a1","name":"Task","input":{"description":"old research"}}]}}\n{"timestamp":"%s","message":{"content":[{"type":"tool_result","tool_use_id":"a1"}]}}\n{"timestamp":"%s","message":{"content":[{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"/src/b.ts"}}]}}\n{"timestamp":"%s","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}\n' "$old_iso" "$old_iso" "$old_iso" "$old_iso" > "$tr_file"
  run_helper "$tr_file"
  [[ "$activity" != *"⚒"* ]]
  [[ "$activity" != *"old research"* ]]
  [[ "$activity" == *"[Edit 1]"* ]]
}

@test "recent tool failure shows the ✗ indicator" {
  require_node
  now_iso="$(iso_at "$(date +%s)")"
  tr_file="${TEST_HOME}/t.jsonl"
  printf '{"timestamp":"%s","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"npm test"}}]}}\n{"timestamp":"%s","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":true}]}}\n' "$now_iso" "$now_iso" > "$tr_file"
  run_helper "$tr_file"
  [[ "$activity" == *"✗ Bash npm test"* ]]
}

@test "running tool shows elapsed time after a few seconds" {
  require_node
  start_iso="$(iso_at "$(( $(date +%s) - 60 ))")"
  tr_file="${TEST_HOME}/t.jsonl"
  printf '{"timestamp":"%s","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"npm run build"}}]}}\n' "$start_iso" > "$tr_file"
  run_helper "$tr_file"
  [[ "$activity" == *"▶ Bash npm run build 1m"* ]]
}

@test "incremental parse picks up appended entries and advances the offset" {
  require_node
  now_iso="$(iso_at "$(date +%s)")"
  tr_file="${TEST_HOME}/t.jsonl"
  printf '{"timestamp":"%s","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/src/a.ts"}}]}}\n{"timestamp":"%s","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}\n' "$now_iso" "$now_iso" > "$tr_file"
  run_helper "$tr_file"
  cache_file="$(ls "${TEST_HOME}/.claude/.statusline-transcript-cache/"*.json)"
  off1="$(grep -o '"offset":[0-9]*' "$cache_file" | cut -d: -f2)"
  printf '{"timestamp":"%s","message":{"content":[{"type":"tool_use","id":"t2","name":"Edit","input":{"file_path":"/src/uniq.ts"}}]}}\n{"timestamp":"%s","message":{"content":[{"type":"tool_result","tool_use_id":"t2"}]}}\n' "$now_iso" "$now_iso" >> "$tr_file"
  run_helper "$tr_file"
  off2="$(grep -o '"offset":[0-9]*' "$cache_file" | cut -d: -f2)"
  [ "$off2" -gt "$off1" ]
  [[ "$activity" == *"→ Edit uniq.ts"* ]]
  [[ "$activity" == *"Edit 1"* ]]
  [[ "$activity" == *"Read 1"* ]]
}

@test "activity cache within activity_ttl_seconds renders line 2" {
  require_node
  cp "${REPO_ROOT}/statusline-helper.js" "${TEST_HOME}/.claude/statusline-helper.js"
  tr_file="${TEST_HOME}/t.jsonl"
  printf '{"x":1}\n' > "$tr_file"
  printf '%s {"activity":"MARKER_FRESH"}\n' "$(( $(date +%s) - 60 ))" \
    > "${TEST_HOME}/.claude/.statusline-activity-cache"
  run_statusline "{\"cwd\":\"/tmp\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":40},\"transcript_path\":\"${tr_file}\"}"
  assert_plain_contains "MARKER_FRESH"
}

@test "activity cache older than activity_ttl_seconds is hidden" {
  require_node
  cp "${REPO_ROOT}/statusline-helper.js" "${TEST_HOME}/.claude/statusline-helper.js"
  write_conf "activity_ttl_seconds=30"
  tr_file="${TEST_HOME}/t.jsonl"
  printf '{"x":1}\n' > "$tr_file"
  printf '%s {"activity":"MARKER_STALE"}\n' "$(( $(date +%s) - 60 ))" \
    > "${TEST_HOME}/.claude/.statusline-activity-cache"
  run_statusline "{\"cwd\":\"/tmp\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":40},\"transcript_path\":\"${tr_file}\"}"
  assert_plain_not_contains "MARKER_STALE"
}

# Under the default `classic` layout the activity line is always row 2, so
# `sed -n '2p'` is valid here. Custom layouts (v2.19.0+) can relocate it.
@test "line 2 is trimmed to COLUMNS" {
  require_node
  cp "${REPO_ROOT}/statusline-helper.js" "${TEST_HOME}/.claude/statusline-helper.js"
  tr_file="${TEST_HOME}/t.jsonl"
  printf '{"x":1}\n' > "$tr_file"
  long_activity="$(printf 'X%.0s' $(seq 1 120))"
  printf '%s {"activity":"%s"}\n' "$(date +%s)" "$long_activity" \
    > "${TEST_HOME}/.claude/.statusline-activity-cache"
  run_statusline_env "{\"cwd\":\"/tmp\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":40},\"transcript_path\":\"${tr_file}\"}" "COLUMNS=40"
  line2="$(printf '%s' "$output" | strip_ansi | sed -n '2p')"
  [ -n "$line2" ]
  [ "${#line2}" -le 40 ]
}
