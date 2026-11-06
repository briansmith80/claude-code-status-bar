#!/usr/bin/env bats
#
# Git result cache + detached background work (v2.25.0).
#
# Claude Code cancels an in-flight render with a tree kill when the next one
# starts. On Windows (MSYS2) that could strand native children (git, curl,
# node) suspended forever. The fix keeps git out of the render (a per-folder
# cache refreshed by detached jobs) and caps how often background fetches run
# (claim files). These tests pin the observable behaviour on every platform.

load test_helper

require_git() { command -v git > /dev/null 2>&1 || skip "git not available"; }

make_repo() {
  git -c core.fsmonitor=false init -q -b main "${TEST_HOME}/work"
  git -C "${TEST_HOME}/work" config user.email t@t
  git -C "${TEST_HOME}/work" config user.name t
  echo a > "${TEST_HOME}/work/f.txt"
  git -C "${TEST_HOME}/work" -c core.fsmonitor=false add f.txt
  git -C "${TEST_HOME}/work" -c core.fsmonitor=false commit -qm one
  echo u > "${TEST_HOME}/work/u1.txt"   # one untracked file -> "1 dirty"
}

repo_json() {
  echo "{\"cwd\":\"${TEST_HOME}/work\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":40}}"
}

# A git that logs each call and fails, so a render that runs git is visible.
install_git_trap() {
  mkdir -p "${TEST_HOME}/trap"
  printf '#!/bin/bash\necho "$*" >> "%s/git-calls.log"\nexit 1\n' "${TEST_HOME}" > "${TEST_HOME}/trap/git"
  chmod +x "${TEST_HOME}/trap/git"
}

git_cache_file() {
  local f
  for f in "${TEST_HOME}/.claude"/.statusline-git-cache.*; do
    case "$f" in *.lock|*.tmp.*) continue ;; esac
    [ -f "$f" ] && { echo "$f"; return 0; }
  done
  return 1
}

# Rewrite the cached result's timestamp to N seconds ago.
age_git_cache() {
  local f; f="$(git_cache_file)"
  local rest; rest="$(tail -n +2 "$f")"
  printf '%s\n%s\n' "$(( $(date +%s) - $1 ))" "$rest" > "$f"
}

wait_for_file_gone() {
  local i
  for i in $(seq 1 100); do [ -e "$1" ] || return 0; sleep 0.1; done
  return 1
}

@test "first render runs git and writes the folder's cache" {
  require_git
  make_repo
  run_statusline "$(repo_json)"
  assert_plain_contains "main"
  assert_plain_contains "1 dirty"
  f="$(git_cache_file)"
  [ "$(tail -n 1 "$f")" = "end" ]
}

@test "a fresh cached result is reused: the render runs no git" {
  require_git
  make_repo
  # A wide window so a slow CI runner can't age the cache between renders.
  write_conf "git_cache_seconds=60"
  run_statusline "$(repo_json)"
  install_git_trap
  run_statusline_env "$(repo_json)" "PATH=${TEST_HOME}/trap:${PATH}"
  assert_plain_contains "main"
  assert_plain_contains "1 dirty"
  [ ! -f "${TEST_HOME}/git-calls.log" ]
}

@test "a stale result is still shown, then refreshed in the background" {
  require_git
  make_repo
  run_statusline "$(repo_json)"
  echo u > "${TEST_HOME}/work/u2.txt"    # now 2 dirty
  age_git_cache 10
  run_statusline "$(repo_json)"
  assert_plain_contains "1 dirty"        # stale result shown, no wait on git
  f="$(git_cache_file)"
  wait_for_file_gone "${f}.lock"         # the detached job frees its lock when done
  run_statusline "$(repo_json)"
  assert_plain_contains "2 dirty"
}

@test "a result over five minutes old is not shown: the render runs git" {
  require_git
  make_repo
  run_statusline "$(repo_json)"
  echo u > "${TEST_HOME}/work/u2.txt"
  age_git_cache 400
  run_statusline "$(repo_json)"
  assert_plain_contains "2 dirty"
}

@test "a refresh already in flight is not started twice" {
  require_git
  make_repo
  run_statusline "$(repo_json)"
  age_git_cache 10
  f="$(git_cache_file)"
  printf '%s\n' "$(date +%s)" > "${f}.lock"   # another render holds the folder
  install_git_trap
  run_statusline_env "$(repo_json)" "PATH=${TEST_HOME}/trap:${PATH}"
  sleep 1
  assert_plain_contains "main"
  [ ! -f "${TEST_HOME}/git-calls.log" ]
}

@test "git_cache_seconds=0 runs git on every render and writes no cache" {
  require_git
  make_repo
  write_conf "git_cache_seconds=0"
  run_statusline "$(repo_json)"
  assert_plain_contains "1 dirty"
  echo u > "${TEST_HOME}/work/u2.txt"
  run_statusline "$(repo_json)"
  assert_plain_contains "2 dirty"
  run git_cache_file
  [ "$status" -ne 0 ]
}

@test "a cached result is ignored after a git setting changes" {
  require_git
  make_repo
  run_statusline "$(repo_json)"
  assert_plain_contains "1 dirty"
  write_conf "git_untracked=false"
  run_statusline "$(repo_json)"
  assert_plain_not_contains "dirty"
}

@test "a folder that is not a repo is cached too (no git per render)" {
  mkdir -p "${TEST_HOME}/plain"
  json="{\"cwd\":\"${TEST_HOME}/plain\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":40}}"
  write_conf "git_cache_seconds=60"
  run_statusline "$json"
  install_git_trap
  run_statusline_env "$json" "PATH=${TEST_HOME}/trap:${PATH}"
  [ "$status" -eq 0 ]
  [ ! -f "${TEST_HOME}/git-calls.log" ]
}

@test "--dump-config shows git_cache_seconds (default 5) and the git knobs" {
  run env HOME="${TEST_HOME}" bash "${STATUSLINE_SCRIPT}" --dump-config
  [ "$status" -eq 0 ]
  [[ "$output" == *"git_cache_seconds=5"* ]]
  [[ "$output" == *"git_timeout=0"* ]]
  [[ "$output" == *"git_untracked=true"* ]]
}

# ── Background fetch claims ───────────────────────────────────

@test "a failing Claude-status fetch is tried once per 30s, not every render" {
  mkdir -p "${TEST_HOME}/trap"
  printf '#!/bin/bash\necho x >> "%s/curl-calls.log"\nexit 7\n' "${TEST_HOME}" > "${TEST_HOME}/trap/curl"
  chmod +x "${TEST_HOME}/trap/curl"
  write_conf "show_claude_status=true" "claude_status_cache_seconds=1"
  json='{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40}}'
  for _ in 1 2 3; do
    run_statusline_env "$json" "PATH=${TEST_HOME}/trap:${PATH}"
  done
  sleep 1
  [ "$(wc -l < "${TEST_HOME}/curl-calls.log")" -eq 1 ]
  [ -f "${TEST_HOME}/.claude/.statusline-claude-status-cache.lock" ]
}

@test "the fetch claim expires, so the next attempt happens after the gap" {
  mkdir -p "${TEST_HOME}/trap"
  printf '#!/bin/bash\necho x >> "%s/curl-calls.log"\nexit 7\n' "${TEST_HOME}" > "${TEST_HOME}/trap/curl"
  chmod +x "${TEST_HOME}/trap/curl"
  write_conf "show_claude_status=true" "claude_status_cache_seconds=1"
  printf '%s\n' "$(( $(date +%s) - 31 ))" > "${TEST_HOME}/.claude/.statusline-claude-status-cache.lock"
  json='{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40}}'
  run_statusline_env "$json" "PATH=${TEST_HOME}/trap:${PATH}"
  sleep 1
  [ "$(wc -l < "${TEST_HOME}/curl-calls.log")" -eq 1 ]
}

# ── Activity helper: one run per session at a time ───────────

@test "the activity helper is not spawned while a run is in flight" {
  command -v node > /dev/null 2>&1 || skip "node not available"
  cp "${REPO_ROOT}/statusline-helper.js" "${TEST_HOME}/.claude/statusline-helper.js"
  cache="${TEST_HOME}/.claude/.statusline-activity-cache"
  printf '%s {"activity":"IN_FLIGHT","next":0}\n' "$(date +%s)" > "$cache"
  printf '%s\n' "$(date +%s)" > "${cache}.lock"   # a helper run holds the session
  tr_file="${TEST_HOME}/t.jsonl"; printf '{"x":1}\n' > "$tr_file"   # transcript changed
  run_statusline "{\"cwd\":\"/tmp\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":40},\"transcript_path\":\"${tr_file}\"}"
  assert_plain_contains "IN_FLIGHT"
  [ ! -f "${cache}.seen" ]                         # not spawned: the next render re-checks
}

@test "a stale helper lock (hung run) does not block the helper" {
  command -v node > /dev/null 2>&1 || skip "node not available"
  cp "${REPO_ROOT}/statusline-helper.js" "${TEST_HOME}/.claude/statusline-helper.js"
  cache="${TEST_HOME}/.claude/.statusline-activity-cache"
  printf '%s\n' "$(( $(date +%s) - 60 ))" > "${cache}.lock"
  tr_file="${TEST_HOME}/t.jsonl"; printf '{"x":1}\n' > "$tr_file"
  run_statusline "{\"cwd\":\"/tmp\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":40},\"transcript_path\":\"${tr_file}\"}"
  [ -f "${cache}.seen" ]                           # spawned
  wait_for_file_gone "${cache}.lock"               # and the job freed the lock
}
