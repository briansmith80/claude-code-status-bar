#!/usr/bin/env bash
# Regenerates docs/assets/line2-activity-loop.svg: an animated SVG of just the
# LIVE ACTIVITY line (line 2), flip-booking through the same six real frames the
# hero demo uses, so the Live activity section can show the second line moving on
# its own. Reuses capture-demo-frames.sh; pure node + the local ansi-to-svg.js
# (no npm deps).
#   bash docs/assets/generate-line2-demo.sh
set -e

here="$(cd "$(dirname "$0")" && pwd)"
frames="$(mktemp -d "${TMPDIR:-/tmp}/cc-l2-XXXXXX")"
bash "$here/capture-demo-frames.sh" "$frames"

node -e '
const fs = require("fs"), path = require("path");
const { toAnimatedSvg } = require(path.join(process.argv[1], "themes", "ansi-to-svg.js"));
const dir = process.argv[2], out = process.argv[3];
const line2 = fs.readdirSync(dir).filter(f => f.endsWith(".ansi")).sort().map(f => {
  const lines = fs.readFileSync(path.join(dir, f), "utf8").replace(/\r\n/g, "\n").split("\n");
  return lines[1] || "";            // raw line-2 ANSI
}).filter(s => s.trim());
fs.writeFileSync(out, toAnimatedSvg(line2, { label: "live activity line" }));
console.log("wrote", out, line2.length + " frames");
' "$here" "$frames" "$here/line2-activity-loop.svg"

rm -rf "$frames"
