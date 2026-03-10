# Sprint Plan

Validated sprint plan derived from [ROADMAP.md](ROADMAP.md). Each sprint is a shippable release with a focused theme. Features are ordered by dependency chain, not arbitrary grouping.

> **Methodology**: Feature-based releases via GitHub Milestones (not time-boxed sprints). Each milestone ships when complete or after ~2 weeks, whichever comes first. Bug fixes ship immediately as patch releases. This follows the pattern of successful solo-maintained shell projects (starship, fzf, powerlevel10k).
>
> **Versioning**: Stay on 1.x as long as possible. Only bump to 2.0.0 if `statusline.conf` compatibility breaks. Patch (1.3.x) for bug fixes. Minor (1.x.0) for new features.

---

## Sprint 0: v1.3.1 — Housekeeping

**Theme**: Fix known bugs and documentation inaccuracies before adding features.
**Why first**: Bugs in the codebase compound — fixing them now prevents regressions in later sprints. Shipping a patch release also validates the release pipeline.

| # | Item | Type | Effort | Risk |
|---|------|------|--------|------|
| 0.1 | Fix CHANGELOG inaccuracy (`read -r -d ''` → `input=$(cat)`) | docs | ~5 min | None |
| 0.2 | Add numeric guard for `cached_time` in update check (line 131), matching usage cache pattern at line 464 | bug | ~10 lines | Low — arithmetic guard is proven pattern |
| 0.3 | Document wget auth header exposure in CLAUDE.md | docs | ~3 lines | None |
| 0.4 | Handle empty-string JSON values in `extract_from()` | bug | ~5 lines | Low — add `\"([^\"]*)\"` alternate regex |
| 0.5 | Session start placeholder — show "Starting..." when JSON fields are null | enhancement | ~15 lines | Low — conditional at top of segment building |

**Estimated LOC**: ~35 new/modified
**Depends on**: Nothing
**Releases as**: v1.3.1 (patch)

---

## Sprint 1: v1.4.0 — New Segments

**Theme**: Consume the API fields we're already receiving but ignoring. Pure additive — no refactoring.
**Why second**: Each new segment is independent (~10-15 lines, just extract + conditional + `add_seg`). Low risk, high user value, and builds familiarity with the segment pattern before we change it.

| # | Item | Type | Effort | Risk |
|---|------|------|--------|------|
| 1.0 | **`extract_block()` helper** for nested JSON extraction | infra | ~15 lines | Low — proven pattern from `five_hour`/`seven_day` block extraction |
| 1.1 | Vim mode segment (`vim.mode` → NORMAL/INSERT) | feature | ~12 lines | Low — field may be absent, use conditional |
| 1.2 | Agent name segment (`agent.name`) | feature | ~12 lines | Low — same pattern as vim mode |
| 1.3 | Token count segment (`total_input_tokens`/`total_output_tokens`) | feature | ~15 lines | Low — format as "15k in 4k out" |
| 1.4 | API wait time segment (`total_api_duration_ms`) | feature | ~12 lines | Low — format as "API 2.3s" |
| 1.5 | 200k token warning (automatic, `exceeds_200k_tokens`) | feature | ~8 lines | Low — prepend warning icon to context bar |
| 1.6 | Cache hit ratio segment (`current_usage.cache_*`) | feature | ~18 lines | Medium — uses `extract_block()` from 1.0 |
| 1.7 | Use `workspace.current_dir` with `cwd` fallback | enhancement | ~3 lines | Low — already doing similar fallback |
| 1.8 | `bar_width` config option (currently hardcoded to 10) | config | ~5 lines | Low — replace literal with variable |
| 1.9 | `branch_max_length` config option | config | ~8 lines | Low — truncate with `${branch:0:$max}...` |
| 1.10 | `separator` config option (default `"  "`) | config | ~10 lines | Low — replace hardcoded in assembly loop |

**Estimated LOC**: ~120 new/modified
**Depends on**: Sprint 0 (clean baseline)
**Releases as**: v1.4.0 (minor)

### Dependency notes

- **Item 1.0 (`extract_block`) must be first.** Multiple segments (1.3, 1.4, 1.6) need to extract fields from nested JSON objects. This helper generalises the existing `fh_pattern`/`sd_pattern` approach from the usage parsing code — extract a parent block, then extract within it. Build it once, reuse everywhere.
- Items 1.1-1.6 are independent of each other after 1.0 lands — can be implemented in any order.
- Item 1.6 (cache hit ratio) requires extracting from `current_usage` block via `extract_block()`.
- Item 1.8 (`bar_width`) should land before Sprint 3 (bar styles), since bar styles build on a configurable width.
- Item 1.10 (`separator`) should land before Sprint 3 (separator styles), since styles build on a configurable separator.

---

## Sprint 2: v1.5.0 — Directory & Display Polish

**Theme**: Improve information density and visual hierarchy without changing architecture.
**Why third**: These are independent visual improvements. Fish-style dirs and model coloring are high-value, low-risk. This sprint builds user trust before we tackle layout changes.

| # | Item | Type | Effort | Risk |
|---|------|------|--------|------|
| 2.1 | Fish-style directory truncation (`dir_style=fish`) | feature | ~25 lines | Medium — path manipulation, must handle Windows paths |
| 2.2 | Model tier coloring (Haiku=green, Sonnet=yellow, Opus=red) | feature | ~12 lines | Low — case statement on `model` name |
| 2.3 | `CLR_DIM` modifier for secondary info (reset times, $/hr) | feature | ~15 lines | Low — add to all 5 themes, apply to labels |
| 2.4 | `workspace.project_dir` display — show project name when cwd differs | feature | ~12 lines | Low — compare two extracted paths |
| 2.5 | 4 new themes: tokyo-night, rose-pine, gruvbox, catppuccin | feature | ~80 lines | Low — just CLR_* variable assignments |
| 2.6 | Per-segment icon overrides (`icon_branch="🌿"` etc.) | config | ~20 lines | Low — read from config, fallback to defaults |
| 2.7 | Overflow indicator — show `…` when segments are truncated | enhancement | ~10 lines | Low — append after truncation loop |

**Estimated LOC**: ~175 new/modified
**Depends on**: Sprint 1 (needs `bar_width`, `separator` config)
**Releases as**: v1.5.0 (minor)

### Dependency notes

- Item 2.1 (fish dirs) must handle `~` expansion and `/c/Users/...` MSYS2 paths. Test on all 3 platforms.
- Items 2.2 and 2.3 are independent visual changes — no risk of conflict.
- Item 2.5 (themes) is pure additive — new cases in `apply_theme()`.
- Item 2.7 (overflow) depends on the truncation system being stable (it is — no changes planned until Sprint 4).

---

## Sprint 3: v1.6.0 — Layout & Bar Styles

**Theme**: Major visual upgrade — multi-line, bar styles, separator styles, right-alignment.
**Why fourth**: These features touch the assembly and truncation systems (lines 766-878). Doing them after the simpler additive sprints means we have a stable baseline with more segments to test with.

| # | Item | Type | Effort | Risk |
|---|------|------|--------|------|
| 3.1 | Progress bar styles (`bar_style=block/filled/dots/line/ascii`) | feature | ~35 lines | Low — parametrize fill/empty chars in `build_progress_bar()` |
| 3.2 | Separator styles: space, pipe, capsule (`separator_style`) | feature | ~20 lines | Low — just different separator strings |
| 3.3 | Two-line layout (`layout=two-line`) | feature | ~60 lines | **High** — needs `seg_line[]` array, per-line truncation, two assembly passes |
| 3.4 | Right-aligned segments (`align_right="cost,duration"`) | feature | ~60 lines | **High** — ANSI width calc fragile, terminal width detection |
| 3.5 | Progressive truncation cascade | enhancement | ~90 lines | **High** — multi-stage: shorten dir, abbreviate model, shorten labels, then drop. Effectively a rewrite of the output pipeline. |
| 3.6 | Segment reordering (`segment_order="dir,branch,..."`) | feature | ~110 lines | **High** — requires naming each segment + Bash 3.2-compatible mapping (parallel name arrays, NOT associative arrays) |

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

| # | Item | Type | Effort | Risk |
|---|------|------|--------|------|
| 4.1 | **BATS test scaffold** — setup, JSON parsing tests, progress bar tests | testing | ~150 lines | Medium — one-time setup cost |
| 4.2 | **CI matrix** — add macOS and Windows (MSYS2) to GitHub Actions | ci | ~40 lines | Medium — MSYS2 CI setup can be finicky |
| 4.3 | Token speed segment (`show_token_speed`) | feature | ~35 lines | Medium — needs delta cache file between invocations |
| 4.4 | Session budget bar (`session_budget=5.00`) | feature | ~20 lines | Low — reuses `build_progress_bar()` |
| 4.5 | Cost velocity indicator (`$2.40/hr ↑`) | feature | ~15 lines | Low — compare current rate vs previous rate from cache |
| 4.6 | Alert-only usage mode (`usage_alert_threshold=80`) | feature | ~8 lines | Low — conditional wrapper around existing segments |
| 4.7 | Rate limit countdown (show "resets in 47m" when at 100%) | feature | ~15 lines | Low — reuses `iso_to_epoch()` and existing reset data |
| 4.8 | `--dump-config` CLI flag | cli | ~25 lines | Low — print all config values |
| 4.9 | `--preview` CLI flag (render with sample data) | cli | ~20 lines | Low — hardcoded JSON piped through the script |

**Estimated LOC**: ~330 new/modified
**Depends on**: Sprint 1 (token extraction), Sprint 3 (stable assembly)
**Releases as**: v1.7.0 (minor)

### Dependency notes

- **Item 4.1 (BATS tests) is the highest-value item in this sprint.** It protects all prior work. Tests should cover: `extract_from()`, `extract_num_from()`, `build_progress_bar()`, `sanitize()`, theme application, config loading, truncation, and edge cases (empty input, null fields).
- Item 4.3 (token speed) depends on Sprint 1's token count extraction (item 1.3). The delta calculation needs a cache file: store `"$NOW_EPOCH $total_tokens"`, read previous entry, compute `(new_tokens - old_tokens) / (new_time - old_time)`.
- Item 4.4 (session budget) reuses `build_progress_bar()` with `$total_cost / $session_budget * 100` as the percentage. Trivial if bar_width is configurable (Sprint 1).
- Items 4.6 and 4.7 build on existing usage infrastructure — low risk.

---

## Sprint 5: v1.8.0 — CLI & Persistence

**Theme**: CLI polish and persistent analytics. The script becomes a proper CLI tool.
**Why sixth**: The `--uninstall` and `--stats` features need the persistent history file. History tracking is a prerequisite for daily aggregation.

| # | Item | Type | Effort | Risk |
|---|------|------|--------|------|
| 5.1 | Session history logging (`~/.claude/.statusline-history.jsonl`) | feature | ~30 lines | Medium — write one line per session, avoid bloat |
| 5.2 | Today's totals segments (`show_today_cost`, `show_today_tokens`) | feature | ~25 lines | Medium — read and aggregate today's log entries |
| 5.3 | `--stats today/week/month` CLI reporting | cli | ~45 lines | Medium — parse JSONL, aggregate, format |
| 5.4 | `--uninstall` CLI flag | cli | ~25 lines | Low — `rm` files, print instructions for settings.json |
| 5.5 | `--test` CLI flag (debug output with hidden/truncated segment info) | cli | ~20 lines | Low — add debug annotations to output |
| 5.6 | Plan-aware limits (`plan_type=max5`) | feature | ~30 lines | Medium — needs hardcoded plan caps, validate against API |
| 5.7 | Clickable OSC 8 links (`use_links=true`) | feature | ~25 lines | Medium — terminal compatibility varies |
| 5.8 | Install script testing in CI | ci | ~30 lines | Medium — needs clean environment simulation |

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

| # | Item | Type | Effort | Risk |
|---|------|------|--------|------|
| 6.1 | Refactor segments into named functions | refactor | ~100 lines | **High** — touches every segment |
| 6.2 | Custom segments via config (`custom_segment_1="uptime -p"`) | feature | ~30 lines | Medium — needs sanitization |
| 6.3 | Modular segment loading from `~/.claude/statusline-segments/` | feature | ~25 lines | Medium — source external files |
| 6.4 | Optimize `sanitize()` — fast-path for strings without ANSI | perf | ~10 lines | Low — `[[ $str == *$'\033'* ]]` guard |
| 6.5 | Replace `echo \| cut` with bash parameter expansion for ahead/behind | perf | ~5 lines | Low — proven bash pattern |
| 6.6 | Replace `git stash list \| wc -l` with `git rev-list --count refs/stash` | perf | ~3 lines | Low — single process |
| 6.7 | Reduce `format_reset_label()` date forks with epoch arithmetic | perf | ~20 lines | Medium — day-of-week from epoch is tricky |
| 6.8 | `--benchmark` CLI flag | perf | ~15 lines | Low — loop + timing |
| 6.9 | Comprehensive BATS coverage (all segments, all themes, all platforms) | testing | ~200 lines | Medium — large but incremental |
| 6.10 | CONTRIBUTING.md and JSON schema docs | docs | ~100 lines | None |
| 6.11 | Automated release workflow (GitHub Actions on VERSION change) | ci | ~40 lines | Medium — needs tag + release automation |

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
| 1 (v1.4.0) | ~120 | 11 |
| 2 (v1.5.0) | ~175 | 7 |
| 3 (v1.6.0) | ~375 | 6 |
| 4 (v1.7.0) | ~330 | 9 |
| 5 (v1.8.0) | ~230 | 8 |
| 6 (v2.0.0) | ~550 | 11 |
| **Total** | **~1,815** | **57** |
