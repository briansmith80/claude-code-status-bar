#!/usr/bin/env bats
#
# Segment rendering — directory, model, cost, vim mode, agent name,
# and the automatic 200k token warning.

load test_helper

@test "working directory shows" {
  # Use the sandbox HOME so the dir is rendered as a literal path.
  run_statusline '{"cwd":"/tmp/cc-test-dir","display_name":"Sonnet","used_percentage":10,"total_cost_usd":0.10}'
  [ "$status" -eq 0 ]
  assert_plain_contains "/tmp/cc-test-dir"
}

@test "Windows cwd: JSON-escaped backslashes decode to single backslashes" {
  # Claude Code sends Windows paths as valid JSON, escaping each separator as
  # "\\". The bar must decode it back to a single "\" instead of echoing the
  # doubled form. A non-existent path keeps it deterministic (no git runs).
  run_statusline '{"cwd":"C:\\Users\\dev\\my-project","model":{"display_name":"Opus"},"context_window":{"used_percentage":42}}'
  [ "$status" -eq 0 ]
  assert_plain_contains 'C:\Users\dev\my-project'
  assert_plain_not_contains 'C:\\Users'
}

@test "UNC-style cwd with consecutive backslashes decodes correctly" {
  # "\\\\server\\share" (JSON) -> "\\server\share". Guards the single-pass
  # decoder against off-by-one drift across adjacent escapes.
  run_statusline '{"cwd":"\\\\server\\share\\proj","model":{"display_name":"Opus"},"context_window":{"used_percentage":42}}'
  [ "$status" -eq 0 ]
  assert_plain_contains '\\server\share\proj'
  assert_plain_not_contains '\\\\server'
}

@test "model name appears" {
  run_statusline '{"cwd":"/tmp","display_name":"Haiku","used_percentage":5,"total_cost_usd":0.01}'
  [ "$status" -eq 0 ]
  assert_plain_contains "Haiku"
}

@test "cost segment appears when total_cost_usd is non-zero" {
  run_statusline '{"cwd":"/tmp","display_name":"Sonnet","used_percentage":40,"total_cost_usd":1.23}'
  [ "$status" -eq 0 ]
  assert_plain_contains "\$1.23"
}

@test "cost segment hidden when total_cost_usd is absent" {
  run_statusline '{"cwd":"/tmp","display_name":"Sonnet","used_percentage":40}'
  [ "$status" -eq 0 ]
  # No dollar sign anywhere in the plain output
  assert_plain_not_contains "$"
}

@test "vim mode segment renders when vim.mode is present" {
  run_statusline '{"cwd":"/tmp","display_name":"Sonnet","used_percentage":40,"vim":{"mode":"NORMAL"}}'
  [ "$status" -eq 0 ]
  assert_plain_contains "NORMAL"
}

@test "agent name segment renders when agent.name is present" {
  run_statusline '{"cwd":"/tmp","display_name":"Sonnet","used_percentage":40,"agent":{"name":"my-agent"}}'
  [ "$status" -eq 0 ]
  assert_plain_contains "my-agent"
}

@test "exceeds_200k_tokens no longer renders a segment (long-context premium pricing was retired)" {
  run_statusline '{"cwd":"/tmp","display_name":"Sonnet","used_percentage":40,"exceeds_200k_tokens":true}'
  [ "$status" -eq 0 ]
  assert_plain_not_contains "200k+"
}
