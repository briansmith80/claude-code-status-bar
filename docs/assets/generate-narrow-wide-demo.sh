#!/usr/bin/env bash
# Regenerates docs/assets/narrow-wide-demo.svg: the SAME bar rendered at a wide
# and a narrow terminal width, stacked, to show the responsive collapse cascade
# (dir_style=auto + enable_truncation, both on by default: the path collapses to
# its basename, then low-priority segments drop, before metrics are lost).
#
# Runs the real script WITHOUT STATUSLINE_DEMO so the responsive logic is live;
# uses an isolated HOME + throwaway repo and seeds the version so no update
# notice leaks in. Pure node + the local ansi-to-svg.js (no npm deps).
#   bash docs/assets/generate-narrow-wide-demo.sh
set -e

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../../statusline-command.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/cc-nw-XXXXXX")"
export HOME="$work"
claude="$work/.claude"; mkdir -p "$claude"
now="$(date +%s)"
ver="$(tr -d '[:space:]' < "$here/../../VERSION")"
printf '%s\n' "$ver" > "$claude/.statusline-version"
printf '%s %s\n' "$now" "$ver" > "$claude/.statusline-update-cache"

app="$work/projects/acme-web-platform"; mkdir -p "$app"
( cd "$app"
  git init -q .
  git symbolic-ref HEAD refs/heads/feature/signup-form
  git -c user.email=demo@example.com -c user.name=demo commit -q --allow-empty -m init )

json="{\"cwd\":\"$app\",\"workspace\":{\"current_dir\":\"$app\"},\"model\":{\"display_name\":\"Opus 4.8 (1M context)\"},\"context_window\":{\"used_percentage\":71,\"context_window_size\":1000000,\"total_input_tokens\":710000},\"total_cost_usd\":0.42,\"rate_limits\":{\"five_hour\":{\"used_percentage\":37,\"resets_at\":$((now + 8400))},\"seven_day\":{\"used_percentage\":61,\"resets_at\":$((now + 97200))}}}"

wide="$(printf '%s' "$json"   | ( cd "$app" && STATUSLINE_TRUECOLOR=1 COLUMNS=240 bash "$script" 2>/dev/null ) | head -1)"
narrow="$(printf '%s' "$json" | ( cd "$app" && STATUSLINE_TRUECOLOR=1 COLUMNS=72  bash "$script" 2>/dev/null ) | head -1)"

printf '%s\n%s\n' "$wide" "$narrow" | node "$here/themes/ansi-to-svg.js" - "$here/narrow-wide-demo.svg" "responsive width"
echo "wrote $here/narrow-wide-demo.svg"
rm -rf "$work"
