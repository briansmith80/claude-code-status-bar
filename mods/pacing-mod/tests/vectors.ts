// Shared pacing vectors, run against the TypeScript maths here (pacing.test.tsx)
// and against the bash functions in statusline-command.sh (tests/pacing_mod.bats
// at the repo root parses this file, one case per line). Keep one case per
// line in exactly this shape.
//
// [resetOffsetSecs, windowSecs, usedPct, expectedPace, expectedForecast]
export const VECTORS: [number, number, number, number, string | null][] = [
  [7200, 18000, 80, 60, '45m'],
  [518400, 604800, 8, 14, null],
  [60, 18000, 50, 100, null],
  [17900, 18000, 10, 1, null],
  [3600, 18000, 100, 80, 'now'],
  [-10, 18000, 50, 100, null],
  [86400, 604800, 95, 86, '7h34m'],
  [90000, 604800, 70, 85, null],
  [200000, 604800, 70, 67, '2d0h'],
  [7200, 18000, 0, 60, null],
]
