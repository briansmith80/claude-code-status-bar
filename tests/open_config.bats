#!/usr/bin/env bats
#
# Tests for the --open-config flag: opens statusline.conf in an editor,
# seeding it from the example template (or empty) when absent. Tests pin the
# editor via $STATUSLINE_EDITOR=echo so nothing actually launches.

load test_helper

# Run --open-config in the sandbox HOME with a stub editor. Captures $output
# and $status. Pass extra KEY=VAL env vars after the (ignored) first arg.
run_open_config() {
  output="$(STATUSLINE_EDITOR='echo OPENED:' HOME="${TEST_HOME}" \
    bash "${STATUSLINE_SCRIPT}" --open-config 2>&1)"
  # shellcheck disable=SC2034
  status=$?
}

@test "--open-config seeds statusline.conf from the example when absent" {
  printf '# example template\nshow_cost=true\n' \
    > "${TEST_HOME}/.claude/statusline.conf.example"
  [ ! -f "${TEST_HOME}/.claude/statusline.conf" ]

  run_open_config
  [ "$status" -eq 0 ]

  # conf now exists and matches the example
  [ -f "${TEST_HOME}/.claude/statusline.conf" ]
  grep -q "show_cost=true" "${TEST_HOME}/.claude/statusline.conf"
  [[ "$output" == *"from the example template"* ]]
}

@test "--open-config passes the conf path to the editor" {
  printf 'show_cost=true\n' > "${TEST_HOME}/.claude/statusline.conf.example"
  run_open_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"OPENED: ${TEST_HOME}/.claude/statusline.conf"* ]]
}

@test "--open-config does not overwrite an existing conf" {
  printf '# example template\nshow_cost=true\n' \
    > "${TEST_HOME}/.claude/statusline.conf.example"
  printf 'show_cost=false\n' > "${TEST_HOME}/.claude/statusline.conf"

  run_open_config
  [ "$status" -eq 0 ]

  # Untouched: still the user's value, no example content merged in
  run cat "${TEST_HOME}/.claude/statusline.conf"
  [ "$output" = "show_cost=false" ]
}

@test "--open-config creates an empty conf when no example exists" {
  [ ! -f "${TEST_HOME}/.claude/statusline.conf.example" ]
  [ ! -f "${TEST_HOME}/.claude/statusline.conf" ]

  run_open_config
  [ "$status" -eq 0 ]
  [ -f "${TEST_HOME}/.claude/statusline.conf" ]
  [[ "$output" == *"no example template found"* ]]
}

@test "--help lists --open-config" {
  output="$(HOME="${TEST_HOME}" bash "${STATUSLINE_SCRIPT}" --help 2>&1)"
  [[ "$output" == *"--open-config"* ]]
}
