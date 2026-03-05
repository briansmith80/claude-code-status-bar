# Brainstorm: Status Bar Enhancements

**Date:** 2026-03-05
**Status:** Draft

## What We're Building

A comprehensive enhancement of the Claude Code status bar, adding new data segments, smarter context awareness, visual polish, and layout intelligence — all delivered incrementally to the existing single-file architecture.

## Why This Approach

**Incremental enhancement** (Approach A) was chosen over a segment engine refactor or modular plugin system. The status bar is a single bash script with no dependencies — that simplicity is a feature. Each enhancement ships as a new config toggle, fully backward compatible. Refactoring can happen later if the script outgrows its structure.

## Key Decisions

### 1. New Git Segments (Conservative)

Add **ahead/behind remote** and **stash count** only. Skip commit age and staged file count to minimize git command overhead.

- **Ahead/behind:** `git rev-list --count --left-right @{upstream}...HEAD` — shows unpushed/unpulled commits (e.g., `↓3 ↑1`)
- **Stash count:** `git stash list | wc -l` — shows stash indicator when non-zero (e.g., `stash:2`)
- Both gated behind `show_ahead_behind=true` and `show_stash=true` (default: true)
- Gracefully handle no upstream set (ahead/behind silently hidden)

### 2. Context Window Intelligence

Three new features layered onto the existing context bar:

- **Warning thresholds:** Configurable alerts at context milestones. When context hits a threshold, the percentage text gets highlighted/flashing. Config: `context_warn_thresholds="70,85,95"`. Visual: prepend a warning icon at 85%+.
- **Cost rate:** Calculate `total_cost_usd / (duration_ms / 3600000)` to show burn rate (e.g., `$2.40/hr`). Config: `show_cost_rate=true`. Only shown when both cost and duration are non-zero.
- **Context remaining estimate:** Approximate messages remaining based on avg tokens per message and remaining %. Config: `show_context_remaining=true`. This is inherently a rough estimate — label accordingly.

### 3. Visual: Icon/Emoji Mode

A single toggle `use_icons=true` (default: false) that prepends Unicode icons to segments:

| Segment | Icon |
|---------|------|
| Directory | folder icon |
| Branch | branch icon |
| Model | brain icon |
| Context | gauge icon |
| Lines | pencil icon |
| Dirty | warning icon |
| Duration | clock icon |
| Worktree | tree icon |
| Cost | money icon |
| Stash | package icon |

Implementation: Each segment conditionally prepends its icon. Icons are simple Unicode characters (not emoji) to work across terminals. Provide a `icon_style` config: `"unicode"` (default) or `"emoji"` for richer glyphs.

### 4. Visual: Colour Themes

Predefined colour palettes loaded via `colour_theme="default"` config option.

Built-in themes:
- **default** — current colours (cyan, magenta, blue, green, red, yellow)
- **nord** — muted blue/cyan palette
- **dracula** — purple/green/pink
- **solarized** — solar yellows and blues
- **mono** — no colours, plain text

Implementation: Define theme variables (e.g., `CLR_DIR`, `CLR_BRANCH`, `CLR_MODEL`, etc.) set per theme. User can also override individual colours in `statusline.conf`.

### 5. Layout: Conditional Visibility

Segments auto-hide when their data is empty or zero. This partially exists already (lines changed, dirty count, cost all check for non-zero). Extend to:

- Hide cost when `$0.00`
- Hide lines changed when both are 0 (already done)
- Hide dirty count when 0 (already done)
- Hide duration when under 1 minute (already done)
- Hide ahead/behind when at parity with remote
- Hide stash when empty
- New config: `auto_hide=true` (default: true) — when false, show all segments even when zero/empty

### 6. Layout: Priority Truncation

When terminal width is limited, drop lowest-priority segments first.

Priority order (highest to lowest):
1. Directory + Branch (identity — always shown)
2. Context bar (most actionable)
3. Model name
4. Cost + Cost rate
5. Lines changed + Dirty count
6. Ahead/behind + Stash
7. Duration
8. Worktree
9. Update notification

Implementation: Calculate total output width, compare to `$COLUMNS` (or a `max_width` config). Drop segments from the bottom of the priority list until it fits. Config: `enable_truncation=true` (default: false — opt-in since terminal width detection can be unreliable in some environments).

### 7. Layout: Segment Grouping

Group related segments with visual brackets or shared context:

- **Git group:** `[main ↓3 2 dirty stash:1]`
- **Context group:** `[Sonnet ██████░░ 72% ~15 msgs]`
- **Cost group:** `[$0.45 $2.40/hr]`

Config: `use_groups=true` (default: false). Grouping characters configurable: `group_open="["` `group_close="]"`.

## Implementation Priority

| Phase | Features | Complexity |
|-------|----------|------------|
| 1 | Conditional visibility (polish existing) | Low |
| 2 | Ahead/behind + Stash segments | Medium |
| 3 | Context warnings + Cost rate | Medium |
| 4 | Icon/emoji mode | Low |
| 5 | Colour themes | Medium |
| 6 | Priority truncation | Medium-High |
| 7 | Segment grouping | Medium |
| ~~8~~ | ~~Context remaining estimate~~ | Skipped — insufficient data from Claude Code |

## Resolved Questions

1. **Terminal width detection:** Try `tput cols` first, fall back to a `max_width` config value (default: 120), disable truncation if neither works.
2. **Icon compatibility:** Icons **on by default** (`use_icons=true`). Users can opt out with `use_icons=false`. Use Unicode symbols that work broadly.
3. **Context remaining estimate:** **Skipped.** We only have `used_percentage` — restating it adds no value. Revisit if Claude Code exposes token/message counts in the future.
4. **Theme file format:** **Inline in the script.** All themes defined as case blocks inside `statusline-command.sh`. Keeps the single-file simplicity.

## Open Questions

(None remaining)
