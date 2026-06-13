#!/usr/bin/env bats
#
# Opt-in styling (v2.15.0): gradient progress bars, the --demo theme preview,
# and Nerd Font / Powerline glyphs. All three are off by default.

load test_helper

JSON='{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":78,"context_window_size":200000},"total_cost_usd":1.0,"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":4102444800}}}'
# Context-only payload: exactly one progress bar, so a single-bar colour count
# is unambiguous (no usage bars adding their own colour).
GRAD_JSON='{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":78,"context_window_size":200000}}'

# Count distinct truecolour fills immediately preceding a filled bar cell.
bar_fill_colours() {
  printf '%s' "$output" | grep -oE '38;2;[0-9;]+m█' | sort -u | wc -l | tr -d ' '
}

@test "bar_gradient=true gives a smooth per-cell gradient (not 4 bands)" {
  write_conf "colour_theme=tokyo-night" "bar_gradient=true"
  run_statusline_env "$GRAD_JSON" "STATUSLINE_TRUECOLOR=1"
  [ "$status" -eq 0 ]
  # ~7 filled cells at 78%; interpolation should give well more than the old
  # 4 ramp stops — assert a smooth spread, not banding.
  [ "$(bar_fill_colours)" -ge 5 ]
}

@test "bar_gradient=false (default) uses a single bar colour" {
  write_conf "colour_theme=tokyo-night" "bar_gradient=false"
  run_statusline_env "$GRAD_JSON" "STATUSLINE_TRUECOLOR=1"
  [ "$status" -eq 0 ]
  [ "$(bar_fill_colours)" -le 1 ]
}

@test "--demo <theme> renders that theme and exits 0" {
  output="$(HOME="${TEST_HOME}" bash "${STATUSLINE_SCRIPT}" --demo nord 2>/dev/null)"
  status=$?
  [ "$status" -eq 0 ]
  [[ "$output" == *"── nord ──"* ]]
}

@test "--demo all cycles all eight themes" {
  output="$(HOME="${TEST_HOME}" bash "${STATUSLINE_SCRIPT}" --demo all 2>/dev/null)"
  [ "$(printf '%s' "$output" | grep -c '^── ')" -eq 8 ]
}

@test "env STATUSLINE_THEME overrides the conf colour_theme" {
  write_conf "colour_theme=nord"
  run_statusline_env "$JSON" "STATUSLINE_TRUECOLOR=1" "STATUSLINE_THEME=matrix"
  [ "$status" -eq 0 ]
  [[ "$output" == *"38;2;0;255;65"* ]]   # matrix dir, not nord
}

@test "a STATUSLINE_THEME line in the conf is a no-op (env-only knob)" {
  # A conf STATUSLINE_THEME must NOT clobber a real env override (the --demo bug).
  write_conf "colour_theme=dracula" "STATUSLINE_THEME=mono"
  run_statusline_env "$JSON" "STATUSLINE_TRUECOLOR=1" "STATUSLINE_THEME=matrix"
  [ "$status" -eq 0 ]
  [[ "$output" == *"38;2;0;255;65"* ]]   # env matrix wins over both conf lines
}

@test "nerd_font=true swaps the Unicode segment icons for glyphs" {
  write_conf "nerd_font=true"
  run_statusline "$JSON"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\xe2\x97\x86'* ]]   # no ◆ (U+25C6) model icon
  [[ "$output" == *$'\xef\x8b\x9b'* ]]   # has U+F2DB chip glyph
}

@test "nerd_font=false (default) keeps the Unicode segment icons" {
  write_conf "nerd_font=false"
  run_statusline "$JSON"
  [[ "$output" == *$'\xe2\x97\x86'* ]]   # has ◆
}

@test "powerline=true inserts the arrow separator glyph" {
  write_conf "powerline=true"
  run_statusline "$JSON"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\xee\x82\xb0'* ]]   # U+E0B0 powerline arrow
}

@test "powerline=false (default) uses plain spacing" {
  write_conf "powerline=false"
  run_statusline "$JSON"
  [[ "$output" != *$'\xee\x82\xb0'* ]]
}
