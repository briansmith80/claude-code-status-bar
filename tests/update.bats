#!/usr/bin/env bats
#
# Frictionless update (v2.11.0):
#   - the --update self-update flag
#   - the update-available notice now shows the new version and links to its
#     release notes via an OSC 8 hyperlink (honours pr_link)

load test_helper

# A minimal stdin payload; the update notice is independent of these fields.
NOTICE_JSON='{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40}}'

# Force the "update available" state by writing a fresh cache whose version is
# higher than the sandbox's pinned VERSION.
force_update_notice() {
  printf '%s %s\n' "$(date +%s)" "9.9.9" \
    > "${TEST_HOME}/.claude/.statusline-update-cache"
}

# file:// fetches go through the platform curl/wget. Native curl.exe on
# Windows cannot resolve MSYS-style file:// paths, so skip there.
skip_if_windows() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) skip "file:// fetch unreliable with Windows curl" ;;
  esac
}

@test "--help lists the --update flag" {
  output="$(HOME="${TEST_HOME}" bash "${STATUSLINE_SCRIPT}" --help 2>/dev/null)"
  [[ "$output" == *"--update"* ]]
}

@test "update notice shows the new version number" {
  force_update_notice
  run_statusline "$NOTICE_JSON"
  assert_plain_contains "9.9.9"
}

@test "update notice is hidden when the cached version is OLDER than current" {
  # Regression (v2.19.1): raw.githubusercontent.com can serve the previous
  # VERSION for minutes after a release, caching an OLDER version. The notice
  # must fire only for a strictly-newer version, never a phantom downgrade.
  printf '%s %s\n' "$(date +%s)" "0.0.1" \
    > "${TEST_HOME}/.claude/.statusline-update-cache"
  run_statusline "$NOTICE_JSON"
  assert_plain_not_contains "0.0.1"
  assert_plain_not_contains "↑"
}

@test "update notice is hidden when the cached version equals current" {
  local ver
  ver="$(tr -d '[:space:]' < "${TEST_HOME}/.claude/.statusline-version")"
  printf '%s %s\n' "$(date +%s)" "$ver" \
    > "${TEST_HOME}/.claude/.statusline-update-cache"
  run_statusline "$NOTICE_JSON"
  assert_plain_not_contains "↑"
}

@test "update notice links to the release notes by default" {
  force_update_notice
  run_statusline "$NOTICE_JSON"
  [[ "$output" == *$'\x1b]8;;https://github.com/briansmith80/claude-code-status-bar/releases/tag/v9.9.9\x1b\\'* ]]
  [[ "$output" == *$'\x1b]8;;\x1b\\'* ]]   # close sequence
}

@test "pr_link=false drops the update-notice hyperlink but keeps the version" {
  write_conf "pr_link=false"
  force_update_notice
  run_statusline "$NOTICE_JSON"
  [[ "$output" != *$'\x1b]8'* ]]
  assert_plain_contains "9.9.9"
}

@test "--update installs files from the repo source and reports the new version" {
  command -v curl >/dev/null 2>&1 || skip "curl required for file:// fetch"
  skip_if_windows
  remote_dir="$(mktemp -d "${BATS_TMPDIR:-/tmp}/cc-remote-XXXXXX")"
  printf '9.9.9\n'              > "${remote_dir}/VERSION"
  printf 'echo new-command\n'   > "${remote_dir}/statusline-command.sh"
  printf '// new helper\n'      > "${remote_dir}/statusline-helper.js"
  printf '// new subagent\n'    > "${remote_dir}/statusline-subagent.js"
  printf '# template marker\n'  > "${remote_dir}/statusline.conf.example"

  output="$(HOME="${TEST_HOME}" STATUSLINE_REPO_RAW="file://${remote_dir}" \
    bash "${STATUSLINE_SCRIPT}" --update 2>&1)"
  local rc=$?

  [ "$rc" -eq 0 ]
  [[ "$output" == *"9.9.9 available"* ]]
  [[ "$output" == *"Done"* ]]
  [ "$(tr -d '[:space:]' < "${TEST_HOME}/.claude/.statusline-version")" = "9.9.9" ]
  grep -q "new-command" "${TEST_HOME}/.claude/statusline-command.sh"
  grep -q "new helper"  "${TEST_HOME}/.claude/statusline-helper.js"
  grep -q "new subagent" "${TEST_HOME}/.claude/statusline-subagent.js"
  # Refreshes the template and seeds statusline.conf when absent.
  grep -q "template marker" "${TEST_HOME}/.claude/statusline.conf.example"
  grep -q "template marker" "${TEST_HOME}/.claude/statusline.conf"
  # The update cache is cleared so the notice clears on the next render.
  [ ! -f "${TEST_HOME}/.claude/.statusline-update-cache" ]
  rm -rf "${remote_dir}"
}

@test "--update refreshes the template but never overwrites an existing statusline.conf" {
  command -v curl >/dev/null 2>&1 || skip "curl required for file:// fetch"
  skip_if_windows
  write_conf "colour_theme=nord"   # user already has a config
  remote_dir="$(mktemp -d "${BATS_TMPDIR:-/tmp}/cc-remote-XXXXXX")"
  printf '9.9.9\n'              > "${remote_dir}/VERSION"
  printf 'echo x\n'             > "${remote_dir}/statusline-command.sh"
  printf '// h\n'               > "${remote_dir}/statusline-helper.js"
  printf '// s\n'               > "${remote_dir}/statusline-subagent.js"
  printf '# template marker\n'  > "${remote_dir}/statusline.conf.example"

  HOME="${TEST_HOME}" STATUSLINE_REPO_RAW="file://${remote_dir}" \
    bash "${STATUSLINE_SCRIPT}" --update >/dev/null 2>&1

  grep -q "template marker" "${TEST_HOME}/.claude/statusline.conf.example"  # refreshed
  grep -q "colour_theme=nord" "${TEST_HOME}/.claude/statusline.conf"        # untouched
  ! grep -q "template marker" "${TEST_HOME}/.claude/statusline.conf"
  rm -rf "${remote_dir}"
}

@test "--update is a no-op when already on the latest version" {
  command -v curl >/dev/null 2>&1 || skip "curl required for file:// fetch"
  skip_if_windows
  remote_dir="$(mktemp -d "${BATS_TMPDIR:-/tmp}/cc-remote-XXXXXX")"
  cp "${TEST_HOME}/.claude/.statusline-version" "${remote_dir}/VERSION"

  output="$(HOME="${TEST_HOME}" STATUSLINE_REPO_RAW="file://${remote_dir}" \
    bash "${STATUSLINE_SCRIPT}" --update 2>&1)"

  [[ "$output" == *"Already up to date"* ]]
  rm -rf "${remote_dir}"
}

@test "--update preserves statusline.conf" {
  command -v curl >/dev/null 2>&1 || skip "curl required for file:// fetch"
  skip_if_windows
  write_conf "colour_theme=nord" "usage_label=clock"
  remote_dir="$(mktemp -d "${BATS_TMPDIR:-/tmp}/cc-remote-XXXXXX")"
  printf '9.9.9\n'            > "${remote_dir}/VERSION"
  printf 'echo x\n'          > "${remote_dir}/statusline-command.sh"
  printf '// h\n'            > "${remote_dir}/statusline-helper.js"
  printf '// s\n'            > "${remote_dir}/statusline-subagent.js"

  HOME="${TEST_HOME}" STATUSLINE_REPO_RAW="file://${remote_dir}" \
    bash "${STATUSLINE_SCRIPT}" --update >/dev/null 2>&1

  grep -q "colour_theme=nord" "${TEST_HOME}/.claude/statusline.conf"
  grep -q "usage_label=clock" "${TEST_HOME}/.claude/statusline.conf"
  rm -rf "${remote_dir}"
}

# ── Opt-in auto-update (v2.12.0) ─────────────────────────────
# STATUSLINE_AUTOUPDATE_SYNC runs the otherwise-detached auto-update inline so
# these assertions are deterministic.

@test "auto_update defaults to false and appears in --dump-config" {
  output="$(HOME="${TEST_HOME}" bash "${STATUSLINE_SCRIPT}" --dump-config 2>/dev/null)"
  [[ "$output" == *"auto_update=false"* ]]
}

@test "auto_update=true installs a pending update" {
  command -v curl >/dev/null 2>&1 || skip "curl required for file:// fetch"
  skip_if_windows
  write_conf "auto_update=true"
  printf '%s %s\n' "$(date +%s)" "9.9.9" > "${TEST_HOME}/.claude/.statusline-update-cache"
  remote_dir="$(mktemp -d "${BATS_TMPDIR:-/tmp}/cc-remote-XXXXXX")"
  printf '9.9.9\n'         > "${remote_dir}/VERSION"
  printf 'echo auto-new\n' > "${remote_dir}/statusline-command.sh"
  printf '// h\n'          > "${remote_dir}/statusline-helper.js"
  printf '// s\n'          > "${remote_dir}/statusline-subagent.js"

  run_statusline_env "$NOTICE_JSON" \
    "STATUSLINE_REPO_RAW=file://${remote_dir}" "STATUSLINE_AUTOUPDATE_SYNC=1"

  [ "$(tr -d '[:space:]' < "${TEST_HOME}/.claude/.statusline-version")" = "9.9.9" ]
  grep -q "auto-new" "${TEST_HOME}/.claude/statusline-command.sh"
  # Cache cleared and lock released afterwards.
  [ ! -f "${TEST_HOME}/.claude/.statusline-update-cache" ]
  [ ! -d "${TEST_HOME}/.claude/.statusline-autoupdate.lock" ]
  rm -rf "${remote_dir}"
}

@test "auto_update=false leaves a pending update alone" {
  command -v curl >/dev/null 2>&1 || skip "curl required for file:// fetch"
  skip_if_windows
  write_conf "auto_update=false"
  printf '%s %s\n' "$(date +%s)" "9.9.9" > "${TEST_HOME}/.claude/.statusline-update-cache"
  remote_dir="$(mktemp -d "${BATS_TMPDIR:-/tmp}/cc-remote-XXXXXX")"
  printf '9.9.9\n'      > "${remote_dir}/VERSION"
  printf 'echo nope\n'  > "${remote_dir}/statusline-command.sh"
  printf '// h\n'       > "${remote_dir}/statusline-helper.js"
  printf '// s\n'       > "${remote_dir}/statusline-subagent.js"
  before="$(tr -d '[:space:]' < "${TEST_HOME}/.claude/.statusline-version")"

  run_statusline_env "$NOTICE_JSON" "STATUSLINE_REPO_RAW=file://${remote_dir}"

  [ "$(tr -d '[:space:]' < "${TEST_HOME}/.claude/.statusline-version")" = "$before" ]
  rm -rf "${remote_dir}"
}

# ── Integrity-verified self-update (G1) ──────────────────────
# Write a SHA256SUMS manifest into a remote dir for the three updater files.
# Skips the calling test if no sha256 tool is available.
write_remote_sha256sums() {
  local dir="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    ( cd "$dir" && sha256sum statusline-command.sh statusline-helper.js statusline-subagent.js > SHA256SUMS )
  elif command -v shasum >/dev/null 2>&1; then
    ( cd "$dir" && shasum -a 256 statusline-command.sh statusline-helper.js statusline-subagent.js > SHA256SUMS )
  else
    skip "no sha256 tool available"
  fi
}

@test "--update verifies a matching SHA256SUMS and installs" {
  command -v curl >/dev/null 2>&1 || skip "curl required for file:// fetch"
  skip_if_windows
  remote_dir="$(mktemp -d "${BATS_TMPDIR:-/tmp}/cc-remote-XXXXXX")"
  printf '9.9.9\n'            > "${remote_dir}/VERSION"
  printf 'echo verified\n'   > "${remote_dir}/statusline-command.sh"
  printf '// h\n'            > "${remote_dir}/statusline-helper.js"
  printf '// s\n'            > "${remote_dir}/statusline-subagent.js"
  write_remote_sha256sums "$remote_dir"

  output="$(HOME="${TEST_HOME}" STATUSLINE_REPO_RAW="file://${remote_dir}" \
    bash "${STATUSLINE_SCRIPT}" --update 2>&1)"

  [[ "$output" == *"Done"* ]]
  [ "$(tr -d '[:space:]' < "${TEST_HOME}/.claude/.statusline-version")" = "9.9.9" ]
  grep -q "verified" "${TEST_HOME}/.claude/statusline-command.sh"
  rm -rf "${remote_dir}"
}

@test "--update aborts and changes nothing when SHA256SUMS does not match" {
  command -v curl >/dev/null 2>&1 || skip "curl required for file:// fetch"
  skip_if_windows
  command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || skip "no sha256 tool"
  before="$(tr -d '[:space:]' < "${TEST_HOME}/.claude/.statusline-version")"
  remote_dir="$(mktemp -d "${BATS_TMPDIR:-/tmp}/cc-remote-XXXXXX")"
  printf '9.9.9\n'           > "${remote_dir}/VERSION"
  printf 'echo tampered\n'   > "${remote_dir}/statusline-command.sh"
  printf '// h\n'           > "${remote_dir}/statusline-helper.js"
  printf '// s\n'           > "${remote_dir}/statusline-subagent.js"
  # A manifest whose hashes do NOT match the served files (tamper simulation).
  cat > "${remote_dir}/SHA256SUMS" <<'EOF'
0000000000000000000000000000000000000000000000000000000000000000  statusline-command.sh
0000000000000000000000000000000000000000000000000000000000000000  statusline-helper.js
0000000000000000000000000000000000000000000000000000000000000000  statusline-subagent.js
EOF

  output="$(HOME="${TEST_HOME}" STATUSLINE_REPO_RAW="file://${remote_dir}" \
    bash "${STATUSLINE_SCRIPT}" --update 2>&1)"

  [[ "$output" == *"checksum verification failed"* ]]
  # Nothing swapped in: version unchanged and the tampered payload not installed.
  [ "$(tr -d '[:space:]' < "${TEST_HOME}/.claude/.statusline-version")" = "$before" ]
  ! grep -q "tampered" "${TEST_HOME}/.claude/statusline-command.sh"
  # No staging files left behind.
  [ -z "$(find "${TEST_HOME}/.claude" -maxdepth 1 -name '*.update.*' 2>/dev/null)" ]
  rm -rf "${remote_dir}"
}

@test "--update still works when the remote has no SHA256SUMS (graceful skip)" {
  command -v curl >/dev/null 2>&1 || skip "curl required for file:// fetch"
  skip_if_windows
  remote_dir="$(mktemp -d "${BATS_TMPDIR:-/tmp}/cc-remote-XXXXXX")"
  printf '9.9.9\n'          > "${remote_dir}/VERSION"
  printf 'echo nosums\n'    > "${remote_dir}/statusline-command.sh"
  printf '// h\n'          > "${remote_dir}/statusline-helper.js"
  printf '// s\n'          > "${remote_dir}/statusline-subagent.js"
  # No SHA256SUMS in the remote — older forks must still be able to update.

  HOME="${TEST_HOME}" STATUSLINE_REPO_RAW="file://${remote_dir}" \
    bash "${STATUSLINE_SCRIPT}" --update >/dev/null 2>&1

  [ "$(tr -d '[:space:]' < "${TEST_HOME}/.claude/.statusline-version")" = "9.9.9" ]
  grep -q "nosums" "${TEST_HOME}/.claude/statusline-command.sh"
  rm -rf "${remote_dir}"
}

# ── Update source can't be repointed by statusline.conf (S2) ──
@test "statusline.conf cannot repoint the auto-update source" {
  command -v curl >/dev/null 2>&1 || skip "curl required for file:// fetch"
  skip_if_windows
  # conf tries to redirect the updater at a bogus (nonexistent) source AND turns
  # on auto_update; the real source comes from the environment. The conf value
  # must be ignored — the update installs from the env source, not the conf one.
  write_conf "auto_update=true" "REPO_RAW=file:///nonexistent-evil-source"
  printf '%s %s\n' "$(date +%s)" "9.9.9" > "${TEST_HOME}/.claude/.statusline-update-cache"
  remote_dir="$(mktemp -d "${BATS_TMPDIR:-/tmp}/cc-remote-XXXXXX")"
  printf '9.9.9\n'           > "${remote_dir}/VERSION"
  printf 'echo from-env\n'   > "${remote_dir}/statusline-command.sh"
  printf '// h\n'           > "${remote_dir}/statusline-helper.js"
  printf '// s\n'           > "${remote_dir}/statusline-subagent.js"

  run_statusline_env "$NOTICE_JSON" \
    "STATUSLINE_REPO_RAW=file://${remote_dir}" "STATUSLINE_AUTOUPDATE_SYNC=1"

  [ "$(tr -d '[:space:]' < "${TEST_HOME}/.claude/.statusline-version")" = "9.9.9" ]
  grep -q "from-env" "${TEST_HOME}/.claude/statusline-command.sh"
  rm -rf "${remote_dir}"
}

@test "auto_update=true does nothing when already current" {
  command -v curl >/dev/null 2>&1 || skip "curl required for file:// fetch"
  skip_if_windows
  write_conf "auto_update=true"
  ver="$(tr -d '[:space:]' < "${TEST_HOME}/.claude/.statusline-version")"
  printf '%s %s\n' "$(date +%s)" "$ver" > "${TEST_HOME}/.claude/.statusline-update-cache"
  remote_dir="$(mktemp -d "${BATS_TMPDIR:-/tmp}/cc-remote-XXXXXX")"
  printf '%s\n' "$ver" > "${remote_dir}/VERSION"

  run_statusline_env "$NOTICE_JSON" \
    "STATUSLINE_REPO_RAW=file://${remote_dir}" "STATUSLINE_AUTOUPDATE_SYNC=1"

  [ "$(tr -d '[:space:]' < "${TEST_HOME}/.claude/.statusline-version")" = "$ver" ]
  rm -rf "${remote_dir}"
}
