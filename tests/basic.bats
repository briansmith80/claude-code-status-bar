#!/usr/bin/env bats
#
# Schema parsing — make sure both old (flat) and new (nested) shapes work,
# plus the stdin rate_limits block.

load test_helper

@test "old flat schema: display_name and used_percentage at top level" {
  run_statusline '{"cwd":"/tmp","display_name":"Sonnet","used_percentage":60,"total_cost_usd":0.50}'
  [ "$status" -eq 0 ]
  assert_plain_contains "Sonnet"
  assert_plain_contains "60%"
}

@test "new nested schema: model.display_name and context_window.used_percentage" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":78,"context_window_size":200000},"total_cost_usd":2.50}'
  [ "$status" -eq 0 ]
  assert_plain_contains "Opus"
  assert_plain_contains "78%"
  assert_plain_contains "of 200k"
}

@test "stdin rate_limits: five_hour and seven_day render usage segments" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":65},"total_cost_usd":0.50,"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1743019200},"seven_day":{"used_percentage":71,"resets_at":1743278400}}}'
  [ "$status" -eq 0 ]
  assert_plain_contains "5hr"
  assert_plain_contains "42%"
  assert_plain_contains "wk"
  assert_plain_contains "71%"
}

@test "session-start placeholder when both model and used are absent" {
  # When the script can't find a model name or context %, it prints a
  # short "Starting..." message and exits.
  run_statusline '{"cwd":"/tmp"}'
  [ "$status" -eq 0 ]
  assert_plain_contains "Starting"
}
