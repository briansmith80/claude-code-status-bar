#!/usr/bin/env bash
# Regenerates docs/assets/hero-demo.gif: an animated demo of the status bar
# progressing through a session, the context bar filling green->red until the
# auto-compact warning (the ▲) fires, with usage and cost ticking up. Every
# frame is the REAL bar output, so there is no screen recording to drift.
#
# Requires: bash, git, node, and a one-time `npm i @resvg/resvg-js gifenc`
# (the rasteriser + GIF encoder) resolvable from docs/assets/.
#   bash docs/assets/generate-demo-gif.sh
set -e

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../../statusline-command.sh"

# Isolated HOME (pure defaults) + a throwaway repo so the scene reads
# "my-app on main" with no dirty/ahead noise (STATUSLINE_DEMO=1 hides git state).
work="$(mktemp -d "${TMPDIR:-/tmp}/cc-gif-XXXXXX")"
export HOME="$work"
app="$work/my-app"; mkdir -p "$app"
( cd "$app"
  git init -q .
  git symbolic-ref HEAD refs/heads/main
  git -c user.email=demo@example.com -c user.name=demo commit -q --allow-empty -m init )

now="$(date +%s)"
frames="$work/frames"; mkdir -p "$frames"

# One line per frame: context% tokens 5h% weekly% cost
set -- "12 120000 8 20 0.03" \
       "31 310000 14 22 0.09" \
       "52 520000 22 25 0.18" \
       "71 710000 30 28 0.29" \
       "86 860000 37 30 0.39" \
       "95 950000 44 33 0.48"

i=0
for spec in "$@"; do
  set -- $spec
  json="{\"cwd\":\"$app\",\"workspace\":{\"current_dir\":\"$app\"},\"model\":{\"display_name\":\"Opus 4.8 (1M context)\"},\"context_window\":{\"used_percentage\":$1,\"context_window_size\":1000000,\"total_input_tokens\":$2},\"total_cost_usd\":$5,\"rate_limits\":{\"five_hour\":{\"used_percentage\":$3,\"resets_at\":$((now + 8400))},\"seven_day\":{\"used_percentage\":$4,\"resets_at\":$((now + 97200))}}}"
  printf '%s' "$json" \
    | ( cd "$app" && STATUSLINE_DEMO=1 STATUSLINE_TRUECOLOR=1 COLUMNS=240 bash "$script" 2>/dev/null ) \
    > "$frames/$(printf '%02d' "$i").ansi"
  i=$((i + 1))
done

node "$here/generate-demo-gif.js" "$frames" "$here/hero-demo.gif"
rm -rf "$work"
