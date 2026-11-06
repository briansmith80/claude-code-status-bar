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

@test "a result hours old is still shown (no git in the render), then refreshed" {
  require_git
  make_repo
  run_statusline "$(repo_json)"
  echo u > "${TEST_HOME}/work/u2.txt"
  age_git_cache 7200
  f="$(git_cache_file)"
  printf '%s\n' "$(date +%s)" > "${f}.lock"   # hold the folder so no refresh job starts
  install_git_trap
  run_statusline_env "$(repo_json)" "PATH=${TEST_HOME}/trap:${PATH}"
  assert_plain_contains "1 dirty"        # old result shown, no git in the render
  [ ! -f "${TEST_HOME}/git-calls.log" ]
  rm -f "${f}.lock"
  run_statusline "$(repo_json)"          # now a detached job (real git) refreshes it
  assert_plain_contains "1 dirty"
  wait_for_file_gone "${f}.lock"
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

# ── Audit follow-ups: claims, collisions, uninstall ──────────

@test "a claim stamped in the future (clock stepped back) counts as expired" {
  mkdir -p "${TEST_HOME}/trap"
  printf '#!/bin/bash\necho x >> "%s/curl-calls.log"\nexit 7\n' "${TEST_HOME}" > "${TEST_HOME}/trap/curl"
  chmod +x "${TEST_HOME}/trap/curl"
  write_conf "show_claude_status=true" "claude_status_cache_seconds=1"
  printf '%s\n' "$(( $(date +%s) + 3600 ))" > "${TEST_HOME}/.claude/.statusline-claude-status-cache.lock"
  json='{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40}}'
  run_statusline_env "$json" "PATH=${TEST_HOME}/trap:${PATH}"
  sleep 1
  [ "$(wc -l < "${TEST_HOME}/curl-calls.log")" -eq 1 ]
}

@test "the update check is throttled by its claim file too" {
  mkdir -p "${TEST_HOME}/trap"
  printf '#!/bin/bash\necho x >> "%s/curl-calls.log"\nexit 7\n' "${TEST_HOME}" > "${TEST_HOME}/trap/curl"
  chmod +x "${TEST_HOME}/trap/curl"
  # test_helper pins a fresh update cache; age it past the 6-hour interval
  printf '%s 0.0.1\n' "$(( $(date +%s) - 30000 ))" > "${TEST_HOME}/.claude/.statusline-update-cache"
  printf '%s\n' "$(date +%s)" > "${TEST_HOME}/.claude/.statusline-update-cache.lock"
  json='{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40}}'
  run_statusline_env "$json" "PATH=${TEST_HOME}/trap:${PATH}"
  sleep 1
  [ ! -f "${TEST_HOME}/curl-calls.log" ]
  rm -f "${TEST_HOME}/.claude/.statusline-update-cache.lock"
  run_statusline_env "$json" "PATH=${TEST_HOME}/trap:${PATH}"
  sleep 1
  [ "$(wc -l < "${TEST_HOME}/curl-calls.log")" -eq 1 ]
}

@test "a cached result for another folder (hash collision) is ignored" {
  require_git
  make_repo
  run_statusline "$(repo_json)"
  f="$(git_cache_file)"
  awk 'NR==3{$0="/some/other/folder"}1' "$f" > "${f}.new" && mv -f "${f}.new" "$f"
  install_git_trap
  run_statusline_env "$(repo_json)" "PATH=${TEST_HOME}/trap:${PATH}"
  [ -f "${TEST_HOME}/git-calls.log" ]
}

@test "a result over 5 min old is still shown while another render refreshes the folder" {
  require_git
  make_repo
  run_statusline "$(repo_json)"
  age_git_cache 301
  f="$(git_cache_file)"
  printf '%s\n' "$(date +%s)" > "${f}.lock"
  install_git_trap
  run_statusline_env "$(repo_json)" "PATH=${TEST_HOME}/trap:${PATH}"
  assert_plain_contains "main"
  [ ! -f "${TEST_HOME}/git-calls.log" ]
}

@test "--uninstall removes git caches, claim files, the conf template and the auto-update lock dir" {
  d="${TEST_HOME}/.claude"
  cp "${REPO_ROOT}/statusline.conf.example" "$d/statusline.conf.example"
  : > "$d/.statusline-git-cache.deadbeef"; : > "$d/.statusline-git-cache.deadbeef.lock"
  : > "$d/.statusline-update-cache.lock"; : > "$d/.statusline-activity-cache.abcd1234"
  mkdir -p "$d/.statusline-autoupdate.lock"
  run bash -c "printf 'y\nn\n' | HOME='${TEST_HOME}' bash '${STATUSLINE_SCRIPT}' --uninstall"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed installed files"* ]]
  [ ! -e "$d/statusline.conf.example" ]
  [ ! -e "$d/.statusline-git-cache.deadbeef" ]
  [ ! -e "$d/.statusline-git-cache.deadbeef.lock" ]
  [ ! -e "$d/.statusline-update-cache.lock" ]
  [ ! -e "$d/.statusline-activity-cache.abcd1234" ]
  [ ! -e "$d/.statusline-autoupdate.lock" ]
}

# ── v2.27.0: the cold probe runs detached too; jobs start in one spawn ──

require_node() { command -v node > /dev/null 2>&1 || skip "node not available"; }

# A git that sleeps before handing over to the real one, so a cold probe
# outlasts the render's wait.
install_slow_git() {
  local real; real="$(command -v git)"
  mkdir -p "${TEST_HOME}/slow"
  printf '#!/bin/bash\nsleep %s\nexec "%s" "$@"\n' "$1" "$real" > "${TEST_HOME}/slow/git"
  chmod +x "${TEST_HOME}/slow/git"
}

@test "a cold probe slower than the wait does not block the render; its result shows next render" {
  require_git
  make_repo
  install_slow_git 3
  start=$(date +%s)
  run_statusline_env "$(repo_json)" "PATH=${TEST_HOME}/slow:${PATH}" "STATUSLINE_GIT_COLD_WAIT_TICKS=5"
  [ $(( $(date +%s) - start )) -lt 3 ]     # rendered before the probe finished
  assert_plain_not_contains "main"         # no git result yet
  assert_plain_contains "Opus"
  f="${TEST_HOME}/.claude/.statusline-git-cache."
  for i in $(seq 1 100); do git_cache_file > /dev/null 2>&1 && break; sleep 0.1; done
  wait_for_file_gone "$(git_cache_file).lock"
  run_statusline "$(repo_json)"            # the detached probe finished meanwhile
  assert_plain_contains "main"
  assert_plain_contains "1 dirty"
}

@test "a cold render whose folder another render holds starts no second git and shows its result" {
  require_git
  make_repo
  # Work out the folder's cache name with one real render, then start cold again.
  run_statusline "$(repo_json)"
  f="$(git_cache_file)"
  rm -f "$f"
  printf '%s held\n' "$(date +%s)" > "${f}.lock"   # another render's probe is running
  install_git_trap
  run_statusline_env "$(repo_json)" "PATH=${TEST_HOME}/trap:${PATH}" "STATUSLINE_GIT_COLD_WAIT_TICKS=3"
  [ ! -f "${TEST_HOME}/git-calls.log" ]    # waited; ran no git of its own
  assert_plain_not_contains "main"
  rm -f "${f}.lock"
  run_statusline "$(repo_json)"
  assert_plain_contains "main"
}

@test "git refresh and the activity helper due in the same render both run (one spawn)" {
  require_git
  require_node
  make_repo
  cp "${REPO_ROOT}/statusline-helper.js" "${TEST_HOME}/.claude/statusline-helper.js"
  run_statusline "$(repo_json)"
  echo u > "${TEST_HOME}/work/u2.txt"
  age_git_cache 10
  tr_file="${TEST_HOME}/t.jsonl"
  printf '{"timestamp":"%s","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"npm test"}}]}}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" > "$tr_file"
  json="{\"cwd\":\"${TEST_HOME}/work\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":40},\"transcript_path\":\"${tr_file}\",\"session_id\":\"onespawn\"}"
  run_statusline "$json"
  assert_plain_contains "1 dirty"          # stale result shown at once
  f="$(git_cache_file)"
  wait_for_file_gone "${f}.lock"
  wait_for_file_gone "${TEST_HOME}/.claude/.statusline-activity-cache.onespawn.lock"
  run_statusline "$json"
  assert_plain_contains "2 dirty"          # the git job ran
  assert_plain_contains "Bash npm test"    # and so did the helper
}
