#!/usr/bin/env bash
# Captures the demo session as a series of REAL bar frames into the directory
# given as $1 (one NN.ansi file per frame). Shared by generate-demo-gif.sh and
# generate-demo-svg.sh so the scenario (the JSON per frame) lives in one place.
#
# Each frame is the actual statusline-command.sh output, rendered in an isolated
# HOME against a throwaway "my-app on main" repo with STATUSLINE_DEMO=1 (which
# hides dirty/ahead/stash noise and disables truncation), so the frames cannot
# drift from what the tool prints.
#
# Both lines are captured: line 1 (metrics) is driven by the per-frame stdin
# JSON; line 2 (live activity) is REAL helper output. make-demo-transcript.js
# emits a JSONL transcript per frame, statusline-helper.js parses it into the
# per-session activity cache, and the script then renders that cache as line 2.
#   bash capture-demo-frames.sh <frames-dir>
set -e

out="${1:?usage: capture-demo-frames.sh <frames-dir>}"
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$out"

work="$(mktemp -d "${TMPDIR:-/tmp}/cc-demo-XXXXXX")"
export HOME="$work"
script="$here/../../statusline-command.sh"

# The script reads its helper and caches from $HOME/.claude (SCRIPT_DIR), so set
# that up in the isolated HOME: the helper must be present for line 2 to render,
# and the per-session activity cache we pre-build must land there too.
claude="$work/.claude"; mkdir -p "$claude"
helper="$claude/statusline-helper.js"
cp "$here/../../statusline-helper.js" "$helper"

app="$work/my-app"; mkdir -p "$app"
( cd "$app"
  git init -q .
  git symbolic-ref HEAD refs/heads/main
  git -c user.email=demo@example.com -c user.name=demo commit -q --allow-empty -m init )

now="$(date +%s)"

# Seed the version file + a fresh update cache with the current version so the
# demo reads as an up-to-date install: no "↑ update available" notice, and no
# network fetch (the 6h cache is fresh), keeping capture deterministic/offline.
ver="$(tr -d '[:space:]' < "$here/../../VERSION")"
printf '%s\n' "$ver" > "$claude/.statusline-version"
printf '%s %s\n' "$now" "$ver" > "$claude/.statusline-update-cache"

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
  sid="$(printf 'demo%04d' "$i")"
  tr="$work/frame-$i.jsonl"
  cache="$claude/.statusline-activity-cache.${sid}"

  # Build line 2 by parsing this frame's transcript into the per-session cache,
  # exactly as a live session would; the script reads the cache on render.
  node "$here/make-demo-transcript.js" "$i" > "$tr"
  node "$helper" "$tr" "$cache" --colour 2>/dev/null

  json="{\"cwd\":\"$app\",\"workspace\":{\"current_dir\":\"$app\"},\"session_id\":\"$sid\",\"transcript_path\":\"$tr\",\"model\":{\"display_name\":\"Opus 4.8 (1M context)\"},\"context_window\":{\"used_percentage\":$1,\"context_window_size\":1000000,\"total_input_tokens\":$2},\"total_cost_usd\":$5,\"rate_limits\":{\"five_hour\":{\"used_percentage\":$3,\"resets_at\":$((now + 8400))},\"seven_day\":{\"used_percentage\":$4,\"resets_at\":$((now + 97200))}}}"
  printf '%s' "$json" \
    | ( cd "$app" && STATUSLINE_DEMO=1 STATUSLINE_TRUECOLOR=1 COLUMNS=240 bash "$script" 2>/dev/null ) \
    > "$out/$(printf '%02d' "$i").ansi"
  i=$((i + 1))
done

rm -rf "$work"
