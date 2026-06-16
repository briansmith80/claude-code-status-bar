#!/usr/bin/env bats
#
# Multi-line layout (v2.19.0): the `layout` preset key + line1/line2/line3
# token overrides, the dir/branch split + connector, per-line placement,
# empty-line hiding, and unknown/disabled-token safety.

load test_helper

require_git() { command -v git > /dev/null 2>&1 || skip "git not available"; }
require_node() { command -v node > /dev/null 2>&1 || skip "node not available"; }

# A git repo at $TEST_HOME/work on branch "mybranch", with a cost block so the
# duration / lines-changed segments have data.
make_repo() {
  git -c core.fsmonitor=false init -q -b mybranch "${TEST_HOME}/work"
  git -C "${TEST_HOME}/work" config user.email t@t
  git -C "${TEST_HOME}/work" config user.name t
  echo a > "${TEST_HOME}/work/f.txt"
  git -C "${TEST_HOME}/work" -c core.fsmonitor=false add f.txt
  git -C "${TEST_HOME}/work" -c core.fsmonitor=false commit -qm one
}
repo_json() {
  echo "{\"cwd\":\"${TEST_HOME}/work\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":40},\"cost\":{\"total_cost_usd\":1.25,\"total_duration_ms\":7980000,\"total_lines_added\":10,\"total_lines_removed\":3}}"
}
plain_json='{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40},"cost":{"total_cost_usd":1.25,"total_duration_ms":7980000,"total_lines_added":10,"total_lines_removed":3}}'

line_n() { printf '%s\n' "$output" | strip_ansi | sed -n "${1}p"; }
nlines() { printf '%s\n' "$output" | grep -c ''; }

@test "no config is byte-identical to an explicit layout=classic" {
  run_statusline_env "$plain_json" "COLUMNS=200"; local a="$output"
  write_conf 'layout=classic'
  run_statusline_env "$plain_json" "COLUMNS=200"; local b="$output"
  [ "$a" = "$b" ]
}

@test "default (classic) with no activity is a single line" {
  run_statusline_env "$plain_json" "COLUMNS=200"
  [ "$(nlines)" -eq 1 ]
}

@test "layout=three-line puts model/usage on line 1 and dir on line 2" {
  write_conf 'layout=three-line'
  run_statusline_env "$plain_json" "COLUMNS=200"
  [[ "$(line_n 1)" == *"Opus"* ]]
  [[ "$(line_n 1)" == *"40%"* ]]
  [[ "$(line_n 2)" == *"/tmp"* ]]
  [[ "$(line_n 1)" != *"/tmp"* ]]
}

@test "layout=stacked puts dir/branch/model/context/cost on line 1 and git/duration on line 2" {
  require_git
  make_repo
  write_conf 'layout=stacked'
  run_statusline_env "$(repo_json)" "COLUMNS=200"
  # line 1: dir + branch (branch attached after dir), model, context, cost
  [[ "$(line_n 1)" == *"mybranch"* ]]
  [[ "$(line_n 1)" == *"Opus"* ]]
  [[ "$(line_n 1)" == *"40%"* ]]
  [[ "$(line_n 1)" == *"\$1.25"* ]]
  # line 2: lines-changed and duration (not the cost, which is on line 1)
  [[ "$(line_n 2)" == *"+10"* ]]
  [[ "$(line_n 2)" == *"-3"* ]]
  [[ "$(line_n 2)" == *"2h13m"* ]]
  [[ "$(line_n 2)" != *"\$1.25"* ]]
}

@test "an explicit lineN overrides the preset for that line" {
  # Override only line1; line2 still comes from the three-line preset (dir).
  # A token lives on the first line that lists it, so cost moves to line 1.
  write_conf 'layout=three-line' 'line1="cost model"'
  run_statusline_env "$plain_json" "COLUMNS=200"
  [[ "$(line_n 1)" == *"\$1.25"* ]]   # cost now on the overridden line 1
  [[ "$(line_n 1)" == *"Opus"* ]]
  [[ "$(line_n 1)" != *"5hr"* ]]      # preset's usage is gone from line 1
  [[ "$(line_n 2)" == *"/tmp"* ]]     # preset's line 2 (dir) is intact
}

@test "explicit line1 hides segments that are not listed" {
  write_conf 'line1="model context"' 'line2=""' 'line3=""'
  run_statusline_env "$plain_json" "COLUMNS=200"
  [ "$(nlines)" -eq 1 ]
  [[ "$(line_n 1)" == *"Opus"* ]]
  [[ "$(line_n 1)" == *"40%"* ]]
  [[ "$(line_n 1)" != *"\$1.25"* ]]
}

@test "an empty / all-missing line does not print a blank row" {
  # line2 references a segment with no data; it must be skipped, not blanked.
  write_conf 'line1="model"' 'line2="worktree"' 'line3="cost"'
  run_statusline_env "$plain_json" "COLUMNS=200"
  [ "$(nlines)" -eq 2 ]
  [[ "$(line_n 1)" == *"Opus"* ]]
  [[ "$(line_n 2)" == *"\$1.25"* ]]
}

@test "an unknown token is ignored and the script still exits 0" {
  write_conf 'line1="model bogus_token context"'
  run_statusline_env "$plain_json" "COLUMNS=200"
  [ "$status" -eq 0 ]
  [[ "$(line_n 1)" == *"Opus"* ]]
  [[ "$(line_n 1)" == *"40%"* ]]
  [[ "$(line_n 1)" != *"bogus_token"* ]]
}

@test "a token whose show_* flag is false never appears" {
  write_conf 'line1="model cost"' 'show_cost=false'
  run_statusline_env "$plain_json" "COLUMNS=200"
  [[ "$(line_n 1)" == *"Opus"* ]]
  [[ "$(line_n 1)" != *"\$1.25"* ]]
}

@test "dir and branch adjacent render the combined 'on <branch>' exactly once" {
  require_git
  make_repo
  run_statusline_env "$(repo_json)" "COLUMNS=200"
  local l1 count
  l1="$(line_n 1)"
  [[ "$l1" == *"on mybranch"* ]] || [[ "$l1" == *"on ↱ mybranch"* ]]
  count="$(printf '%s' "$l1" | grep -o 'mybranch' | grep -c '')"
  [ "$count" -eq 1 ]
}

@test "branch placed apart from dir renders without an orphan ' on '" {
  require_git
  make_repo
  write_conf 'line1="branch"' 'line2="dir"'
  run_statusline_env "$(repo_json)" "COLUMNS=200"
  [[ "$(line_n 1)" == *"mybranch"* ]]
  [[ "$(line_n 1)" != *" on "* ]]
}

@test "activity token can be placed on line 1 alongside metrics" {
  require_node
  cp "${REPO_ROOT}/statusline-helper.js" "${TEST_HOME}/.claude/statusline-helper.js"
  local tr_file="${TEST_HOME}/t.jsonl"; printf '{"x":1}\n' > "$tr_file"
  printf '%s {"activity":"ACT_MARKER"}\n' "$(date +%s)" \
    > "${TEST_HOME}/.claude/.statusline-activity-cache"
  write_conf 'line1="activity model"' 'line2="dir"'
  run_statusline_env "{\"cwd\":\"/tmp\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":40},\"transcript_path\":\"${tr_file}\"}" "COLUMNS=120"
  [[ "$(line_n 1)" == *"ACT_MARKER"* ]]
  [[ "$(line_n 1)" == *"Opus"* ]]
}

@test "--dump-config declares the layout and icon_set keys" {
  output="$(HOME="${TEST_HOME}" bash "${STATUSLINE_SCRIPT}" --dump-config)"
  [[ "$output" == *"layout=classic"* ]]
  [[ "$output" == *"icon_set=classic"* ]]
  [[ "$output" == *"line1="* ]]
  [[ "$output" == *"line2="* ]]
  [[ "$output" == *"line3="* ]]
}
