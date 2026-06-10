#!/usr/bin/env bats
#
# Claude Code 2.1.x schema — nested cost block, current_usage, Fable tier
# colour, effort / fast-mode segments, rate-limits scoping, ISO resets_at.

load test_helper

@test "nested cost block: cost, duration and line counts parse" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40},"cost":{"total_cost_usd":1.25,"total_duration_ms":720000,"total_lines_added":10,"total_lines_removed":3}}'
  assert_plain_contains "\$1.25"
  assert_plain_contains "12m"
  assert_plain_contains "+10"
  assert_plain_contains "-3"
}

@test "context_window with nested current_usage still renders percentage" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Fable 5"},"context_window":{"total_input_tokens":241334,"total_output_tokens":194,"context_window_size":1000000,"current_usage":{"input_tokens":2,"output_tokens":194,"cache_creation_input_tokens":3205,"cache_read_input_tokens":238127},"used_percentage":24,"remaining_percentage":76}}'
  assert_plain_contains "24% of 1M"
}

@test "Fable gets the theme-aware purple tier colour" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Fable 5"},"context_window":{"used_percentage":40}}'
  [[ "$output" == *$'\x1b[38;5;141m'* ]]
}

@test "Mythos maps to the Fable tier colour" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Mythos 5"},"context_window":{"used_percentage":40}}'
  [[ "$output" == *$'\x1b[38;5;141m'* ]]
}

@test "model.id with [1m] suffix never leaks into output" {
  run_statusline '{"cwd":"/tmp","model":{"id":"claude-fable-5[1m]","display_name":"Fable 5"},"context_window":{"used_percentage":40}}'
  assert_plain_contains "Fable 5"
  assert_plain_not_contains "claude-fable-5"
  assert_plain_not_contains "[1m]"
}

@test "effort level renders as eff:<level>" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Fable 5"},"context_window":{"used_percentage":40},"effort":{"level":"xhigh"}}'
  assert_plain_contains "eff:xhigh"
}

@test "show_effort=false hides the effort segment" {
  write_conf "show_effort=false"
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Fable 5"},"context_window":{"used_percentage":40},"effort":{"level":"xhigh"}}'
  assert_plain_not_contains "eff:xhigh"
}

@test "fast_mode true shows the fast indicator" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Fable 5"},"context_window":{"used_percentage":40},"fast_mode":true}'
  assert_plain_contains "⚡ fast"
}

@test "fast_mode false shows no fast indicator" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Fable 5"},"context_window":{"used_percentage":40},"fast_mode":false}'
  assert_plain_not_contains "fast"
}

@test "five_hour outside rate_limits is ignored" {
  now=$(date +%s)
  run_statusline "{\"cwd\":\"/tmp\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":40},\"debug\":{\"five_hour\":{\"used_percentage\":99,\"resets_at\":$((now+3600))}},\"rate_limits\":{\"five_hour\":{\"used_percentage\":42,\"resets_at\":$((now+3600))}}}"
  assert_plain_contains "42%"
  assert_plain_not_contains "99%"
}

@test "ISO-8601 resets_at still yields a reset label" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":"2099-01-01T12:00:00Z"}}}'
  assert_plain_contains "42%"
  assert_plain_contains "5hr ("
}

@test "usage_label=countdown shows remaining time on the 5hr bar" {
  write_conf "usage_label=countdown"
  now=$(date +%s)
  # 2h20m plus a 45s buffer so the label stays 2h20m while the test runs
  run_statusline "{\"cwd\":\"/tmp\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":40},\"rate_limits\":{\"five_hour\":{\"used_percentage\":42,\"resets_at\":$((now + 2*3600 + 20*60 + 45))}}}"
  assert_plain_contains "5hr (2h20m)"
}

@test "usage_label=countdown shows days and hours on the weekly bar" {
  write_conf "usage_label=countdown"
  now=$(date +%s)
  run_statusline "{\"cwd\":\"/tmp\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":40},\"rate_limits\":{\"seven_day\":{\"used_percentage\":71,\"resets_at\":$((now + 3*86400 + 4*3600 + 600))}}}"
  assert_plain_contains "wk (3d4h)"
}

@test "default clock label is unchanged when usage_label is unset" {
  now=$(date +%s)
  run_statusline "{\"cwd\":\"/tmp\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":40},\"rate_limits\":{\"five_hour\":{\"used_percentage\":42,\"resets_at\":$((now + 2*3600 + 20*60))}}}"
  assert_plain_contains "5hr ("
  assert_plain_not_contains "2h20m"
}

@test "PR segment renders number from the pr block" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40},"pr":{"number":1234,"url":"https://github.com/x/y/pull/1234","review_state":"approved"}}'
  assert_plain_contains "PR #1234"
}

@test "PR segment hidden without a pr block and via show_pr=false" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40}}'
  assert_plain_not_contains "PR #"
  write_conf "show_pr=false"
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40},"pr":{"number":1234,"review_state":"pending"}}'
  assert_plain_not_contains "PR #"
}

@test "workspace.git_worktree drives the worktree segment as a fallback" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40},"workspace":{"current_dir":"/tmp","git_worktree":"feature-x"}}'
  assert_plain_contains "feature-x"
}

@test "worktree block still wins over workspace.git_worktree" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40},"worktree":{"name":"hotfix"},"workspace":{"current_dir":"/tmp","git_worktree":"feature-x"}}'
  assert_plain_contains "hotfix"
  assert_plain_not_contains "feature-x"
}
