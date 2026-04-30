#!/usr/bin/env bats
#
# Context-window size formatting and progress-bar fill behaviour.

load test_helper

@test "200,000 token window renders as 'of 200k'" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":50,"context_window_size":200000}}'
  [ "$status" -eq 0 ]
  assert_plain_contains "of 200k"
}

@test "1,000,000 token window renders as 'of 1M'" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":50,"context_window_size":1000000}}'
  [ "$status" -eq 0 ]
  assert_plain_contains "of 1M"
}

@test "1,500,000 token window renders as 'of 1.5M'" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":50,"context_window_size":1500000}}'
  [ "$status" -eq 0 ]
  assert_plain_contains "of 1.5M"
}

@test "0% usage shows zero filled blocks" {
  run_statusline '{"cwd":"/tmp","display_name":"Sonnet","used_percentage":0,"total_cost_usd":0.10}'
  [ "$status" -eq 0 ]
  local plain
  plain="$(strip_ansi "$output")"
  local count
  count="$(printf '%s' "$plain" | grep -o '█' | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
  assert_plain_contains "0%"
}

@test "100% usage shows 10 filled blocks at default bar_width=10" {
  run_statusline '{"cwd":"/tmp","display_name":"Sonnet","used_percentage":100,"total_cost_usd":0.10}'
  [ "$status" -eq 0 ]
  local plain
  plain="$(strip_ansi "$output")"
  local count
  count="$(printf '%s' "$plain" | grep -o '█' | wc -l | tr -d ' ')"
  [ "$count" -eq 10 ]
  assert_plain_contains "100%"
}
