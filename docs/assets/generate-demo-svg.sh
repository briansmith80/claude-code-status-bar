#!/usr/bin/env bash
# Regenerates docs/assets/hero-demo.svg: a crisp, true-colour, dependency-free
# animated demo of the status bar progressing through a session (context bar
# filling green->red until the auto-compact warning fires, usage and cost
# ticking up). Every frame is the REAL bar output (see capture-demo-frames.sh),
# so there is no screen recording to drift.
#
# Unlike the GIF this needs only bash, git, and node (no npm deps). The SVG
# animates on GitHub when referenced via <img> (SMIL, no JavaScript).
#   bash docs/assets/generate-demo-svg.sh
set -e

here="$(cd "$(dirname "$0")" && pwd)"
frames="$(mktemp -d "${TMPDIR:-/tmp}/cc-svg-XXXXXX")"
bash "$here/capture-demo-frames.sh" "$frames"
node "$here/generate-demo-svg.js" "$frames" "$here/hero-demo.svg"
rm -rf "$frames"
