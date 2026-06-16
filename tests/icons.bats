#!/usr/bin/env bats
#
# Icon sets (v2.19.0): icon_set=classic (default, the pre-2.19 glyphs) vs
# icon_set=modern (directory ↱, branch ⑂, lines-changed ⇄, duration ⏱; model
# ◆ unchanged), and the use_icons=false override.

load test_helper

require_git() { command -v git > /dev/null 2>&1 || skip "git not available"; }

# A git repo on branch "mybranch" with a cost block, so dir / branch / model /
# duration / lines-changed segments all have data.
make_repo() {
  git -c core.fsmonitor=false init -q -b mybranch "${TEST_HOME}/work"
  git -C "${TEST_HOME}/work" config user.email t@t
  git -C "${TEST_HOME}/work" config user.name t
  echo a > "${TEST_HOME}/work/f.txt"
  git -C "${TEST_HOME}/work" -c core.fsmonitor=false add f.txt
  git -C "${TEST_HOME}/work" -c core.fsmonitor=false commit -qm one
}
repo_json() {
  echo "{\"cwd\":\"${TEST_HOME}/work\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":40},\"cost\":{\"total_cost_usd\":1.25,\"total_duration_ms\":7980000,\"total_lines_added\":10,\"total_lines_removed\":3}}"
}

@test "default icon_set is classic: branch glyph is ↱, not ⑂" {
  require_git; make_repo
  run_statusline_env "$(repo_json)" "COLUMNS=200"
  assert_plain_contains "on ↱ mybranch"
  assert_plain_not_contains "⑂"
}

@test "icon_set=modern swaps the directory and branch glyphs" {
  require_git; make_repo
  write_conf 'icon_set=modern'
  run_statusline_env "$(repo_json)" "COLUMNS=200"
  assert_plain_contains "on ⑂ mybranch"   # branch gets ⑂
  assert_plain_contains "↱ "               # directory gets ↱
  assert_plain_not_contains "↱ mybranch"   # ↱ is no longer the branch icon
}

@test "icon_set=modern adds the lines-changed icon (classic has none)" {
  run_statusline_env '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40},"cost":{"total_cost_usd":1.25,"total_lines_added":10,"total_lines_removed":3}}' "COLUMNS=200"
  assert_plain_not_contains "⇄"
  write_conf 'icon_set=modern'
  run_statusline_env '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40},"cost":{"total_cost_usd":1.25,"total_lines_added":10,"total_lines_removed":3}}' "COLUMNS=200"
  assert_plain_contains "⇄ +10"
}

@test "icon_set=modern fills the duration icon (classic leaves it empty)" {
  run_statusline_env '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40},"cost":{"total_cost_usd":1.25,"total_duration_ms":7980000}}' "COLUMNS=200"
  assert_plain_contains "2h13m"
  assert_plain_not_contains "⏱"
  write_conf 'icon_set=modern'
  run_statusline_env '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40},"cost":{"total_cost_usd":1.25,"total_duration_ms":7980000}}' "COLUMNS=200"
  assert_plain_contains "⏱ 2h13m"
}

@test "model ◆ is present in both icon sets" {
  run_statusline_env '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40}}' "COLUMNS=200"
  assert_plain_contains "◆ Opus"
  write_conf 'icon_set=modern'
  run_statusline_env '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40}}' "COLUMNS=200"
  assert_plain_contains "◆ Opus"
}

@test "use_icons=false drops all icons regardless of icon_set" {
  require_git; make_repo
  write_conf 'icon_set=modern' 'use_icons=false'
  run_statusline_env "$(repo_json)" "COLUMNS=200"
  assert_plain_not_contains "↱"
  assert_plain_not_contains "⑂"
  assert_plain_not_contains "⇄"
  assert_plain_not_contains "⏱"
  assert_plain_not_contains "◆"
}

@test "--dump-config shows icon_set=classic by default" {
  output="$(HOME="${TEST_HOME}" bash "${STATUSLINE_SCRIPT}" --dump-config)"
  [[ "$output" == *"icon_set=classic"* ]]
}
