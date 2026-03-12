# Sprint Plan

Lean sprint plan derived from [ROADMAP.md](ROADMAP.md). Three focused releases, then re-evaluate based on user feedback.

> **Methodology**: Feature-based releases via GitHub Milestones (not time-boxed). Each milestone ships when complete. Bug fixes ship immediately as patch releases.
>
> **Versioning**: Stay on 1.x. Patch (1.x.x) for bug fixes. Minor (1.x.0) for new features.

---

## Sprint 0: v1.3.1 — Housekeeping :white_check_mark:

**Status**: Complete.

| | # | Item | Type |
|---|---|------|------|
| [x] | 0.1 | Fix CHANGELOG inaccuracy — #53 | docs |
| [x] | 0.2 | Add numeric guard for `cached_time` — #54 | bug |
| [x] | 0.3 | Document wget auth header exposure — #55 | docs |
| [x] | 0.4 | Handle empty-string JSON values — #56 | bug |
| [x] | 0.5 | Session start placeholder — #57 | enhancement |

---

## Sprint 1: v1.4.0 — New Segments :white_check_mark:

**Status**: Complete.

| | # | Item | Type | Effort |
|---|---|------|------|--------|
| [x] | 1.0 | `extract_block()` helper for nested JSON — #1 | infra | ~15 lines |
| [x] | 1.1 | Vim mode segment (`vim.mode`) — #2 | feature | ~12 lines |
| [x] | 1.2 | Agent name segment (`agent.name`) — #3 | feature | ~12 lines |
| [x] | 1.3 | Token count segment (input/output) — #4 | feature | ~15 lines |
| [x] | 1.4 | 200k token warning (`exceeds_200k_tokens`) — #6 | feature | ~8 lines |
| [x] | 1.5 | Use `workspace.current_dir` with `cwd` fallback — #8 | enhancement | ~3 lines |
| [x] | 1.6 | `bar_width` config option — #9 | config | ~5 lines |
| [x] | 1.7 | `branch_max_length` config option — #10 | config | ~8 lines |

**Estimated LOC**: ~80 new/modified
**Depends on**: Sprint 0 (complete)

### Notes

- Item 1.0 (`extract_block`) must land first — items 1.3 and 1.4 need nested JSON extraction.
- Items 1.1-1.5 are independent of each other after 1.0.
- All items are low risk — each is ~10 lines, just extract + conditional + `add_seg`.

---

## Sprint 2: v1.5.0 — Visual Polish :white_check_mark:

**Status**: Complete.

| | # | Item | Type | Effort |
|---|---|------|------|--------|
| [x] | 2.1 | Model tier coloring (Haiku/Sonnet/Opus) — #13 | feature | ~12 lines |
| [x] | 2.2 | New themes: tokyo-night, catppuccin — #16 | feature | ~40 lines |

**Estimated LOC**: ~52 new/modified
**Depends on**: Sprint 1 (complete)

### Notes

- Item 2.1 is a simple case statement in the model display logic. Uses existing theme colours.
- Item 2.2 is pure additive — new cases in `apply_theme()`. Two themes with highest community demand.

---

## Sprint 3: v1.6.0 — Testing & CLI

**Theme**: Protect what we've built and add practical CLI features.

| | # | Item | Type | Effort |
|---|---|------|------|--------|
| [ ] | 3.1 | BATS test scaffold — #25 | testing | ~150 lines |
| [ ] | 3.2 | CI matrix (macOS + MSYS2) — #26 | ci | ~40 lines |
| [ ] | 3.3 | `--dump-config` CLI flag — #32 | cli | ~25 lines |
| [ ] | 3.4 | `--uninstall` CLI flag — #37 | cli | ~25 lines |

**Estimated LOC**: ~240 new/modified
**Depends on**: Sprint 2 (complete)

### Notes

- BATS tests should cover: `extract_from()`, `build_progress_bar()`, `sanitize()`, theme application, config loading, edge cases (empty input, null fields).
- CI matrix adds macOS and Windows (MSYS2) runners alongside existing ubuntu-latest.
- `--dump-config` helps users debug config issues.
- `--uninstall` replaces the current manual 5-step removal process.

---

## After Sprint 3

Stop and re-evaluate. See what users are actually asking for before building more. The [ROADMAP.md](ROADMAP.md) has a full list of parked ideas that can be promoted based on demand.

---

## Summary

| Sprint | Version | LOC | Items |
|--------|---------|-----|-------|
| 0 | v1.3.1 | ~35 | 5 |
| 1 | v1.4.0 | ~80 | 8 |
| 2 | v1.5.0 | ~52 | 2 |
| 3 | v1.6.0 | ~240 | 4 |
| **Total** | | **~407** | **19** |
