#!/usr/bin/env bats
#
# Colourful activity line (v2.7.0) — helper token emission (--colour), bash
# token-to-theme mapping, spinner slot, completion flash, gradient ramp,
# stale fade, activity_colour toggle, NO_COLOR, JSON quote unescaping, and
# the colour-aware width trim. Helper tests need node; they skip without it.

load test_helper

HELPER="${BATS_TEST_DIRNAME}/../statusline-helper.js"

require_node() {
  command -v node > /dev/null 2>&1 || skip "node not available"
}

iso_at() {
  date -ud "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null && return 0
  date -r "$1" -u +%Y-%m-%dT%H:%M:%SZ
}

# Write a fresh activity cache with the given (pre-tokenized) activity text.
# The text is passed as a literal printf argument, so no escape processing.
write_act_cache() {
  printf '%s %s\n' "${2:-$(date +%s)}" "{\"activity\":\"$1\"}" \
    > "${TEST_HOME}/.claude/.statusline-activity-cache"
}

# Standard stdin for line-2 tests; transcript must exist for the branch to run
act_stdin() {
  printf '{"x":1}\n' > "${TEST_HOME}/t.jsonl"
  cp "${REPO_ROOT}/statusline-helper.js" "${TEST_HOME}/.claude/statusline-helper.js"
  echo "{\"cwd\":\"/tmp\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":40},\"transcript_path\":\"${TEST_HOME}/t.jsonl\"}"
}

line2() { printf '%s' "$output" | sed -n '2p'; }

# Spinner frames the bash side can pick from the clock
is_spinner_frame() {
  case "$1" in
    *"⠋"*|*"⠙"*|*"⠸"*|*"⠴"*) return 0 ;;
    *) return 1 ;;
  esac
}

@test "helper --colour emits zero-width tokens" {
  require_node
  start_iso="$(iso_at "$(( $(date +%s) - 60 ))")"
  tr_file="${TEST_HOME}/t.jsonl"
  printf '{"timestamp":"%s","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"npm run build"}}]}}\n' "$start_iso" > "$tr_file"
  cache="${TEST_HOME}/.claude/.statusline-activity-cache"
  node "$HELPER" "$tr_file" "$cache" --colour
  activity="$(cat "$cache")"
  [[ "$activity" == *"{s}"* ]]
  [[ "$activity" == *"{w}Bash{d}"* ]]
  [[ "$activity" == *"{h2}1m"* ]]   # 60s elapsed = middle heat tier
}

@test "helper without --colour emits no tokens (back-compat)" {
  require_node
  start_iso="$(iso_at "$(( $(date +%s) - 60 ))")"
  tr_file="${TEST_HOME}/t.jsonl"
  printf '{"timestamp":"%s","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"npm run build"}}]}}\n' "$start_iso" > "$tr_file"
  cache="${TEST_HOME}/.claude/.statusline-activity-cache"
  node "$HELPER" "$tr_file" "$cache"
  activity="$(cat "$cache")"
  [[ "$activity" == *"▶ Bash npm run build 1m"* ]]
  [[ "$activity" != *"{"[a-zA-Z]* ]]
}

@test "helper --colour defuses token lookalikes in untrusted text" {
  require_node
  now_iso="$(iso_at "$(date +%s)")"
  tr_file="${TEST_HOME}/t.jsonl"
  printf '{"timestamp":"%s","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"echo {e}boo{d}"}}]}}\n' "$now_iso" > "$tr_file"
  cache="${TEST_HOME}/.claude/.statusline-activity-cache"
  node "$HELPER" "$tr_file" "$cache" --colour
  activity="$(cat "$cache")"
  [[ "$activity" != *"{e}boo"* ]]
}

@test "bash maps tokens to theme colours with a spinner frame" {
  require_node
  write_act_cache '{s} {w}Bash{d} npm test {h1}6s{d}'
  run_statusline_env "$(act_stdin)" "COLUMNS=200"
  l2="$(line2)"
  [[ "$l2" == *$'\x1b[0;33m'* ]]          # default theme CLR_WARN
  is_spinner_frame "$l2"
  [[ "$l2" != *"{w}"* ]]
  assert_plain_contains "Bash npm test 6s"
}

@test "completion flash and gradient tokens map to bold and ramp colours" {
  require_node
  write_act_cache '{i}→{d} {O}✓ Read a.ts{d}  │  {r0}█{r3}█{d}░░ 2/4'
  run_statusline_env "$(act_stdin)" "COLUMNS=200"
  l2="$(line2)"
  [[ "$l2" == *$'\x1b[1m\x1b[0;32m'* ]]   # flash = bold + CLR_ADD
  [[ "$l2" == *$'\x1b[38;5;40m'* ]]       # ramp step 0 (default theme heat ramp)
  [[ "$l2" == *$'\x1b[38;5;196m'* ]]      # ramp step 3 (default theme heat ramp)
}

@test "stale cache drops colours and restores the plain dim look" {
  require_node
  write_conf "activity_fresh_seconds=10"
  write_act_cache '{s} {w}Bash{d} npm test {h1}6s{d}' "$(( $(date +%s) - 30 ))"
  run_statusline_env "$(act_stdin)" "COLUMNS=200"
  l2="$(line2)"
  [[ "$l2" != *$'\x1b[0;33m'* ]]
  ! is_spinner_frame "$l2"
  assert_plain_contains "▶ Bash npm test 6s"
}

@test "activity_colour=false strips tokens" {
  require_node
  write_conf "activity_colour=false"
  write_act_cache '{s} {w}Bash{d} npm test {h1}6s{d}'
  run_statusline_env "$(act_stdin)" "COLUMNS=200"
  l2="$(line2)"
  [[ "$l2" != *$'\x1b[0;33m'* ]]
  [[ "$l2" != *"{w}"* ]]
  assert_plain_contains "▶ Bash npm test 6s"
}

@test "NO_COLOR keeps the spinner glyph but emits no escapes" {
  require_node
  write_act_cache '{s} {w}Bash{d} npm test {h1}6s{d}'
  run_statusline_env "$(act_stdin)" "COLUMNS=200" "NO_COLOR=1"
  l2="$(line2)"
  [[ "$l2" != *$'\x1b'* ]]
  is_spinner_frame "$l2"
  [[ "$l2" == *"Bash npm test 6s"* ]]
}

@test "JSON-escaped quotes in the activity value survive to display" {
  require_node
  write_act_cache '{s} {w}Bash{d} echo \"hi\" {h1}6s{d}'
  run_statusline_env "$(act_stdin)" "COLUMNS=200"
  assert_plain_contains 'echo "hi" 6s'
}

@test "backslash sequences in content stay literal text (no decode)" {
  require_node
  # JSON \\n = literal backslash+n in the value; must never become a newline
  write_act_cache '{s} {w}Bash{d} printf a\\nb {h1}6s{d}'
  run_statusline_env "$(act_stdin)" "COLUMNS=200"
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
  assert_plain_contains 'printf a\nb'
}

@test "colour-aware trim drops whole parts and never cuts an escape" {
  require_node
  write_act_cache '{s} {w}Bash{d} npm test {h2}1m24s{d}  │  {i}→{d} Read main.ts  [Read 5]  │  {e}✗ Edit{d}  │  {r0}█{r1}█{r2}█{d}░░░░ 3/7 Fix the failing tests'
  run_statusline_env "$(act_stdin)" "COLUMNS=40"
  l2="$(line2)"
  plain="$(strip_ansi "$l2")"
  [ -n "$plain" ]
  [ "${#plain}" -le 40 ]
  # No dangling, half-cut escape anywhere: after removing every complete
  # SGR sequence, no ESC byte may remain
  stripped="$l2"
  sgr_pat=$'\x1b''\[[0-9;]*m'
  while [[ $stripped =~ $sgr_pat ]]; do stripped="${stripped//"${BASH_REMATCH[0]}"/}"; done
  [[ "$stripped" != *$'\x1b'* ]]
}

@test "dump-config declares the new activity keys" {
  run env HOME="${TEST_HOME}" bash "${STATUSLINE_SCRIPT}" --dump-config
  [[ "$output" == *"activity_colour=true"* ]]
  [[ "$output" == *"activity_fresh_seconds=45"* ]]
  [[ "$output" == *"activity_pulse=false"* ]]
  [[ "$output" == *"activity_scanner=false"* ]]
}

@test "activity_pulse alternates intensity on the running label" {
  require_node
  write_conf "activity_pulse=true"
  write_act_cache '{s} {w}Bash{d} npm test {h1}6s{d}'
  run_statusline_env "$(act_stdin)" "COLUMNS=200"
  l2="$(line2)"
  # One of the two pulse frames must be present, plus the SGR 22 clear
  [[ "$l2" == *$'\x1b[1m'* ]] || [[ "$l2" == *$'\x1b[2m'* ]]
  [[ "$l2" == *$'\x1b[22m'* ]]
}

@test "activity_scanner appends a sweeping track while a tool runs long" {
  require_node
  write_conf "activity_scanner=true"
  write_act_cache '{s} {w}Bash{d} npm test {h2}1m24s{d}'
  run_statusline_env "$(act_stdin)" "COLUMNS=200"
  l2="$(line2)"
  [[ "$l2" == *"─"* ]]
  [[ "$l2" == *$'\x1b[38;5;199m'"█"* ]]   # default theme CLR_PACE lit cell
}

@test "pulse and scanner stay off by default" {
  require_node
  write_act_cache '{s} {w}Bash{d} npm test {h2}1m24s{d}'
  run_statusline_env "$(act_stdin)" "COLUMNS=200"
  l2="$(line2)"
  [[ "$l2" != *$'\x1b[1m'* ]]
  [[ "$l2" != *$'\x1b[2m'* ]]
  [[ "$l2" != *"─"* ]]
}
