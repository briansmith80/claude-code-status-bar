# Shared helpers for the Claude Code status bar BATS suite.
#
# Goals:
#   - Run statusline-command.sh in a sandboxed HOME so the developer's real
#     ~/.claude/statusline.conf and credentials never leak into tests.
#   - Provide a `run_statusline` helper that pipes JSON to the script.
#   - Provide a `strip_ansi` helper so assertions can match plain text.
#
# Tests are expected to be run from the repo root: `bats tests/`.

# Resolve repo root (parent of tests/) once.
REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
STATUSLINE_SCRIPT="${REPO_ROOT}/statusline-command.sh"

# Per-test sandbox HOME. Each test gets a fresh dir under $BATS_TMPDIR so
# - the developer's real ~/.claude/statusline.conf can never leak in
# - tests can drop their own statusline.conf without affecting siblings
setup() {
  TEST_HOME="$(mktemp -d "${BATS_TMPDIR:-/tmp}/cc-statusline-XXXXXX")"
  mkdir -p "${TEST_HOME}/.claude"

  # Pin VERSION inside the sandbox to the repo's VERSION (or "test" fallback)
  # and pre-populate the update cache with the same string. This prevents the
  # script from showing "update available" or hitting the network.
  local pinned_version="test"
  if [ -f "${REPO_ROOT}/VERSION" ]; then
    pinned_version="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"
  fi
  printf '%s\n' "${pinned_version}" > "${TEST_HOME}/.claude/.statusline-version"
  printf '%s %s\n' "$(date +%s)" "${pinned_version}" \
    > "${TEST_HOME}/.claude/.statusline-update-cache"

  # NO_COLOR is honoured by the script as a "mono" trigger. Make sure we don't
  # accidentally inherit it from the host environment for the colour tests.
  unset NO_COLOR
}

teardown() {
  if [ -n "${TEST_HOME:-}" ] && [ -d "${TEST_HOME}" ]; then
    rm -rf "${TEST_HOME}"
  fi
}

# Pipe a JSON blob to the statusline script under the sandbox HOME.
# Captures stdout in $output and exit status in $status (BATS conventions).
#
# Usage: run_statusline '<json>'
run_statusline() {
  local json="$1"
  # We intentionally don't use BATS' built-in `run` here because we need
  # to set HOME and feed stdin. Callers expecting `run`-style $output and
  # $status will get them via this manual capture.
  output="$(printf '%s' "$json" | HOME="${TEST_HOME}" bash "${STATUSLINE_SCRIPT}" 2>/dev/null)"
  # shellcheck disable=SC2034  # consumed by the .bats tests, not this file
  status=$?
}

# Same as run_statusline but lets the caller add extra `KEY=VAL` env vars.
# Usage: run_statusline_env '<json>' "VAR1=foo" "VAR2=bar"
run_statusline_env() {
  local json="$1"; shift
  output="$(printf '%s' "$json" | env "$@" HOME="${TEST_HOME}" bash "${STATUSLINE_SCRIPT}" 2>/dev/null)"
  # shellcheck disable=SC2034  # consumed by the .bats tests, not this file
  status=$?
}

# Strip ANSI escape sequences (CSI, OSC) from input.
# Reads from $1 if given, else from stdin.
strip_ansi() {
  if [ $# -gt 0 ]; then
    printf '%s' "$1" | sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/\x1b\][^\x07]*\x07//g'
  else
    sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/\x1b\][^\x07]*\x07//g'
  fi
}

# Write a statusline.conf inside the sandbox. Subsequent run_statusline calls
# in the same test will pick it up. Pass key=value lines as args.
#
# Usage: write_conf "show_cost=false" "bar_width=20"
write_conf() {
  local conf="${TEST_HOME}/.claude/statusline.conf"
  : > "$conf"
  local line
  for line in "$@"; do
    printf '%s\n' "$line" >> "$conf"
  done
}

# Convenience: assert $output (after stripping ANSI) contains a substring.
assert_plain_contains() {
  local needle="$1"
  local plain
  plain="$(strip_ansi "$output")"
  if [[ "$plain" != *"$needle"* ]]; then
    printf 'expected plain output to contain: %s\nactual: %s\n' "$needle" "$plain" >&2
    return 1
  fi
}

# Convenience: assert $output (after stripping ANSI) does NOT contain a string.
assert_plain_not_contains() {
  local needle="$1"
  local plain
  plain="$(strip_ansi "$output")"
  if [[ "$plain" == *"$needle"* ]]; then
    printf 'expected plain output NOT to contain: %s\nactual: %s\n' "$needle" "$plain" >&2
    return 1
  fi
}
