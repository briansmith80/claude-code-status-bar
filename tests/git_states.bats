#!/usr/bin/env bats
#
# Git segment states (v2.8.0) — the porcelain-v2 consolidated parser:
# branch name, dirty count, ahead/behind, stash count, detached HEAD.
# Also covers the --benchmark CLI flag added in the same release.

load test_helper

require_git() {
  command -v git > /dev/null 2>&1 || skip "git not available"
}

# Build a repo with an upstream so ahead/behind has data:
#   upstream: two commits; clone resets to commit 1 and adds its own commit
#   -> ahead 1 / behind 1, plus one untracked file and one stash entry
make_diverged_repo() {
  GIT_QUIET=(-c core.fsmonitor=false)
  git "${GIT_QUIET[@]}" init -q -b main "${TEST_HOME}/up"
  git -C "${TEST_HOME}/up" config user.email t@t
  git -C "${TEST_HOME}/up" config user.name t
  echo a > "${TEST_HOME}/up/f.txt"
  git -C "${TEST_HOME}/up" "${GIT_QUIET[@]}" add f.txt
  git -C "${TEST_HOME}/up" "${GIT_QUIET[@]}" commit -qm one
  echo b > "${TEST_HOME}/up/f.txt"
  git -C "${TEST_HOME}/up" "${GIT_QUIET[@]}" commit -qam two
  git "${GIT_QUIET[@]}" clone -q "${TEST_HOME}/up" "${TEST_HOME}/work"
  git -C "${TEST_HOME}/work" config user.email t@t
  git -C "${TEST_HOME}/work" config user.name t
  git -C "${TEST_HOME}/work" "${GIT_QUIET[@]}" reset -q --hard HEAD~1
  echo c > "${TEST_HOME}/work/new.txt"
  git -C "${TEST_HOME}/work" "${GIT_QUIET[@]}" add new.txt
  git -C "${TEST_HOME}/work" "${GIT_QUIET[@]}" commit -qm three
  echo untracked > "${TEST_HOME}/work/d1.txt"
}

repo_json() {
  echo "{\"cwd\":\"${TEST_HOME}/work\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":40},\"total_cost_usd\":0.10}"
}

@test "branch, dirty count, and ahead/behind from one porcelain call" {
  require_git
  make_diverged_repo
  run_statusline "$(repo_json)"
  assert_plain_contains "main"
  assert_plain_contains "1 dirty"
  assert_plain_contains "↑1"
  assert_plain_contains "↓1"
}

@test "stash count comes from the stash reflog" {
  require_git
  make_diverged_repo
  echo stashme > "${TEST_HOME}/work/s.txt"
  git -C "${TEST_HOME}/work" -c core.fsmonitor=false add s.txt
  git -C "${TEST_HOME}/work" -c core.fsmonitor=false stash -q
  run_statusline "$(repo_json)"
  assert_plain_contains "stash:1"
}

@test "detached HEAD shows the short commit hash" {
  require_git
  make_diverged_repo
  git -C "${TEST_HOME}/work" -c core.fsmonitor=false checkout -q --detach HEAD
  head_sha="$(git -C "${TEST_HOME}/work" rev-parse --short=7 HEAD)"
  run_statusline "$(repo_json)"
  assert_plain_contains "$head_sha"
}

@test "clean repo without upstream shows branch and no arrows" {
  require_git
  git -c core.fsmonitor=false init -q -b solo "${TEST_HOME}/solo"
  git -C "${TEST_HOME}/solo" config user.email t@t
  git -C "${TEST_HOME}/solo" config user.name t
  echo x > "${TEST_HOME}/solo/f.txt"
  git -C "${TEST_HOME}/solo" -c core.fsmonitor=false add f.txt
  git -C "${TEST_HOME}/solo" -c core.fsmonitor=false commit -qm init
  run_statusline "{\"cwd\":\"${TEST_HOME}/solo\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":40}}"
  assert_plain_contains "solo"
  assert_plain_not_contains "↑"
  assert_plain_not_contains "↓"
}

@test "--help documents --benchmark" {
  run env HOME="${TEST_HOME}" bash "${STATUSLINE_SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--benchmark"* ]]
}

@test "--benchmark runs or degrades gracefully without GNU date %N" {
  require_git
  output="$(cd "${TEST_HOME}" && HOME="${TEST_HOME}" bash "${STATUSLINE_SCRIPT}" --benchmark 1 2>&1)" || true
  [[ "$output" == *"min "* ]] || [[ "$output" == *"millisecond timing unavailable"* ]] || [[ "$output" == *"needs GNU date"* ]]
}
