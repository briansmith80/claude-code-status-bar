#!/usr/bin/env bats
#
# Opt-in styling: gradient progress bars (theme ramp or fixed "heat"), and the
# --demo theme preview. Both off by default.

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

@test "bar_gradient=false gives a single (flat) bar colour" {
  write_conf "colour_theme=tokyo-night" "bar_gradient=false"
  run_statusline_env "$GRAD_JSON" "STATUSLINE_TRUECOLOR=1"
  [ "$status" -eq 0 ]
  [ "$(bar_fill_colours)" -le 1 ]
}

@test "bar_gradient is on by default (gradient without setting it)" {
  write_conf "colour_theme=tokyo-night"   # no bar_gradient line — use the default
  run_statusline_env "$GRAD_JSON" "STATUSLINE_TRUECOLOR=1"
  [ "$status" -eq 0 ]
  [ "$(bar_fill_colours)" -ge 5 ]
}

@test "bar_gradient=heat uses a fixed green->red ramp regardless of theme" {
  write_conf "colour_theme=matrix" "bar_gradient=heat"
  # 100% so the final cell reaches the red stop, on the all-green matrix theme
  run_statusline_env '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":100,"context_window_size":200000}}' "STATUSLINE_TRUECOLOR=1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"38;2;255;65;54"* ]]   # red end — proves it's not the theme ramp
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

@test "--demo renders the full scene (model, usage bars, cost), not a truncated stub" {
  # Regression: demo mode forces no-truncation, so the model, both usage bars,
  # and cost always survive regardless of terminal width.
  output="$(HOME="${TEST_HOME}" bash "${STATUSLINE_SCRIPT}" --demo nord 2>/dev/null)"
  [[ "$output" == *"Opus 4.8 (1M)"* ]]   # model name, with the " context" trimmed
  [[ "$output" == *"5hr ("* ]]           # 5-hour usage bar survived
  [[ "$output" == *"wk ("* ]]            # weekly usage bar survived
  [[ "$output" == *'$0.45'* ]]           # cost survived
  [[ "$output" != *"▲"* ]]               # tokens kept below the auto-compact warning band
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
