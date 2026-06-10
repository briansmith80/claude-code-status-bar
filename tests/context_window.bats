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

# ── Auto-compact awareness (v2.6.0) ──────────────────────────

@test "context bar shows the auto-compact marker on a 200k window" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":50,"context_window_size":200000,"total_input_tokens":100000}}'
  local plain
  plain="$(strip_ansi "$output")"
  [[ "$plain" == *"│"* ]]
}

@test "auto warning fires within 20k tokens of the compact point" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":74,"context_window_size":200000,"total_input_tokens":148000}}'
  assert_plain_contains "▲"
}

@test "no auto warning while comfortably below the compact point" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":70,"context_window_size":200000,"total_input_tokens":140000}}'
  assert_plain_not_contains "▲"
}

@test "1M window does not warn at 80% raw usage (old fixed threshold)" {
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Fable 5"},"context_window":{"used_percentage":80,"context_window_size":1000000,"total_input_tokens":800000}}'
  assert_plain_not_contains "▲"
}

@test "CLAUDE_CODE_AUTO_COMPACT_WINDOW moves the marker and warning" {
  run_statusline_env '{"cwd":"/tmp","model":{"display_name":"Fable 5"},"context_window":{"used_percentage":15,"context_window_size":1000000,"total_input_tokens":150000}}' "CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000"
  assert_plain_contains "▲"
}

@test "DISABLE_AUTO_COMPACT removes the marker and falls back to the 80% rule" {
  run_statusline_env '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":70,"context_window_size":200000,"total_input_tokens":140000}}' "DISABLE_AUTO_COMPACT=1"
  local plain
  plain="$(strip_ansi "$output")"
  [[ "$plain" != *"│"* ]]
  assert_plain_not_contains "▲"
}

@test "numeric context_warn_threshold keeps the legacy raw-percentage rule" {
  write_conf "context_warn_threshold=60"
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":65,"context_window_size":200000}}'
  assert_plain_contains "▲"
}
