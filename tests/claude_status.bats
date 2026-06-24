#!/usr/bin/env bats
#
# Claude API status segment (v2.23.0):
#   - opt-in (default off), shows ONLY when degraded
#   - tier floor (claude_status_min), severity glyph/colour mapping
#   - staleness ceiling, fail-silent guard, OSC 8 link (honours pr_link)
#   - summary.json parser + the "monitoring incident while indicator=none"
#     under-report escalation (file://, skipped on Windows)

load test_helper

STATUS_JSON='{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40}}'

# Seed the status cache directly (no network). seed_status <indicator> [age_secs]
seed_status() {
  local ind="$1" age="${2:-0}"
  printf '%s %s\n' "$(( $(date +%s) - age ))" "$ind" \
    > "${TEST_HOME}/.claude/.statusline-claude-status-cache"
}

# file:// fetches go through the platform curl/wget; native Windows curl can't
# resolve MSYS file:// paths, so skip those tests there (mirrors update.bats).
skip_if_windows() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) skip "file:// fetch unreliable with Windows curl" ;;
  esac
}

# ── Config registration ──────────────────────────────────────

@test "show_claude_status defaults to false and appears in --dump-config" {
  output="$(HOME="${TEST_HOME}" bash "${STATUSLINE_SCRIPT}" --dump-config 2>/dev/null)"
  [[ "$output" == *"show_claude_status=false"* ]]
  [[ "$output" == *"claude_status_min=major"* ]]
  [[ "$output" == *"claude_status_cache_seconds=300"* ]]
}

# ── Display policy ───────────────────────────────────────────

@test "healthy (none) shows no badge even when enabled" {
  write_conf "show_claude_status=true"
  seed_status none
  run_statusline "$STATUS_JSON"
  assert_plain_not_contains "Claude:"
}

@test "major outage shows a badge" {
  write_conf "show_claude_status=true"
  seed_status major
  run_statusline "$STATUS_JSON"
  assert_plain_contains "Claude: major outage"
}

@test "critical outage shows a critical badge" {
  write_conf "show_claude_status=true"
  seed_status critical
  run_statusline "$STATUS_JSON"
  assert_plain_contains "Claude: critical outage"
}

@test "minor is suppressed under the default (major) floor" {
  write_conf "show_claude_status=true"
  seed_status minor
  run_statusline "$STATUS_JSON"
  assert_plain_not_contains "Claude:"
}

@test "minor is shown when claude_status_min=minor" {
  write_conf "show_claude_status=true" "claude_status_min=minor"
  seed_status minor
  run_statusline "$STATUS_JSON"
  assert_plain_contains "Claude: degraded"
}

@test "maintenance shows (as info) only at the minor floor" {
  write_conf "show_claude_status=true" "claude_status_min=minor"
  seed_status maintenance
  run_statusline "$STATUS_JSON"
  assert_plain_contains "Claude: maintenance"
}

@test "maintenance is suppressed under the default (major) floor" {
  write_conf "show_claude_status=true"
  seed_status maintenance
  run_statusline "$STATUS_JSON"
  assert_plain_not_contains "Claude:"
}

@test "a stale cache (past the ceiling) shows no badge" {
  # cache_seconds=60 -> ceiling 360s; age 3000s is well past it. Point the URL
  # at a bogus file:// so the stale-triggered background refresh hits nothing.
  write_conf "show_claude_status=true" "claude_status_cache_seconds=60"
  seed_status major 3000
  run_statusline_env "$STATUS_JSON" "STATUSLINE_CLAUDE_STATUS_URL=file:///nonexistent-cc-status"
  assert_plain_not_contains "Claude:"
}

@test "default (show_claude_status=false) shows nothing even when critical" {
  seed_status critical
  run_statusline "$STATUS_JSON"
  assert_plain_not_contains "Claude:"
}

# ── Hyperlink (honours pr_link, like the update notice) ──────

@test "the badge links to status.claude.com by default" {
  write_conf "show_claude_status=true"
  seed_status major
  run_statusline "$STATUS_JSON"
  [[ "$output" == *$'\x1b]8;;https://status.claude.com\x1b\\'* ]]
  [[ "$output" == *$'\x1b]8;;\x1b\\'* ]]   # close sequence
}

@test "pr_link=false drops the hyperlink but keeps the badge text" {
  write_conf "show_claude_status=true" "pr_link=false"
  seed_status major
  run_statusline "$STATUS_JSON"
  [[ "$output" != *$'\x1b]8'* ]]
  assert_plain_contains "Claude: major outage"
}

# ── use_icons ────────────────────────────────────────────────

@test "use_icons=false drops the glyph but keeps the text" {
  write_conf "show_claude_status=true" "use_icons=false"
  seed_status major
  run_statusline "$STATUS_JSON"
  assert_plain_contains "Claude: major outage"
  assert_plain_not_contains "●"
}

# ── status.json parser (file://) ─────────────────────────────

# Run the background writer against a local fixture and wait for the cache.
write_status_via_fixture() {
  local fixture="$1"
  rm -f "${TEST_HOME}/.claude/.statusline-claude-status-cache"
  printf 'show_claude_status=true\n' > "${TEST_HOME}/.claude/statusline.conf"
  printf '%s' "$STATUS_JSON" | HOME="${TEST_HOME}" \
    STATUSLINE_CLAUDE_STATUS_URL="file://${fixture}" \
    bash "${STATUSLINE_SCRIPT}" >/dev/null 2>&1
  local i
  for i in $(seq 1 25); do
    [ -s "${TEST_HOME}/.claude/.statusline-claude-status-cache" ] && return 0
    sleep 0.2
  done
  return 0
}

@test "status.json: the page indicator is cached verbatim (critical)" {
  command -v curl >/dev/null 2>&1 || skip "curl required for file:// fetch"
  skip_if_windows
  local fx="${TEST_HOME}/crit.json"
  cat > "$fx" <<'EOF'
{"page":{"id":"x"},"status":{"indicator":"critical","description":"Major Service Outage"}}
EOF
  write_status_via_fixture "$fx"
  read -r _ ind < "${TEST_HOME}/.claude/.statusline-claude-status-cache"
  [ "$ind" = "critical" ]
}

@test "status.json: a healthy page caches 'none'" {
  command -v curl >/dev/null 2>&1 || skip "curl required for file:// fetch"
  skip_if_windows
  local fx="${TEST_HOME}/healthy.json"
  cat > "$fx" <<'EOF'
{"page":{"id":"x"},"status":{"indicator":"none","description":"All Systems Operational"}}
EOF
  write_status_via_fixture "$fx"
  read -r _ ind < "${TEST_HOME}/.claude/.statusline-claude-status-cache"
  [ "$ind" = "none" ]
}

@test "an open critical incident while indicator=none is NOT surfaced (trust the indicator, v2.23.1)" {
  # Regression: a mitigated 'monitoring' incident (components recovered) or a
  # long-lived suspension leaves the page indicator at 'none'. We deliberately
  # do NOT escalate on the incident's impact, so the badge stays clear while
  # requests still work. (v2.23.0 took the worst-of and wrongly read 'critical'.)
  command -v curl >/dev/null 2>&1 || skip "curl required for file:// fetch"
  skip_if_windows
  local fx="${TEST_HOME}/underreport.json"
  cat > "$fx" <<'EOF'
{"page":{"id":"x"},"components":[{"name":"claude.ai","status":"operational"}],"incidents":[{"id":"a","name":"Suspended access to a model","status":"monitoring","impact":"critical","resolved_at":null}],"status":{"indicator":"none","description":"All Systems Operational"}}
EOF
  write_status_via_fixture "$fx"
  read -r _ ind < "${TEST_HOME}/.claude/.statusline-claude-status-cache"
  [ "$ind" = "none" ]
}

@test "a garbage (non-JSON) response writes nothing — never a false 'down'" {
  command -v curl >/dev/null 2>&1 || skip "curl required for file:// fetch"
  skip_if_windows
  local fx="${TEST_HOME}/garbage.json"
  printf '<html>503 Service Unavailable</html>\n' > "$fx"
  rm -f "${TEST_HOME}/.claude/.statusline-claude-status-cache"
  printf 'show_claude_status=true\n' > "${TEST_HOME}/.claude/statusline.conf"
  printf '%s' "$STATUS_JSON" | HOME="${TEST_HOME}" \
    STATUSLINE_CLAUDE_STATUS_URL="file://${fx}" \
    bash "${STATUSLINE_SCRIPT}" >/dev/null 2>&1
  sleep 1
  [ ! -f "${TEST_HOME}/.claude/.statusline-claude-status-cache" ]
}
