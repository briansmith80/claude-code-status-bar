#!/usr/bin/env bash
# Regenerates the per-theme preview images in this directory (<theme>-demo.svg).
#
#   bash docs/assets/themes/generate-theme-demos.sh
#
# Each preview is the REAL output of `statusline-command.sh --demo <theme>`
# (truecolour forced), captured and converted to SVG by ansi-to-svg.js. The
# scene itself (model, fills, cost, the demo-mode layout overrides) lives in the
# script's --demo branch, so the README previews and what a user sees when they
# run `--demo` are one and the same: there is no second scene to keep in sync,
# and the gradient cells are exactly the bytes the bar prints.
#
# An isolated HOME (so the bar reads pure defaults, not the maintainer's conf)
# and a throwaway git repo named "my-app" give the clean `my-app on main` that
# --demo's basename layout shows, with no dirty/ahead noise.
set -e

here="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$here/../../.." && pwd)"
script="$repo_root/statusline-command.sh"

themes="default nord dracula solarized tokyo-night catppuccin matrix mono"

work="$(mktemp -d "${TMPDIR:-/tmp}/cc-theme-demo-XXXXXX")"
export HOME="$work"          # SCRIPT_DIR=$HOME/.claude -> no conf -> pure defaults
app="$work/my-app"
mkdir -p "$app"
( cd "$app"
  git init -q .
  git symbolic-ref HEAD refs/heads/main
  git -c user.email=demo@example.com -c user.name=demo commit -q --allow-empty -m init )

for t in $themes; do
  # Run --demo from the throwaway repo so its cwd/git drive the scene, force
  # truecolour for the SVG, strip the "── theme ──" header + blank lines, and
  # convert the lone metrics line to SVG.
  ( cd "$app" && STATUSLINE_TRUECOLOR=1 bash "$script" --demo "$t" 2>/dev/null ) \
    | sed -e '/^── /d' -e '/^[[:space:]]*$/d' \
    | node "$here/ansi-to-svg.js" - "$here/$t-demo.svg" "$t"
done

rm -rf "$work"
echo "done"
