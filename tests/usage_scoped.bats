#!/usr/bin/env bats
#
# Model-scoped weekly limit swap (v2.24.0, usage_scoped, default on):
#   - the wk bar swaps to a per-model weekly limit ("wk:Fable") when that
#     limit is running HIGHER than the all-models one (it binds first)
#   - data comes from the OAuth usage cache's limits[] weekly_scoped entry
#     (Claude Code does not forward it on stdin)
#   - equal/lower scoped usage, usage_scoped=false, or a stale cache all
#     keep the plain all-models bar; stdin 5h/7d numbers are never clobbered

load test_helper

# ISO-8601 UTC timestamp N seconds from now (GNU date, BSD/macOS fallback).
# Realistic near-future resets keep countdown labels short — a far-future date
# would balloon the label ("26482d17h") and trigger width truncation.
iso_in() {
  local ts=$(( $(date +%s) + $1 ))
  date -u -d "@$ts" '+%Y-%m-%dT%H:%M:%S+00:00' 2>/dev/null \
    || date -u -r "$ts" '+%Y-%m-%dT%H:%M:%S+00:00'
}

# Seed the OAuth usage cache with a canned response carrying an all-models
# weekly of 28% and a scoped weekly.
# Usage: seed_usage_cache <scoped_pct> [age_secs] [model_json]
seed_usage_cache() {
  local scoped_pct="$1" age="${2:-0}" model_json="${3:-}"
  [ -z "$model_json" ] && model_json='{"id":null,"display_name":"Fable"}'
  local r5 r7
  r5="$(iso_in $(( 3*3600 )))"
  r7="$(iso_in $(( 4*86400 )))"
  printf '%s %s\n' "$(( $(date +%s) - age ))" \
    '{"five_hour":{"utilization":19.0,"resets_at":"'"$r5"'"},"seven_day":{"utilization":28.0,"resets_at":"'"$r7"'"},"seven_day_opus":null,"limits":[{"kind":"session","group":"session","percent":19,"severity":"normal","resets_at":"'"$r5"'","scope":null,"is_active":false},{"kind":"weekly_all","group":"weekly","percent":28,"severity":"normal","resets_at":"'"$r7"'","scope":null,"is_active":false},{"kind":"weekly_scoped","group":"weekly","percent":'"$scoped_pct"',"severity":"normal","resets_at":"'"$r7"'","scope":{"model":'"$model_json"',"surface":null},"is_active":true}]}' \
    > "${TEST_HOME}/.claude/.statusline-usage-cache"
}

# stdin payload with real-time rate limits: 5h 19%, all-models weekly 28%
stdin_json() {
  local now; now=$(date +%s)
  printf '{"cwd":"/tmp","model":{"display_name":"Fable 5"},"context_window":{"used_percentage":40},"rate_limits":{"five_hour":{"used_percentage":19,"resets_at":%s},"seven_day":{"used_percentage":28,"resets_at":%s}}}' \
    "$(( now + 3*3600 ))" "$(( now + 4*86400 ))"
}

# ── Config registration ──────────────────────────────────────

@test "usage_scoped defaults to true and appears in --dump-config" {
  output="$(HOME="${TEST_HOME}" bash "${STATUSLINE_SCRIPT}" --dump-config 2>/dev/null)"
  [[ "$output" == *"usage_scoped=true"* ]]
}

# ── Swap policy ──────────────────────────────────────────────

@test "scoped weekly higher than all-models swaps the wk bar (stdin-native)" {
  seed_usage_cache 36
  run_statusline "$(stdin_json)"
  assert_plain_contains "wk:Fable"
  assert_plain_contains "36%"
  assert_plain_not_contains "28%"
}

@test "scoped weekly lower than all-models keeps the plain wk bar" {
  seed_usage_cache 12
  run_statusline "$(stdin_json)"
  assert_plain_not_contains "wk:Fable"
  assert_plain_contains "28%"
}

@test "scoped weekly equal to all-models keeps the plain wk bar" {
  seed_usage_cache 28
  run_statusline "$(stdin_json)"
  assert_plain_not_contains "wk:Fable"
}

@test "usage_scoped=false disables the swap" {
  write_conf "usage_scoped=false"
  seed_usage_cache 36
  run_statusline "$(stdin_json)"
  assert_plain_not_contains "wk:Fable"
  assert_plain_contains "28%"
}

@test "stale cache (beyond 6x refresh interval) never swaps" {
  seed_usage_cache 36 7200
  run_statusline "$(stdin_json)"
  assert_plain_not_contains "wk:Fable"
  assert_plain_contains "28%"
}

@test "swap also works on the OAuth fallback path (no stdin rate limits)" {
  seed_usage_cache 36
  run_statusline '{"cwd":"/tmp","model":{"display_name":"Fable 5"},"context_window":{"used_percentage":40}}'
  assert_plain_contains "wk:Fable"
  assert_plain_contains "36%"
}

@test "stdin 5h number survives the swap untouched" {
  seed_usage_cache 36
  run_statusline "$(stdin_json)"
  assert_plain_contains "19%"
}

# ── Hardening ────────────────────────────────────────────────

@test "missing model display_name still swaps with a plain wk prefix" {
  seed_usage_cache 36 0 '{"id":null,"display_name":null}'
  run_statusline "$(stdin_json)"
  assert_plain_not_contains "wk:"
  assert_plain_contains "36%"
}

@test "control bytes in the model name are sanitized out" {
  # A raw CSI sequence embedded in the cached display_name must be stripped by
  # sanitize(), leaving the printable letters. ESC[999m is not a code the
  # themes ever emit, so its absence can be asserted against raw output.
  local esc; esc=$(printf '\033')
  seed_usage_cache 36 0 "{\"id\":null,\"display_name\":\"Fa${esc}[999mble\"}"
  run_statusline "$(stdin_json)"
  assert_plain_contains "wk:Fable"
  assert_plain_contains "36%"
  [[ "$output" != *"${esc}[999m"* ]]
}

@test "no usage cache at all leaves the default bar unchanged" {
  run_statusline "$(stdin_json)"
  assert_plain_contains "28%"
  assert_plain_not_contains "wk:"
}
