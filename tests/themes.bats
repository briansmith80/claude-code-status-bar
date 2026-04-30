#!/usr/bin/env bats
#
# Theme tests. The script applies one of seven palettes via apply_theme().
# - non-mono themes must emit at least one ANSI CSI sequence (\033[)
# - mono must emit zero CSI sequences
# - NO_COLOR=1 must force mono behaviour regardless of theme

load test_helper

JSON='{"cwd":"/tmp","display_name":"Sonnet","used_percentage":40,"total_cost_usd":0.10}'

# Helper: count ANSI CSI introducer bytes (ESC + [) in $output.
csi_count() {
  # printf '%s' keeps the literal ESC character that the script emits.
  printf '%s' "$output" | LC_ALL=C tr -cd $'\x1b' | wc -c | tr -d ' '
}

@test "default theme emits ANSI escapes" {
  write_conf "colour_theme=default"
  run_statusline "$JSON"
  [ "$status" -eq 0 ]
  [ "$(csi_count)" -gt 0 ]
}

@test "nord theme emits ANSI escapes" {
  write_conf "colour_theme=nord"
  run_statusline "$JSON"
  [ "$status" -eq 0 ]
  [ "$(csi_count)" -gt 0 ]
}

@test "dracula theme emits ANSI escapes" {
  write_conf "colour_theme=dracula"
  run_statusline "$JSON"
  [ "$status" -eq 0 ]
  [ "$(csi_count)" -gt 0 ]
}

@test "solarized theme emits ANSI escapes" {
  write_conf "colour_theme=solarized"
  run_statusline "$JSON"
  [ "$status" -eq 0 ]
  [ "$(csi_count)" -gt 0 ]
}

@test "tokyo-night theme emits ANSI escapes" {
  write_conf "colour_theme=tokyo-night"
  run_statusline "$JSON"
  [ "$status" -eq 0 ]
  [ "$(csi_count)" -gt 0 ]
}

@test "catppuccin theme emits ANSI escapes" {
  write_conf "colour_theme=catppuccin"
  run_statusline "$JSON"
  [ "$status" -eq 0 ]
  [ "$(csi_count)" -gt 0 ]
}

@test "mono theme emits NO ANSI escapes" {
  write_conf "colour_theme=mono"
  run_statusline "$JSON"
  [ "$status" -eq 0 ]
  [ "$(csi_count)" -eq 0 ]
}

@test "NO_COLOR forces mono behaviour" {
  write_conf "colour_theme=dracula"
  run_statusline_env "$JSON" "NO_COLOR=1"
  [ "$status" -eq 0 ]
  [ "$(csi_count)" -eq 0 ]
}
