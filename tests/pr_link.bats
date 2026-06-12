#!/usr/bin/env bats
#
# OSC 8 clickable PR links (v2.9.0) — the PR segment wraps in a hyperlink
# to pr.url when pr_link=true (default), with a strict https allowlist.

load test_helper

pr_json() {
  echo "{\"cwd\":\"/tmp\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":40},\"pr\":{\"number\":123,\"url\":\"$1\",\"review_state\":\"approved\"}}"
}

@test "PR segment carries an OSC 8 link to pr.url by default" {
  run_statusline "$(pr_json "https://github.com/o/r/pull/123")"
  [[ "$output" == *$'\x1b]8;;https://github.com/o/r/pull/123\x1b\\'* ]]
  [[ "$output" == *$'\x1b]8;;\x1b\\'* ]]   # close sequence
  assert_plain_contains "PR #123"
}

@test "pr_link=false keeps the plain PR segment" {
  write_conf "pr_link=false"
  run_statusline "$(pr_json "https://github.com/o/r/pull/123")"
  [[ "$output" != *$'\x1b]8'* ]]
  assert_plain_contains "PR #123"
}

@test "non-https and unsafe URLs are rejected, segment stays plain" {
  run_statusline "$(pr_json "http://evil.example/x")"
  [[ "$output" != *$'\x1b]8'* ]]
  assert_plain_contains "PR #123"
  run_statusline "$(pr_json "https://e.com/a b")"
  [[ "$output" != *$'\x1b]8'* ]]
}
