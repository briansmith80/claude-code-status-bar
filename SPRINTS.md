# Sprint Plan

Lean sprint plan derived from [ROADMAP.md](ROADMAP.md). Three focused releases, then re-evaluate based on user feedback.

> **Methodology**: Feature-based releases via GitHub Milestones (not time-boxed). Each milestone ships when complete. Bug fixes ship immediately as patch releases.
>
> **Versioning**: Semver. Major (x.0.0) for breaking changes or major features. Minor (x.y.0) for new features. Patch (x.y.z) for bug fixes.

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

## Sprint 3: v2.0.0 — Stdin-Native, Live Activity, Plugin Marketplace :white_check_mark:

**Theme**: Close the feature gap with claude-hud while keeping our pure-bash identity.

**Status**: Complete.

| | # | Item | Type | Effort |
|---|---|------|------|--------|
| [x] | 3.1 | Stdin-native rate limits | feature | ~40 lines |
| [x] | 3.2 | Updated schema parsing (old + new) | feature | ~15 lines |
| [x] | 3.3 | Node.js transcript helper | feature | ~260 lines (new file) |
| [x] | 3.4 | Live activity integration in bash | feature | ~30 lines |
| [x] | 3.5 | Two-line layout | feature | ~5 lines |
| [x] | 3.6 | Plugin marketplace files | infra | ~100 lines (new files) |
| [x] | 3.7 | `--no-optional-locks` on git | fix | ~1 line (replace_all) |
| [x] | 3.8 | Installer update (download helper) | enhancement | ~4 lines |

**Estimated LOC**: ~455 new/modified
**Depends on**: Sprint 2 (complete)

### Notes

- Stdin rate limits skip OAuth entirely when `rate_limits` key present in stdin JSON.
- `statusline-helper.js` uses SHA256-keyed disk cache, only re-parses on transcript change.
- Activity line is enabled by default (`show_activity=true`), disable in `statusline.conf`.
- Plugin slash commands: `/claude-code-status-bar:setup` and `/claude-code-status-bar:configure`.

---

## Patch releases (v2.0.x)

Bug-fix and doc-cleanup releases shipped between v2.0.0 and the next milestone:

- **v2.0.1** — `extract_block()` regex fix for nested JSON (1M-context models displayed 0%).
- **v2.0.2** — Context-window suffix renders as `1M` instead of `1000k` for million-token windows.
- **v2.0.3** — `.claude-plugin/plugin.json` version sync, doc cleanup, release-checklist hardening.

---

## Sprint 4: v2.1.0 — Testing & CLI

**Theme**: Protect what we've built and add practical CLI features.

| | # | Item | Type | Effort |
|---|---|------|------|--------|
| [ ] | 4.1 | BATS test scaffold — #25 | testing | ~150 lines |
| [ ] | 4.2 | CI matrix (macOS + MSYS2) — #26 | ci | ~40 lines |
| [ ] | 4.3 | `--dump-config` CLI flag — #32 | cli | ~25 lines |
| [ ] | 4.4 | `--uninstall` CLI flag — #37 | cli | ~25 lines |

**Estimated LOC**: ~240 new/modified
**Depends on**: Sprint 3 (complete)

---

## After Sprint 4

Stop and re-evaluate. See what users are actually asking for before building more. The [ROADMAP.md](ROADMAP.md) has a full list of parked ideas that can be promoted based on demand.

---

## Summary

| Sprint | Version | LOC | Items |
|--------|---------|-----|-------|
| 0 | v1.3.1 | ~35 | 5 |
| 1 | v1.4.0 | ~80 | 8 |
| 2 | v1.5.0 | ~52 | 2 |
| 3 | v2.0.0 | ~455 | 8 |
| 4 | v2.1.0 | ~240 | 4 |
| **Total** | | **~862** | **27** |
