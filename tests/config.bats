#!/usr/bin/env bats
#
# Config-file overrides via ~/.claude/statusline.conf.
# Each test writes a fresh conf into the sandbox HOME and asserts behaviour.

load test_helper

@test "show_cost=false hides the cost segment" {
  write_conf "show_cost=false"
  run_statusline '{"cwd":"/tmp","display_name":"Sonnet","used_percentage":40,"total_cost_usd":1.23}'
  [ "$status" -eq 0 ]
  assert_plain_not_contains "\$1.23"
}

@test "show_branch=false hides the branch segment" {
  # Use the repo root as cwd so we know there IS a branch to suppress.
  # If show_branch=false works, no " on " (branch separator) text appears.
  write_conf "show_branch=false"
  run_statusline "$(printf '{"cwd":"%s","display_name":"Sonnet","used_percentage":40,"total_cost_usd":0.10}' "${REPO_ROOT}")"
  [ "$status" -eq 0 ]
  assert_plain_not_contains " on "
}

@test "bar_width=20 produces a 20-wide context bar" {
  # 100% with bar_width=20 must yield exactly 20 filled blocks.
  write_conf "bar_width=20"
  run_statusline '{"cwd":"/tmp","display_name":"Sonnet","used_percentage":100,"total_cost_usd":0.10}'
  [ "$status" -eq 0 ]
  local plain
  plain="$(strip_ansi "$output")"
  # Count █ glyphs. Each █ is a 3-byte UTF-8 sequence, so we count the byte
  # 0xE2 0x96 0x88 by collapsing first-byte 0xE2 occurrences in the bar prefix.
  local count
  count="$(printf '%s' "$plain" | grep -o '█' | wc -l | tr -d ' ')"
  [ "$count" -eq 20 ]
}

@test "branch_max_length=5 truncates long branch names" {
  # We don't want git logic to fire: point cwd at a non-git temp dir so the
  # branch is empty. Instead, exercise the truncation logic by pointing cwd
  # at the repo root (which has a real branch) and check the output length.
  #
  # If the current branch name is shorter than 5 chars, this becomes a no-op
  # check, so we skip it in that case to avoid a false pass.
  local current_branch
  current_branch="$(git -C "${REPO_ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  if [ -z "$current_branch" ] || [ "${#current_branch}" -le 5 ]; then
    skip "current branch name (${current_branch}) is too short to test truncation"
  fi

  write_conf "branch_max_length=5"
  run_statusline "$(printf '{"cwd":"%s","display_name":"Sonnet","used_percentage":40,"total_cost_usd":0.10}' "${REPO_ROOT}")"
  [ "$status" -eq 0 ]
  # Truncated branch ends with the ellipsis character.
  assert_plain_contains "…"
  # The full original branch name should NOT appear.
  assert_plain_not_contains "$current_branch"
}

DIR_JSON='{"cwd":"/tmp/aaa/bbb/project-xyz","model":{"display_name":"Opus"},"context_window":{"used_percentage":40}}'

@test "dir_style=full always shows the whole path" {
  write_conf "dir_style=full"
  run_statusline "$DIR_JSON"
  assert_plain_contains "/tmp/aaa/bbb/project-xyz"
}

@test "dir_style=basename shows only the last path component" {
  write_conf "dir_style=basename"
  run_statusline "$DIR_JSON"
  assert_plain_contains "project-xyz"
  assert_plain_not_contains "/tmp/aaa/bbb"
}

@test "dir_style=auto keeps the full path on a wide terminal" {
  write_conf "dir_style=auto" "max_width=200"
  run_statusline "$DIR_JSON"
  assert_plain_contains "/tmp/aaa/bbb/project-xyz"
}

@test "dir_style=auto collapses to the basename on a narrow terminal" {
  write_conf "dir_style=auto" "max_width=20"
  run_statusline "$DIR_JSON"
  assert_plain_contains "project-xyz"
  assert_plain_not_contains "/tmp/aaa/bbb"
}
