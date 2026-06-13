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
  # The update cache is cleared so the notice clears on the next render.
  [ ! -f "${TEST_HOME}/.claude/.statusline-update-cache" ]
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
