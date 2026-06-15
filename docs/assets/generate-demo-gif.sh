#!/usr/bin/env bash
# Regenerates docs/assets/hero-demo.gif: an animated demo of the status bar
# progressing through a session, the context bar filling green->red until the
# auto-compact warning (the ▲) fires, with usage and cost ticking up. Every
# frame is the REAL bar output (see capture-demo-frames.sh), so there is no
# screen recording to drift.
#
# Requires: bash, git, node, and a one-time `npm i @resvg/resvg-js gifenc`
# (the rasteriser + GIF encoder) resolvable from docs/assets/.
#   bash docs/assets/generate-demo-gif.sh
#
# Prefer generate-demo-svg.sh for the README: the SVG is crisp, true-colour,
# and needs no npm deps. This GIF is the fallback for contexts that cannot
# render an animated SVG.
set -e

here="$(cd "$(dirname "$0")" && pwd)"
frames="$(mktemp -d "${TMPDIR:-/tmp}/cc-gif-XXXXXX")"
bash "$here/capture-demo-frames.sh" "$frames"
node "$here/generate-demo-gif.js" "$frames" "$here/hero-demo.gif"
rm -rf "$frames"
