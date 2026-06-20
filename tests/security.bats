#!/usr/bin/env bats
#
# Security regression tests for the line-1 render.
#
# S-1: line 1 is printed with `printf '%s'` (never `%b`), and the script's own
#      colours / OSC 8 links carry REAL ESC bytes set at their source. So a
#      field carrying the printable TEXT "\033..." can never be decoded into a
#      live control sequence.
# S-3: model and vim.mode are passed through sanitize() like every other
#      displayed field, so a RAW ESC byte in them is stripped.

load test_helper

# ── S-1: escape *text* is never decoded ───────────────────────────────

@test "S-1: literal \\033 SGR text in model is not decoded (NO_COLOR => zero ESC)" {
  # Under NO_COLOR the script emits no escapes of its own, so ANY real ESC byte
  # in the output could only have come from decoding the untrusted field text.
  run_statusline_env \
    '{"cwd":"/tmp","model":{"display_name":"Opus\033[31mPWNED"},"context_window":{"used_percentage":10}}' \
    NO_COLOR=1 COLUMNS=200
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\x1b'* ]]            # no real ESC byte anywhere
  [[ "$output" == *'\033[31mPWNED'* ]]   # the escape text survives as literal chars
}

@test "S-1: literal OSC window-title injection via cwd is neutralised (NO_COLOR)" {
  run_statusline_env \
    '{"cwd":"/work/\033]0;PWNED\007x","model":{"display_name":"Opus"},"context_window":{"used_percentage":10}}' \
    NO_COLOR=1 COLUMNS=200
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\x1b'* ]]   # no real ESC
  [[ "$output" != *$'\x07'* ]]   # no real BEL (OSC terminator)
}

@test "S-1: OSC title injection in model does not emit a set-title sequence even WITH colours" {
  # Colours are on, so the output legitimately contains real ESC bytes (CLR_*).
  # The injection check is therefore specific: the script never emits OSC ]0;
  # (it only uses OSC ]8; for hyperlinks), so a real ESC]0; could only be decoded.
  run_statusline \
    '{"cwd":"/tmp","model":{"display_name":"Opus\033]0;PWNED\007"},"context_window":{"used_percentage":10}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\x1b'* ]]       # script colours are present (sanity)
  [[ "$output" != *$'\x1b]0;'* ]]    # but no decoded set-window-title sequence
}

# ── S-3: raw ESC bytes are stripped from model / vim.mode ─────────────

@test "S-3: a raw ESC byte in model is stripped by sanitize (NO_COLOR => zero ESC)" {
  local json
  json="$(printf '{"cwd":"/tmp","model":{"display_name":"Op\033[31mus"},"context_window":{"used_percentage":10}}')"
  run_statusline_env "$json" NO_COLOR=1 COLUMNS=200
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\x1b'* ]]           # raw ESC stripped
  assert_plain_contains "Opus"           # the visible text rejoins cleanly
}

@test "S-3: a raw ESC byte in vim.mode is stripped by sanitize (NO_COLOR => zero ESC)" {
  local json
  json="$(printf '{"cwd":"/tmp","model":{"display_name":"Opus"},"vim":{"mode":"NOR\033[5mMAL"},"context_window":{"used_percentage":10}}')"
  run_statusline_env "$json" NO_COLOR=1 COLUMNS=200
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\x1b'* ]]           # raw ESC stripped
  assert_plain_contains "NORMAL"         # the mode label rejoins cleanly
}
