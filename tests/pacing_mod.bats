#!/usr/bin/env bats
#
# Parity between the pacing mod (mods/pacing-mod, TypeScript) and the bar
# (statusline-command.sh): the same pacing/forecast vectors must give the same
# answers, and the mod's copy of the theme palettes must match apply_palette.
# The mod's own suite (`claude plugin test mods/pacing-mod`) runs the same
# vectors through the TypeScript side.

load test_helper

MOD="${REPO_ROOT}/mods/pacing-mod"

# Pull the three pure functions out of the script without running it.
load_pacing_fns() {
  eval "$(sed -n '/^iso_to_epoch()/,/^}/p;/^calc_pacing_target()/,/^}/p;/^calc_forecast()/,/^}/p' "$STATUSLINE_SCRIPT")"
}

@test "pacing vectors: bash gives the mod's expected pace and forecast" {
  load_pacing_fns
  NOW_EPOCH=1793700000
  local n=0 off win used pace fc got
  while read -r off win used pace fc; do
    n=$((n + 1))
    calc_pacing_target $((NOW_EPOCH + off)) "$win" || true
    [ "$REPLY" = "$pace" ] || { echo "vector $n ($off $win $used): pace $REPLY, mod expects $pace"; return 1; }
    if calc_forecast $((NOW_EPOCH + off)) "$win" "$used"; then got=$REPLY; else got=null; fi
    [ "$got" = "$fc" ] || { echo "vector $n ($off $win $used): forecast $got, mod expects $fc"; return 1; }
  done < <(sed -n "s/^ *\[\(-*[0-9]*\), *\([0-9]*\), *\([0-9]*\), *\([0-9]*\), *\([^]]*\)\].*/\1 \2 \3 \4 \5/p" "$MOD/tests/vectors.ts" | tr -d "'")
  [ "$n" -ge 8 ]
}

@test "theme palettes: the mod's copy matches apply_palette" {
  local name bash_hex mod_hex
  for name in nord dracula solarized tokyo-night catppuccin matrix; do
    # bash: apply_palette roles 11-18 (bar_ok bar_med bar_high pace ramp0..3)
    bash_hex="$(sed -n "/^    ${name})/,/apply_palette/p" "$STATUSLINE_SCRIPT" \
      | sed -n 's/.*apply_palette //p' | tr -d ';' \
      | awk '{print $11, $12, $13, $14, $15, $16, $17, $18}')"
    mod_hex="$(grep "^  '\{0,1\}${name}'\{0,1\}: named(" "$MOD/hooks/theme.ts" \
      | sed "s/.*named(//; s/).*//; s/[',]//g")"
    [ -n "$bash_hex" ] && [ -n "$mod_hex" ] || { echo "$name: not found in one side"; return 1; }
    [ "$bash_hex" = "$mod_hex" ] || { echo "$name: bash [$bash_hex] mod [$mod_hex]"; return 1; }
  done
}

@test "theme palettes: the default heat ramp matches" {
  local bash_hex mod_hex
  bash_hex="$(sed -n 's/^ *RAMP_HEX="\([0-9a-f][0-9a-f ]*\)".*/\1/p' "$STATUSLINE_SCRIPT" | head -1)"
  mod_hex="$(sed -n "s/^const HEAT = \[\(.*\)\].*/\1/p" "$MOD/hooks/theme.ts" | sed "s/[',#]//g; s/  */ /g")"
  [ -n "$bash_hex" ] && [ "$bash_hex" = "$mod_hex" ] || { echo "bash [$bash_hex] mod [$mod_hex]"; return 1; }
}
