#!/usr/bin/env bash
# Captures the demo session as a series of REAL bar frames into the directory
# given as $1 (one NN.ansi file per frame). Shared by generate-demo-gif.sh and
# generate-demo-svg.sh so the scenario (the JSON per frame) lives in one place.
#
# Each frame is the actual statusline-command.sh output, rendered in an isolated
# HOME against a throwaway "my-app on main" repo with STATUSLINE_DEMO=1 (which
# hides dirty/ahead/stash noise and disables truncation), so the frames cannot
# drift from what the tool prints.
#   bash capture-demo-frames.sh <frames-dir>
set -e

out="${1:?usage: capture-demo-frames.sh <frames-dir>}"
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../../statusline-command.sh"
mkdir -p "$out"

work="$(mktemp -d "${TMPDIR:-/tmp}/cc-demo-XXXXXX")"
export HOME="$work"
app="$work/my-app"; mkdir -p "$app"
( cd "$app"
  git init -q .
  git symbolic-ref HEAD refs/heads/main
  git -c user.email=demo@example.com -c user.name=demo commit -q --allow-empty -m init )

now="$(date +%s)"

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
    > "$out/$(printf '%02d' "$i").ansi"
  i=$((i + 1))
done

rm -rf "$work"
