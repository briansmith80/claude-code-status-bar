# Sprint Plan

Validated sprint plan derived from [ROADMAP.md](ROADMAP.md). Each sprint is a shippable release with a focused theme. Features are ordered by dependency chain, not arbitrary grouping. Tracked via [GitHub Milestones](https://github.com/briansmith80/claude-code-status-bar/milestones).

> **Methodology**: Feature-based releases via GitHub Milestones (not time-boxed sprints). Each milestone ships when complete or after ~2 weeks, whichever comes first. Bug fixes ship immediately as patch releases. This follows the pattern of successful solo-maintained shell projects (starship, fzf, powerlevel10k).
>
> **Versioning**: Stay on 1.x as long as possible. Only bump to 2.0.0 if `statusline.conf` compatibility breaks. Patch (1.3.x) for bug fixes. Minor (1.x.0) for new features.

---

## Sprint 0: v1.3.1 — Housekeeping

**Theme**: Fix known bugs and documentation inaccuracies before adding features.
**Why first**: Bugs in the codebase compound — fixing them now prevents regressions in later sprints. Shipping a patch release also validates the release pipeline.

| | # | Item | Type | Effort | Risk |
|---|---|------|------|--------|------|
| [x] | 0.1 | Fix CHANGELOG inaccuracy (`read -r -d ''` → `input=$(cat)`) — #53 | docs | ~5 min | None |
| [x] | 0.2 | Add numeric guard for `cached_time` in update check — #54 | bug | ~10 lines | Low |
| [x] | 0.3 | Document wget auth header exposure in CLAUDE.md — #55 | docs | ~3 lines | None |
| [x] | 0.4 | Handle empty-string JSON values in `extract_from()` — #56 | bug | ~5 lines | Low |
| [x] | 0.5 | Session start placeholder — show "Starting..." — #57 | enhancement | ~15 lines | Low |

**Estimated LOC**: ~35 new/modified
**Depends on**: Nothing
**Releases as**: v1.3.1 (patch)

---

## Sprint 1: v1.4.0 — New Segments

**Theme**: Consume the API fields we're already receiving but ignoring, plus token conservation awareness features. Pure additive — no refactoring.
**Why second**: Each new segment is independent (~10-15 lines, just extract + conditional + `add_seg`). Low risk, high user value, and builds familiarity with the segment pattern before we change it.

| | # | Item | Type | Effort | Risk |
|---|---|------|------|--------|------|
| [ ] | 1.0 | **`extract_block()` helper** for nested JSON extraction — #1 | infra | ~15 lines | Low |
| [ ] | 1.1 | Vim mode segment (`vim.mode` → NORMAL/INSERT) — #2 | feature | ~12 lines | Low |
| [ ] | 1.2 | Agent name segment (`agent.name`) — #3 | feature | ~12 lines | Low |
| [ ] | 1.3 | Token count segment (`total_input_tokens`/`total_output_tokens`) — #4 | feature | ~15 lines | Low |
| [ ] | 1.4 | API wait time segment (`total_api_duration_ms`) — #5 | feature | ~12 lines | Low |
| [ ] | 1.5 | 200k token warning (automatic, `exceeds_200k_tokens`) — #6 | feature | ~8 lines | Low |
| [ ] | 1.6 | Cache hit ratio segment (`current_usage.cache_*`) — #7 | feature | ~18 lines | Medium |
| [ ] | 1.7 | Use `workspace.current_dir` with `cwd` fallback — #8 | enhancement | ~3 lines | Low |
| [ ] | 1.8 | `bar_width` config option (currently hardcoded to 10) — #9 | config | ~5 lines | Low |
| [ ] | 1.9 | `branch_max_length` config option — #10 | config | ~8 lines | Low |
| [ ] | 1.10 | `separator` config option (default `"  "`) — #11 | config | ~10 lines | Low |
| [ ] | 1.11 | **Compact countdown** — tokens remaining before auto-compact — #58 | feature | ~15 lines | Low |
| [ ] | 1.12 | **Time-to-limit estimate** for usage bars — #59 | feature | ~20 lines | Low |

**Estimated LOC**: ~155 new/modified
**Depends on**: Sprint 0 (clean baseline)
**Releases as**: v1.4.0 (minor)

### Dependency notes

- **Item 1.0 (`extract_block`) must be first.** Multiple segments (1.3, 1.4, 1.6, 1.11) need to extract fields from nested JSON objects. This helper generalises the existing `fh_pattern`/`sd_pattern` approach from the usage parsing code — extract a parent block, then extract within it. Build it once, reuse everywhere.
- Items 1.1-1.6 are independent of each other after 1.0 lands — can be implemented in any order.
- Item 1.6 (cache hit ratio) requires extracting from `current_usage` block via `extract_block()`.
- Item 1.8 (`bar_width`) should land before Sprint 3 (bar styles), since bar styles build on a configurable width.
- Item 1.10 (`separator`) should land before Sprint 3 (separator styles), since styles build on a configurable separator.
- **Item 1.11 (compact countdown)** needs `extract_block()` for `context_window` nested fields. Pure arithmetic: `(83.5% * window_size) - (used_pct% * window_size)`. **No competitor has this — unique differentiator.**
- **Item 1.12 (time-to-limit)** uses data already in the usage cache. Linear extrapolation from pacing target and current utilization. **Most requested feature across competitors.**

---

## Sprint 2: v1.5.0 — Directory & Display Polish

**Theme**: Improve information density and visual hierarchy without changing architecture.
**Why third**: These are independent visual improvements. Fish-style dirs and model coloring are high-value, low-risk. This sprint builds user trust before we tackle layout changes.

| | # | Item | Type | Effort | Risk |
|---|---|------|------|--------|------|
| [ ] | 2.1 | Fish-style directory truncation (`dir_style=fish`) — #12 | feature | ~25 lines | Medium |
| [ ] | 2.2 | Model tier coloring (Haiku=green, Sonnet=yellow, Opus=red) — #13 | feature | ~12 lines | Low |
| [ ] | 2.3 | `CLR_DIM` modifier for secondary info — #14 | feature | ~15 lines | Low |
| [ ] | 2.4 | `workspace.project_dir` display — #15 | feature | ~12 lines | Low |
| [ ] | 2.5 | 4 new themes: tokyo-night, rose-pine, gruvbox, catppuccin — #16 | feature | ~80 lines | Low |
| [ ] | 2.6 | Per-segment icon overrides — #17 | config | ~20 lines | Low |
| [ ] | 2.7 | Overflow indicator — show `…` when truncated — #18 | enhancement | ~10 lines | Low |
| [ ] | 2.8 | **Compact buffer zone** on context bar (dim last ~16.5%) — #61 | feature | ~10 lines | Low |
| [ ] | 2.9 | **Three-tier context severity** escalation — #62 | feature | ~15 lines | Low |

**Estimated LOC**: ~200 new/modified
**Depends on**: Sprint 1 (needs `bar_width`, `separator` config, `extract_block()`)
**Releases as**: v1.5.0 (minor)

### Dependency notes

- Item 2.1 (fish dirs) must handle `~` expansion and `/c/Users/...` MSYS2 paths. Test on all 3 platforms.
- Items 2.2 and 2.3 are independent visual changes — no risk of conflict.
- Item 2.5 (themes) is pure additive — new cases in `apply_theme()`.
- Item 2.7 (overflow) depends on the truncation system being stable (it is — no changes planned until Sprint 4).
- **Item 2.8 (compact buffer zone)** depends on `CLR_DIM` from item 2.3. Dim the last ~2 chars of a 10-char context bar to show the autocompact danger zone.
- **Item 2.9 (three-tier severity)** extends existing `context_warn_threshold` with a new `context_critical_threshold=95`. Graduated green → yellow → red → red+text.

---

## Sprint 3: v1.6.0 — Layout & Bar Styles

**Theme**: Major visual upgrade — multi-line, bar styles, separator styles, right-alignment.
**Why fourth**: These features touch the assembly and truncation systems (lines 766-878). Doing them after the simpler additive sprints means we have a stable baseline with more segments to test with.

| | # | Item | Type | Effort | Risk |
|---|---|------|------|--------|------|
| [ ] | 3.1 | Progress bar styles (`bar_style=block/filled/dots/line/ascii`) — #19 | feature | ~35 lines | Low |
| [ ] | 3.2 | Separator styles: space, pipe, capsule — #20 | feature | ~20 lines | Low |
| [ ] | 3.3 | Two-line layout (`layout=two-line`) — #21 | feature | ~60 lines | **High** |
| [ ] | 3.4 | Right-aligned segments — #22 | feature | ~60 lines | **High** |
| [ ] | 3.5 | Progressive truncation cascade — #23 | enhancement | ~90 lines | **High** |
| [ ] | 3.6 | Segment reordering (`segment_order`) — #24 | feature | ~110 lines | **High** |

**Estimated LOC**: ~375 new/modified (revised upward from ~225 based on effort analysis)
**Depends on**: Sprint 1 (config options), Sprint 2 (dir_style, CLR_DIM)
**Releases as**: v1.6.0 (minor)

### Dependency notes

- **Item 3.3 (two-line layout) is the riskiest item in the entire plan.** The current truncation system (lines 766-821) assumes a single output line. Two-line layout requires: (a) a `seg_line[]` parallel array so each segment declares which line it belongs to, (b) running truncation independently per line (each has its own width budget), (c) splitting the assembly loop into two passes. Verify that Claude Code actually renders multi-line output (each `echo` → separate row, per official docs).
- **Powerline separators deferred to v2.0.** Unlike pipe/capsule (which just swap the separator string), powerline requires background+foreground colour transitions between segments — each segment needs to know the colour of its neighbour. This is a fundamentally different complexity class. Ship pipe/capsule now, powerline later.
- **Item 3.6 (segment reordering) — ~110 lines, not ~50.** Effort estimation research confirms: Bash 3.2 has no associative arrays, so you need parallel `seg_names[]` arrays and an ordering function that iterates `segment_order` and emits matching indices. Additionally, reordering can break group adjacency (e.g., moving `model` away from `context_bar` splits the "ctx" group). Must enforce that grouped segments stay together or handle non-contiguous groups.
- Item 3.4 (right-align) — ANSI escape codes make width calculation fragile. Any missed escape pattern in `strip_ansi` means the fill is the wrong width. On narrow terminals, right-aligned segments could overlap left-aligned ones.
- Item 3.5 (progressive truncation) — each segment needs multiple renderings at different verbosity levels (`seg_vals_full[]`, `seg_vals_short[]`). This significantly complicates segment registration.

### Suggested order within sprint

3.1 → 3.2 → 3.3 → 3.4 → 3.5 → 3.6

(Bar styles and separators first — low-risk, stable the base. Then two-line layout. Then right-align, progressive truncation, and reordering — each builds on the prior.)

---

## Sprint 4: v1.7.0 — Smart Features & Testing

**Theme**: Intelligence features (token speed, cost budget) plus test infrastructure to protect everything built so far.
**Why fifth**: Token speed depends on token count extraction (Sprint 1). BATS tests are critical now — 4 sprints of changes need regression protection. Combining them avoids a "boring test-only release".

| | # | Item | Type | Effort | Risk |
|---|---|------|------|--------|------|
| [ ] | 4.1 | **BATS test scaffold** — setup, JSON parsing, progress bar tests — #25 | testing | ~150 lines | Medium |
| [ ] | 4.2 | **CI matrix** — macOS and Windows (MSYS2) — #26 | ci | ~40 lines | Medium |
| [ ] | 4.3 | Token speed segment (`show_token_speed`) — #27 | feature | ~35 lines | Medium |
| [ ] | 4.4 | Session budget bar (`session_budget=5.00`) — #28 | feature | ~20 lines | Low |
| [ ] | 4.5 | Cost velocity indicator (`$2.40/hr ↑`) — #29 | feature | ~15 lines | Low |
| [ ] | 4.6 | Alert-only usage mode (`usage_alert_threshold=80`) — #30 | feature | ~8 lines | Low |
| [ ] | 4.7 | Rate limit countdown ("resets in 47m" at 100%) — #31 | feature | ~15 lines | Low |
| [ ] | 4.8 | `--dump-config` CLI flag — #32 | cli | ~25 lines | Low |
| [ ] | 4.9 | `--preview` CLI flag (render with sample data) — #33 | cli | ~20 lines | Low |
| [ ] | 4.10 | **Compact detection indicator** ("compacted" flash) — #65 | feature | ~15 lines | Low |

**Estimated LOC**: ~345 new/modified
**Depends on**: Sprint 1 (token extraction, compact countdown), Sprint 3 (stable assembly)
**Releases as**: v1.7.0 (minor)

### Dependency notes

- **Item 4.1 (BATS tests) is the highest-value item in this sprint.** It protects all prior work. Tests should cover: `extract_from()`, `extract_num_from()`, `build_progress_bar()`, `sanitize()`, theme application, config loading, truncation, and edge cases (empty input, null fields).
- Item 4.3 (token speed) depends on Sprint 1's token count extraction (item 1.3). The delta calculation needs a cache file: store `"$NOW_EPOCH $total_tokens"`, read previous entry, compute `(new_tokens - old_tokens) / (new_time - old_time)`.
- Item 4.4 (session budget) reuses `build_progress_bar()` with `$total_cost / $session_budget * 100` as the percentage. Trivial if bar_width is configurable (Sprint 1).
- Items 4.6 and 4.7 build on existing usage infrastructure — low risk.
- **Items 4.3 and 4.10 share delta cache infrastructure.** Both need a `~/.claude/.statusline-delta-cache` file storing `"$NOW_EPOCH $used_pct $total_tokens $total_cost"`. Build the cache read/write once in 4.3, reuse in 4.10.
- **Item 4.10 (compact detection)** detects `used_percentage` drops > 20% between invocations — a signature of auto-compact firing. One-shot display, then clears.

---

## Sprint 5: v1.8.0 — CLI & Persistence

**Theme**: CLI polish and persistent analytics. The script becomes a proper CLI tool.
**Why sixth**: The `--uninstall` and `--stats` features need the persistent history file. History tracking is a prerequisite for daily aggregation.

| | # | Item | Type | Effort | Risk |
|---|---|------|------|--------|------|
| [ ] | 5.1 | Session history logging (`.statusline-history.jsonl`) — #34 | feature | ~30 lines | Medium |
| [ ] | 5.2 | Today's totals segments (`show_today_cost`, `show_today_tokens`) — #35 | feature | ~25 lines | Medium |
| [ ] | 5.3 | `--stats today/week/month` CLI reporting — #36 | cli | ~45 lines | Medium |
| [ ] | 5.4 | `--uninstall` CLI flag — #37 | cli | ~25 lines | Low |
| [ ] | 5.5 | `--test` CLI flag (debug output) — #38 | cli | ~20 lines | Low |
| [ ] | 5.6 | Plan-aware limits (`plan_type=max5`) — #39 | feature | ~30 lines | Medium |
| [ ] | 5.7 | Clickable OSC 8 links (`use_links=true`) — #40 | feature | ~25 lines | Medium |
| [ ] | 5.8 | Install script testing in CI — #41 | ci | ~30 lines | Medium |

**Estimated LOC**: ~230 new/modified
**Depends on**: Sprint 4 (BATS tests for safety)
**Releases as**: v1.8.0 (minor)

### Dependency notes

- Item 5.1 (history) is the foundation for 5.2 and 5.3. Must be implemented first.
- Item 5.1 needs care to avoid unbounded file growth. Strategy: rotate when >1MB, keep 30 days.
- Item 5.6 (plan limits) requires hardcoded knowledge of plan caps. These can change — needs a way to update. Consider a separate config key rather than hardcoding.
- Item 5.7 (OSC 8 links) should be default-off since Terminal.app, Windows Terminal, and SSH sessions may not support it.

---

## Sprint 6: v2.0.0 — Architecture

**Theme**: Modular architecture, custom segments, performance optimization. Major version because of potential breaking changes to config format.
**Why last**: Refactoring the segment system is high-risk and touches everything. By this point, the BATS test suite (Sprint 4) provides a safety net.

| | # | Item | Type | Effort | Risk |
|---|---|------|------|--------|------|
| [ ] | 6.1 | Refactor segments into named functions — #42 | refactor | ~100 lines | **High** |
| [ ] | 6.2 | Custom segments via config — #43 | feature | ~30 lines | Medium |
| [ ] | 6.3 | Modular segment loading — #44 | feature | ~25 lines | Medium |
| [ ] | 6.4 | Optimize `sanitize()` — fast-path — #45 | perf | ~10 lines | Low |
| [ ] | 6.5 | Replace `echo\|cut` with parameter expansion — #46 | perf | ~5 lines | Low |
| [ ] | 6.6 | Replace `git stash list\|wc -l` — #47 | perf | ~3 lines | Low |
| [ ] | 6.7 | Reduce `format_reset_label()` date forks — #48 | perf | ~20 lines | Medium |
| [ ] | 6.8 | `--benchmark` CLI flag — #49 | cli | ~15 lines | Low |
| [ ] | 6.9 | Comprehensive BATS coverage — #50 | testing | ~200 lines | Medium |
| [ ] | 6.10 | CONTRIBUTING.md and JSON schema docs — #51 | docs | ~100 lines | None |
| [ ] | 6.11 | Automated release workflow — #52 | ci | ~40 lines | Medium |

**Estimated LOC**: ~550 new/modified
**Depends on**: All prior sprints
**Releases as**: v2.0.0 (major — potential config format changes)

### Dependency notes

- Item 6.1 (named segment functions) is the prerequisite for 6.2 (custom segments) and 6.3 (modular loading).
- Items 6.4-6.7 (performance) are independent of each other — can be done in any order.
- Item 6.9 (comprehensive tests) should be done *after* 6.1 (refactored segments) since the function signatures may change.
- **Bash 3.2 constraint**: Modular loading via `source` works fine. Custom segments via config need careful sanitization to prevent code injection — use a restricted execution environment or validate output format.

---

## Validation Summary

### Dependency Graph

```
Sprint 0 (v1.3.1 bugs)
  └─→ Sprint 1 (v1.4.0 new segments + config options)
        ├─→ Sprint 2 (v1.5.0 visual polish)
        │     └─→ Sprint 3 (v1.6.0 layout & bar styles)
        │           └─→ Sprint 4 (v1.7.0 smart features + BATS)
        │                 └─→ Sprint 5 (v1.8.0 CLI & persistence)
        │                       └─→ Sprint 6 (v2.0.0 architecture)
        └─→ Sprint 4 (token speed depends on token extraction)
```

### Risk Assessment

| Sprint | Overall Risk | Highest-Risk Item |
|--------|-------------|-------------------|
| 0 (v1.3.1) | Low | None |
| 1 (v1.4.0) | Low | Cache hit ratio nested JSON extraction |
| 2 (v1.5.0) | Low-Medium | Fish-style dirs on Windows paths |
| 3 (v1.6.0) | **High** | Two-line layout + truncation refactor |
| 4 (v1.7.0) | Medium | BATS setup + MSYS2 CI |
| 5 (v1.8.0) | Medium | Session history file management |
| 6 (v2.0.0) | **High** | Segment refactor (touches everything) |

### What Changed from the Original Roadmap

| Change | Reason |
|--------|--------|
| **Added `extract_block()` as first item in Sprint 1** | Dependency agent found multiple v1.4 segments need nested JSON extraction. Build the helper once as a prerequisite. |
| **Moved BATS tests from v2.0 to Sprint 4 (v1.7)** | All 3 research agents emphatically agreed: 4 sprints of changes need regression protection before more refactoring. |
| **Split multi-line layout from v1.4 to Sprint 3 (v1.6)** | Not a "quick win" — effort agent estimates ~60 lines, needs `seg_line[]` array and per-line truncation. |
| **Deferred powerline separators from Sprint 3 to v2.0** | Dependency agent confirmed: powerline requires background+foreground colour transitions between segments — fundamentally different complexity class from pipe/capsule. |
| **Revised Sprint 3 LOC from ~225 to ~375** | Effort agent confirmed: segment reordering is ~110 lines (not ~50), progressive truncation is ~90 lines (not ~40), right-alignment is ~60 lines (not ~35). Bash 3.2 constraint (no associative arrays) increases all estimates. |
| **Added Sprint 2 (v1.5) for visual polish** | Fish-style dirs, model coloring, and themes are independent, low-risk, and high-value. They deserve their own sprint between additive segments and layout changes. |
| **Moved `--uninstall` from v1.7 to Sprint 5 (v1.8)** | Groups well with other CLI flags and persistence features. |
| **Moved daily cost aggregation to Sprint 5** | Dependency agent found circular dependency with session history. Daily cost needs cross-session persistence that Sprint 5's JSONL log provides. |
| **Kept v2.0 as final sprint** | Architecture changes are highest-risk and benefit from maximum test coverage. |

### Methodology Validation (from sprint planning research)

The sprint plan follows patterns from successful solo-maintained shell projects:

- **Starship**: Uses GitHub Milestones per minor version, releases every 2-6 weeks. Features land when ready.
- **fzf**: Opinionated — rejects requests that don't fit. Bug-driven releases every few weeks.
- **powerlevel10k**: Stayed on v1.x for its entire active life. Major versions scare users.

Our plan aligns: milestone-based (not time-boxed), patch releases for bugs, minor releases for features, stay on 1.x, defer v2.0 until necessary.

### Total Estimated Effort

| Sprint | LOC | Items |
|--------|-----|-------|
| 0 (v1.3.1) | ~35 | 5 |
| 1 (v1.4.0) | ~155 | 13 |
| 2 (v1.5.0) | ~200 | 9 |
| 3 (v1.6.0) | ~375 | 6 |
| 4 (v1.7.0) | ~345 | 10 |
| 5 (v1.8.0) | ~230 | 8 |
| 6 (v2.0.0) | ~550 | 11 |
| **Total** | **~1,890** | **62** |
