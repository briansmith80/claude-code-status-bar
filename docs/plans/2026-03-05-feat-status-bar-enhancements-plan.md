---
title: "feat: Status Bar Enhancements — New Segments, Visuals, and Layout Intelligence"
type: feat
status: completed
date: 2026-03-05
origin: docs/brainstorms/2026-03-05-status-bar-enhancements-brainstorm.md
---

# feat: Status Bar Enhancements

## Overview

Comprehensive enhancement of the Claude Code status bar across 7 phases: conditional visibility, new git segments (ahead/behind + stash), context intelligence (warnings + cost rate), icon mode, colour themes, priority truncation, and segment grouping. All changes are incremental, backward compatible, and delivered to the existing single-file bash architecture.

## Problem Statement / Motivation

The status bar currently shows useful data but lacks:
- Git workflow context (am I ahead/behind remote? do I have stashes?)
- Proactive warnings when context window is running low
- Cost efficiency awareness (burn rate)
- Visual customisation (icons, themes)
- Smart layout (auto-hide empty segments, truncate on narrow terminals, group related info)

Users have requested more actionable information and better visual presentation. (see brainstorm: docs/brainstorms/2026-03-05-status-bar-enhancements-brainstorm.md)

## Proposed Solution

7 phases, each adding a self-contained feature with its own config toggles. Every phase must maintain backward compatibility — existing `statusline.conf` files continue to work, and default behavior preserves the current experience except where explicitly decided otherwise (icons default to on per brainstorm).

## Technical Considerations

### Architecture Constraint: Bash 3.2 Minimum

macOS ships bash 3.2. **No associative arrays (`declare -A`), no `readarray`, no `${var,,}` lowercase.** Themes must use `case` statements. This is a hard constraint.

### ANSI Width Measurement

Priority truncation (Phase 6) must measure display width excluding ANSI escapes. Approach: `sed` to strip escapes, then `${#var}` for character count. Unicode double-width characters are accepted as approximate — pure bash cannot determine true display width.

### Performance Budget

The status bar runs after every assistant message. Target: complete in <200ms. Currently ~3 git commands. Phase 2 adds 2 more (capped). All git commands use `-c core.fsmonitor=false`. No network calls in the hot path (update check is background-only).

### NO_COLOR Support

Respect the `NO_COLOR` environment variable (https://no-color.org/). When set, force `theme=mono` regardless of config. Implement during Phase 5 (themes).

### Config Backward Compatibility

All new config keys have defaults that preserve current behavior, with one exception: `use_icons=true` by default (per brainstorm decision). Users upgrading will see icons appear. This is intentional but should be documented in release notes.

## System-Wide Impact

- **Single file affected**: `statusline-command.sh` — all 7 phases modify this file only
- **Config surface grows**: ~15 new config keys across all phases (documented below)
- **No external dependencies added**: Pure bash throughout
- **Install/update process unchanged**: `install.sh` overwrites the script, never touches `statusline.conf`
- **ShellCheck CI**: All changes must pass at `severity: warning`

## Implementation Phases

### Phase 1: Conditional Visibility + Auto-Hide

**Goal:** Segments auto-hide when their data is empty/zero. Polish existing guards and add `auto_hide` master toggle.

**Config keys:**
- `auto_hide=true` (default: true) — master toggle; when false, all segments render even if empty

**Behavior:**
- `show_X=true` enables/disables a segment entirely
- When `auto_hide=true`, enabled segments with empty/zero data are still suppressed
- When `auto_hide=false`, enabled segments always render (show `+0 -0`, `0 dirty`, `$0.00`, etc.)

**Changes to `statusline-command.sh`:**
- Add `auto_hide=true` to config defaults section (~line 128)
- Wrap existing zero-checks in `auto_hide` conditional
- Add zero-checks to segments that currently lack them (cost shows `$0` today)
- Standardize: numeric `0` and `0.0` and `0.00` all treated as zero
- Duration: hide when `< 60s` (currently hides when `0`)

**Acceptance criteria:**
- [ ] `auto_hide=true`: cost hidden when `$0`, duration hidden when `<60s`, lines hidden when `+0 -0`
- [ ] `auto_hide=false`: all enabled segments visible with zero/empty values
- [ ] Existing behavior preserved for users without `auto_hide` in their conf
- [ ] ShellCheck passes

---

### Phase 2: Git Segments — Ahead/Behind + Stash Count

**Goal:** Show unpushed/unpulled commits and stash count. Conservative — only 2 new git commands.

**Config keys:**
- `show_ahead_behind=true` (default: true)
- `show_stash=true` (default: true)

**Git commands (inside existing repo-detection guard):**

```bash
# Ahead/behind — suppress on failure (no upstream, detached HEAD)
if [ "$show_ahead_behind" = "true" ]; then
  ab_output=$(git -C "$cwd" -c core.fsmonitor=false rev-list --left-right --count HEAD...@{upstream} 2>/dev/null) || ab_output=""
  # Parse: "ahead\tbehind" format (left=HEAD ahead, right=upstream behind)
fi

# Stash count
if [ "$show_stash" = "true" ]; then
  stash_count=$(git -C "$cwd" -c core.fsmonitor=false stash list 2>/dev/null | wc -l | tr -d ' ')
fi
```

**Display format:**
- Ahead/behind: `↓3 ↑1` (cyan, matching git convention). Hidden when both are 0.
- Stash: `stash:2` (yellow). Hidden when 0.
- Position: after dirty count, before duration

**Edge cases:**
- No upstream configured → `rev-list` fails → `|| ab_output=""` catches it → segment hidden (silent)
- Detached HEAD → same handling, silently hidden
- Bare repo → `rev-parse --git-dir` succeeds but stash/rev-list may fail → guarded by `|| true` / `2>/dev/null`
- Shallow clone → ahead/behind may be inaccurate; accepted (no fix in pure bash)

**Critical `set -e` safety:** The `|| ab_output=""` pattern is essential. Without it, a failed `git rev-list` would kill the entire script under `set -e`. Similarly, stash uses `2>/dev/null` and piping (which masks exit codes). Both patterns are already used in the existing codebase for branch detection.

**Acceptance criteria:**
- [ ] Ahead/behind shows when upstream exists and counts are non-zero
- [ ] Stash count shows when stashes exist
- [ ] Both silently hidden when no git repo, no upstream, detached HEAD, or counts are zero
- [ ] No script crash on any git edge case (`set -e` safe)
- [ ] Git commands use `-C "$cwd" -c core.fsmonitor=false`
- [ ] ShellCheck passes

---

### Phase 3: Context Intelligence — Warnings + Cost Rate

**Goal:** Alert users when context is filling up. Show cost burn rate.

**Config keys:**
- `context_warn_threshold=80` (default: 80) — percentage at which a warning icon appears
- `show_cost_rate=true` (default: true)

**Context warning:**
- When `used_percentage >= context_warn_threshold`, prepend a warning indicator to the context bar
- Visual: `⚠` icon before the bar when threshold exceeded (e.g., `⚠ ██████████ 92%`)
- Colour: the bar already turns red at 80% — the warning icon adds emphasis
- The icon respects `use_icons` toggle (Phase 4); when icons off, use text `WARN` or just rely on colour

**Cost rate:**
- Formula: `total_cost_usd / (total_duration_ms / 3600000)` = dollars per hour
- Display: `$2.40/hr` (yellow, next to session cost)
- Suppress when `total_duration_ms < 60000` (< 1 minute) to avoid division issues and wildly inaccurate rates
- Bash lacks floating-point math. Use one of:
  - `awk "BEGIN {printf \"%.2f\", $total_cost / ($duration_ms / 3600000)}"` (awk is available everywhere including MSYS2)
  - Or integer math with cents: multiply cost by 100, do integer division, format result
- Prefer awk — it's POSIX, available on all target platforms (including MSYS2), and simpler than integer gymnastics
- **Note:** awk is not an "external dependency" in the way jq is — it ships with every Unix-like system and MSYS2. This does not violate the "no dependencies" design principle

**Acceptance criteria:**
- [ ] Warning icon appears at configurable threshold (default 80%)
- [ ] Cost rate displays as `$X.XX/hr` in yellow
- [ ] Cost rate hidden when duration < 60 seconds
- [ ] No division-by-zero crash
- [ ] Configurable threshold via `context_warn_threshold`
- [ ] ShellCheck passes

---

### Phase 4: Icon/Emoji Mode

**Goal:** Prepend Unicode icons to each segment. On by default (per brainstorm).

**Config keys:**
- `use_icons=true` (default: true)

**Icon table (single-width Unicode symbols only — no emoji, no double-width):**

| Segment | Icon | Unicode |
|---------|------|---------|
| Directory | (none — path is self-evident) | — |
| Branch | `⌥` (U+2325) | branch indicator (distinct from worktree's `⎇`) |
| Model | `⚙` (U+2699) | single-width gear |
| Context bar | (none — bar is visual enough) | — |
| Lines changed | (none — `+N -N` format is clear) | — |
| Dirty count | `●` (U+25CF) | dot indicator |
| Ahead/behind | (arrows `↓↑` are already in the display) | — |
| Stash | `≡` (U+2261) | stack indicator (single-width, widely supported) |
| Duration | `◷` (U+25F7) | clock face (single-width, avoids emoji `⏱`) |
| Worktree | `⎇` (U+2387) | (keep existing) |
| Cost | (none — `$` prefix is already present) | — |
| Update | `⬆` (U+2B06) | (keep existing) |
| Context warning | `⚠` (U+26A0) | warning triangle |

**Icon selection criteria:** All icons must be single-width Unicode characters (BMP, non-emoji). Avoid U+1Fxxx emoji codepoints — they render as double-width on most terminals and break width calculations in Phase 6.

**Implementation note:** Only add icons where they genuinely aid scanning. Don't add icons to segments that are already visually distinct (progress bar, `+N -N` format, `$` prefix). The existing `⎇` and `⬆` characters become part of the icon system — hidden when `use_icons=false`.

**Migration:** Existing `⎇` (worktree) and `⬆` (update) are currently always shown. After Phase 4, they only appear when `use_icons=true`. Since icons default to on, behavior is preserved. But users who set `use_icons=false` will lose these icons — this is the intended behavior.

**Acceptance criteria:**
- [ ] Icons appear before relevant segments when `use_icons=true`
- [ ] No icons when `use_icons=false` (including existing `⎇` and `⬆`)
- [ ] Only single-width Unicode characters used
- [ ] Icons work on macOS Terminal, iTerm2, Windows Terminal, GNOME Terminal, tmux
- [ ] ShellCheck passes

---

### Phase 5: Colour Themes

**Goal:** Predefined colour palettes selectable via config. Must work on bash 3.2.

**Config keys:**
- `colour_theme="default"` (default: `"default"`)

**Implementation approach:** Extract all ANSI codes into variables, set them via a `case` statement on `colour_theme`.

```bash
# Colour theme setup
apply_theme() {
  case "${colour_theme:-default}" in
    nord)
      CLR_DIR="\033[38;5;81m"    # nord frost blue
      CLR_BRANCH="\033[38;5;139m" # nord aurora purple
      # ... etc
      ;;
    dracula)
      CLR_DIR="\033[38;5;141m"    # dracula purple
      # ... etc
      ;;
    solarized)
      # ... etc
      ;;
    mono)
      CLR_DIR="" CLR_BRANCH="" CLR_MODEL="" # all empty
      CLR_RESET=""
      ;;
    *) # default — current colours
      CLR_DIR="\033[0;36m"
      CLR_BRANCH="\033[0;35m"
      CLR_MODEL="\033[0;34m"
      CLR_ADD="\033[0;32m"
      CLR_DEL="\033[0;31m"
      CLR_WARN="\033[0;33m"
      CLR_RESET="\033[0m"
      ;;
  esac
}
```

**Colour variables needed:**
- `CLR_DIR`, `CLR_BRANCH`, `CLR_MODEL`, `CLR_ADD`, `CLR_DEL`, `CLR_WARN`, `CLR_INFO`, `CLR_RESET`
- `CLR_BAR_OK`, `CLR_BAR_MED`, `CLR_BAR_HIGH` (for progress bar thresholds)

**NO_COLOR support:**
```bash
[ -n "${NO_COLOR:-}" ] && colour_theme="mono"
```

**Invalid theme fallback:** Unknown theme name falls through to `*)` default case — no error, just default colours.

**Refactor required:** Replace all inline `\033[...m` codes in the segment-building section with `$CLR_*` variables. This is the most invasive internal change but does not alter external behavior.

**Acceptance criteria:**
- [ ] 5 built-in themes: default, nord, dracula, solarized, mono
- [ ] Theme selected via `colour_theme` in config
- [ ] `NO_COLOR` environment variable forces mono theme
- [ ] Invalid theme name falls back to default
- [ ] No bash 4+ features (no associative arrays)
- [ ] All existing inline ANSI codes replaced with variables
- [ ] Visual output identical to current when using `default` theme
- [ ] ShellCheck passes

---

### Phase 6: Priority Truncation

**Goal:** When terminal is narrow, drop lowest-priority segments to fit.

**Config keys:**
- `enable_truncation=false` (default: false — opt-in)
- `max_width=""` (default: empty — auto-detect)

**Width detection chain:**
1. If `max_width` is set in config, use it
2. Try `tput cols 2>/dev/null`
3. Try `$COLUMNS`
4. Fall back to 120 (brainstorm decision)
5. If all fail and `enable_truncation=true`, use 120

**Segment priority table (highest = kept longest):**

| Priority | Segment(s) |
|----------|-----------|
| 1 (highest) | Directory + Branch |
| 2 | Context bar + Warning |
| 3 | Model name |
| 4 | Cost + Cost rate |
| 5 | Lines changed + Dirty count |
| 6 | Ahead/behind + Stash |
| 7 | Duration |
| 8 | Worktree |
| 9 (lowest) | Update notification |

**Width measurement:**
```bash
# Strip ANSI escapes, then measure character count
strip_ansi() {
  printf '%s' "$1" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'
}
visible_width() {
  local stripped
  stripped=$(strip_ansi "$1")
  echo ${#stripped}
}
```

**Algorithm:**
1. Build all segments into an indexed array (bash 3.2 compatible: `segments[0]="..."`, `priorities[0]=1`, etc.)
2. Measure total visible width
3. While total > max_width: find segment with lowest priority, remove it, remeasure
4. Concatenate remaining segments in original order

**Note:** Unicode double-width characters will cause ~1-2 char measurement error. Accepted as a known limitation — pure bash cannot determine true display width.

**Acceptance criteria:**
- [ ] Truncation disabled by default (`enable_truncation=false`)
- [ ] When enabled, correctly detects terminal width via tput/COLUMNS/config
- [ ] Lowest-priority segments dropped first
- [ ] Width measurement strips ANSI escapes
- [ ] Falls back to 120 when width unknown
- [ ] No visual artifacts (no trailing separators after truncation)
- [ ] ShellCheck passes

---

### Phase 7: Segment Grouping

**Goal:** Visually group related segments with brackets.

**Config keys:**
- `use_groups=false` (default: false — opt-in)
- `group_open="["` (default)
- `group_close="]"` (default)

**Group definitions (hardcoded, not user-configurable in v1):**

| Group | Segments |
|-------|----------|
| Git | branch, ahead/behind, dirty count, stash, lines changed |
| Context | model, context bar (+ warning) |
| Session | duration, cost, cost rate |

**Display example:**
```
~/projects/app [main ↓3 +42 -7 2 dirty stash:1]  [Sonnet ████████░░ 78%]  [12m $0.45 $2.40/hr]
```

**Separator rules:**
- Between groups: double-space `"  "` (current behavior)
- Within groups: single-space `" "`
- Brackets inherit the colour of the first segment in the group (or use `CLR_WARN` for a neutral tone)

**Interaction with truncation (Phase 6):**
- Groups are atomic for truncation — if any segment in a group must be dropped, the entire group is evaluated as a unit based on its highest-priority member
- Exception: the Git group can lose low-priority members (stash, ahead/behind) before the whole group is dropped, since branch is priority 1

**Empty groups:**
- If all segments in a group are hidden (by toggle or auto-hide), the group brackets are not rendered

**Acceptance criteria:**
- [ ] Groups disabled by default (`use_groups=false`)
- [ ] Configurable bracket characters
- [ ] Empty groups produce no output (no orphaned brackets)
- [ ] Groups work correctly with truncation (atomic dropping)
- [ ] Groups work correctly with conditional visibility
- [ ] ShellCheck passes

---

## Implementation Order

The SpecFlow analysis recommended a dependency-aware order. Adjusted from the brainstorm's numbered phases:

| Step | Phase | Rationale |
|------|-------|-----------|
| 1 | Phase 1: Conditional Visibility | Standalone, low risk, immediate UX improvement |
| 2 | Phase 5: Colour Themes | Refactors all colour handling — prerequisite for icons and clean segment code |
| 3 | Phase 4: Icon Mode | Depends on theme infrastructure for consistent styling |
| 4 | Phase 2: Git Segments | Standalone new segments, uses established patterns |
| 5 | Phase 3: Context Intelligence | Builds on existing segments, adds cost rate |
| 6 | Phase 6: Priority Truncation | Requires all segments to be finalized |
| 7 | Phase 7: Segment Grouping | Depends on truncation being stable |

Each phase is a separate commit (or PR). Each must pass ShellCheck and manual testing before the next begins.

## New Config Keys Summary

| Key | Default | Phase | Description |
|-----|---------|-------|-------------|
| `auto_hide` | `true` | 1 | Auto-hide segments with empty/zero data |
| `show_ahead_behind` | `true` | 2 | Show git ahead/behind remote counts |
| `show_stash` | `true` | 2 | Show git stash count |
| `context_warn_threshold` | `80` | 3 | Context % that triggers warning indicator |
| `show_cost_rate` | `true` | 3 | Show cost-per-hour burn rate |
| `use_icons` | `true` | 4 | Prepend Unicode icons to segments |
| `colour_theme` | `"default"` | 5 | Colour palette (default/nord/dracula/solarized/mono) |
| `enable_truncation` | `false` | 6 | Drop low-priority segments on narrow terminals |
| `max_width` | `""` | 6 | Override terminal width (empty = auto-detect) |
| `use_groups` | `false` | 7 | Group related segments with brackets |
| `group_open` | `"["` | 7 | Group opening bracket character |
| `group_close` | `"]"` | 7 | Group closing bracket character |

## Testing Strategy

**Manual testing (per phase):**
```bash
# Test with sample JSON
echo '{"cwd":"/tmp","display_name":"Sonnet","used_percentage":85,"total_cost_usd":1.50,"total_lines_added":42,"total_lines_removed":7,"total_duration_ms":720000}' | bash statusline-command.sh

# Test with config overrides
echo "use_icons=false" > ~/.claude/statusline.conf
echo "colour_theme=nord" >> ~/.claude/statusline.conf

# Test edge cases
echo '{}' | bash statusline-command.sh                    # empty JSON
echo '{"cwd":"/nonexistent"}' | bash statusline-command.sh # no git repo
```

**Consider adding automated tests** (bash script that asserts output contains/excludes expected substrings) before Phase 6, as truncation + grouping interactions are hard to verify manually.

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| Script size growth (~300 → ~600+ lines) | Keep phases focused; consider refactoring after Phase 7 if needed |
| Icon rendering on legacy terminals | Icons are on by default but easily disabled; use single-width Unicode only |
| Git command latency (2 new commands) | Only 2 commands added (conservative); all use `-c core.fsmonitor=false` |
| Bash 3.2 constraint limits theme implementation | Use `case` statements instead of associative arrays |
| Truncation width measurement is approximate | Accepted limitation; document in README |
| Breaking change: icons on by default | Document in release notes; one-line config to disable |

## Success Metrics

- All 7 phases implemented and passing ShellCheck
- Status bar renders in <200ms with all features enabled
- No crashes on edge cases (no repo, no upstream, empty JSON, narrow terminal)
- README updated with all new config keys
- Users can opt out of any new feature via `statusline.conf`

## Sources & References

- **Origin brainstorm:** [docs/brainstorms/2026-03-05-status-bar-enhancements-brainstorm.md](docs/brainstorms/2026-03-05-status-bar-enhancements-brainstorm.md) — Key decisions: incremental approach, conservative git segments (ahead/behind + stash only), icons on by default, themes inline, skip context remaining estimate
- **SpecFlow analysis:** Identified critical gaps around bash 3.2 compatibility, ANSI width measurement, NO_COLOR support, git edge cases, and group/truncation interaction
- Current implementation: `statusline-command.sh:1-332`
- NO_COLOR standard: https://no-color.org/
