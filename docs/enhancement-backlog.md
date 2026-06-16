# Status Bar — Backlog & Planning

The single living planning doc for claude-code-status-bar: what we are, the
principles we hold to, the competitive landscape, and the candidate work that
remains. It supersedes the former `ROADMAP.md` and `SPRINTS.md` (both retired —
everything they planned shipped). **Shipped history lives in
[CHANGELOG.md](../CHANGELOG.md)**; the project ships feature-based,
**feedback-driven** releases (latest **v2.19.1**) — promote items from here on
demand, not in list order.

---

## Principles

1. **Stay pure bash core** — no jq, no compiled binaries. Optional Node.js helper for features that need it (transcript parsing). The core status bar works without Node.js.
2. **Never block the status bar** — network/slow ops run in background subshells with caching; the render only ever reads caches.
3. **Config survives updates** — `statusline.conf` is never overwritten.
4. **Cross-platform first** — macOS, Linux, and Windows/MSYS2.
5. **Security by default** — sanitize untrusted input, hide tokens, restrictive permissions, `%s`-only printing of transcript-derived text.
6. **Keep it simple** — resist feature creep. If it needs a different language, it's a different project.

## Our unique strengths

- **Pure bash core** — no jq, no compiled binaries; optional Node.js helper for live activity.
- **Stdin-native rate limits** — reads usage data directly from Claude Code stdin (zero network requests).
- **Pacing markers** on usage progress bars (unique to us).
- **Colourful live activity line** — running tools/agents with a spinner, heat-coloured elapsed times, completion flash, gradient todo bar, stale fade; theme-aware and NO_COLOR-safe (v2.7.0).
- **Compaction-aware context warnings** — mirrors Claude Code's real auto-compact maths, not a guessed percentage (v2.6.0).
- **Subagent panel renderer** — Task-tool agent rows with elapsed, tokens, tok/s (v2.5.0).
- **Clickable PR segment** — OSC 8 hyperlink to the pull request (v2.9.0).
- **Configurable multi-line layout** — assign any segment to any of up to three lines via `layout` presets or `line1`/`line2`/`line3` token lists; the live activity line is a placeable token; `icon_set=modern` refreshes the glyphs (v2.19.0).
- **Fast everywhere** — ~285ms/render on Windows after the v2.8.0 fork overhaul, sub-100ms elsewhere; `--benchmark` to verify.
- **Plugin marketplace** — installable via `/plugin install`, with setup/configure slash commands.
- **One-line installers** (bash + native PowerShell) with background update checks.
- **External config file** that survives updates; **priority-based truncation** for narrow terminals; **security hardening** (umask 077, stdin token passing, ANSI sanitization).

## Competitive landscape

| Project | Language | Key Differentiator |
|---------|----------|--------------------|
| **claude-code-status-bar (ours)** | Bash + Node.js helper | Pure bash core, stdin-native limits, pacing markers, live activity, multi-line layout, plugin marketplace |
| [claude-hud](https://github.com/jarrodwatts/claude-hud) | TypeScript | 13k+ stars, plugin-native, transcript parsing, multi-line layout |
| [ccstatusline](https://github.com/sirmalloc/ccstatusline) | Node.js | Powerline styling, interactive TUI config, 30+ widgets |
| [claude-powerline](https://github.com/Owloops/claude-powerline) | Bash | Vim-style powerline, 10+ bar styles, 6 themes |
| [claude_monitor_statusline](https://github.com/gabriel-dehan/claude_monitor_statusline) | Ruby | Plan-specific limits, message count |
| [claude-code-usage-bar](https://github.com/leeguooooo/claude-code-usage-bar) | Python | Cost depletion estimate, P90 budget tracking |
| [CCometixLine](https://github.com/Haleclipse/CCometixLine) | Rust | High-performance, TUI config |
| [rz1989s/claude-code-statusline](https://github.com/rz1989s/claude-code-statusline) | Bash | 4-line layout, 28 themes, 77 tests |

---

## Outstanding work — token conservation & usage awareness

> **Goal**: make the bar a "fuel gauge" that helps users conserve tokens, avoid
> hitting limits, and make smarter decisions — surface surprise compaction,
> dodge rate limits, and spend wisely.

**Status legend:** ✅ shipped · 🟡 partial (something related shipped; the
specific idea isn't fully done) · ⬜ pending

### Shipped baseline (the 2026-03-05 "enhancements" effort — done)

The original status-bar-enhancements brainstorm + plan are **fully delivered**:
auto-hide (`auto_hide`), ahead/behind + stash segments, cost rate
(`show_cost_rate`), context warnings (`context_warn_threshold=auto` + `▲`), icon
mode (`use_icons`), 8 colour themes (`colour_theme`, truecolour), priority
truncation (`enable_truncation`), and segment grouping (`use_groups`). Later
releases added pacing markers, countdown usage labels, the live activity line,
the subagent panel, gradient bars, the multi-line layout, and `icon_set=modern`.
The tables below are what remains **unbuilt** (plus a few partials).

### Theme A — Context window awareness

| ID | Idea | Status | Effort | Notes (issue ref) |
|----|------|--------|--------|-------|
| A1 | **Compact countdown** `~12k to compact` | 🟡 | ~15 ln | `│` marker + `▲` within 20k tokens ship; the numeric "tokens remaining" text doesn't. **P0**. (#58) |
| A2 | **Compact-detection flash** `compacted` | ⬜ | ~15 ln | If used% drops >20% between runs, flash `compacted`. Needs the delta cache. (#65) |
| A3 | **Compact buffer zone on the bar** (dim last ~16.5%) | 🟡 | ~10 ln | The compact-point `│` marker exists; dimming the buffer *zone* doesn't. (#61) |
| A4 | **Messages-remaining estimate** `~12 msgs left` | ⬜ | ~25 ln | Track invocation count + token totals for avg tokens/turn. Needs delta cache. |
| A5 | **Token-velocity arrow** `ctx 45% ^` | ⬜ | ~15 ln | Delta of `total_input_tokens` → `^`/`v`/`-`. Needs delta cache. |
| A6 | **Per-turn token delta** `last: 8.2k` | ⬜ | ~15 ln | Tokens for the last exchange (CC issue #29600). Needs delta cache. |

### Theme B — Usage-limit intelligence

| ID | Idea | Status | Effort | Notes (issue ref) |
|----|------|--------|--------|-------|
| B1 | **Time-to-limit estimate** `limit in 1.2h` | ⬜ | ~20 ln | Burn extrapolation from usage vs pacing target — distinct from today's time-to-**reset** countdown. **P0**. (#59) |
| B2 | **Pace-delta text** `+8%` / `-5%` | ⬜ | ~10 ln | Numeric distance from the `│` pacing marker (green behind, yellow/red ahead). |
| B3 | **Rate-limit countdown at 100%** | 🟡 | ~10 ln | `usage_label=countdown` already shows time-to-reset; the "replace the useless 100% bar" special-case isn't there. |
| B4 | **Alert-only usage mode** (hide bars until a threshold) | ⬜ | ~5 ln | `usage_alert_threshold` (default 80). **P0** — one `if`, big noise reduction. (#30) |
| B5 | **Usage-velocity arrow** `5hr 73%^` | ⬜ | ~15 ln | Utilisation delta-per-minute → arrow. Needs delta cache. |
| B6 | **Remaining-framing toggle** `5hr 27% left` | ⬜ | ~5 ln | `usage_framing=remaining` vs `used`. Trivial inversion. |

### Theme C — Cost intelligence

| ID | Idea | Status | Effort | Notes (issue ref) |
|----|------|--------|--------|-------|
| C1 | **Cost velocity + trend arrow** `$2.40/hr ^` | 🟡 | ~20 ln | `show_cost_rate` ships; the 5-min-vs-15-min trend arrow doesn't (needs a timestamped cost cache). (#29) |
| C2 | **Session budget bar** `budget [####--] $3/$5` | ⬜ | ~15 ln | Cost as a bar vs `session_budget`. Reuses `build_progress_bar()`. (#28) |
| C3 | **Cost-efficiency ratio** `$0.03/+line` | ⬜ | ~10 ln | Cost per added line; show only when both non-trivial. |
| C4 | **Cost sparkline** `cost _/~\` | ⬜ | ~25 ln | 6–8 char Unicode-block sparkline from a ring buffer. |
| C5 | **Cost-milestone flash** | ⬜ | ~15 ln | One-time colour pulse at `$1/$5/$10/$25` (`cost_milestones`). |
| C6 | **Daily cost tracking** `today:$3.45` | ⬜ | ~30 ln | Append per-session cost to a daily log; sum today's entries. (#35) |

### Theme D — Cache & efficiency metrics

| ID | Idea | Status | Effort | Notes (issue ref) |
|----|------|--------|--------|-------|
| D1 | **Cache hit ratio** `cache:87%` | ⬜ | ~18 ln | `cache_read / (cache_read + cache_creation)` from the API. (#7) |
| D2 | **Cache-utilisation grade** `cache:A` | ⬜ | — | Letter grade — alt display for D1. |
| D3 | **Token efficiency** `412 tok/$` | ⬜ | — | Output tokens per dollar (have `show_tokens`). |

### Theme E — Progressive warnings

| ID | Idea | Status | Effort | Notes (issue ref) |
|----|------|--------|--------|-------|
| E1 | **Three-tier context severity** (95% → "COMPACT NOW") | 🟡 | ~15 ln | green/yellow/red + `▲` ship; the explicit 95% critical tier with text doesn't. (#62) |
| E2 | **Session-duration colour escalation** | ⬜ | — | Colour duration by age (<30m default, 30m–2h yellow, >2h red). |
| E3 | **Desktop notification on threshold crossing** | ⬜ | ~30 ln | One-shot OS notification (osascript / notify-send / BurntToast); spam-guarded via cache. |

### Theme F — Behavioral nudges (subtle)

| ID | Idea | Status | Effort | Notes (issue ref) |
|----|------|--------|--------|-------|
| F1 | **"Context high" hint** `ctx 82% /compact?` | ⬜ | — | One-time hint per threshold crossing; not nagging. |
| F2 | **Model cost-tier indicator** `$`/`$$`/`$$$` | 🟡 | — | Model tier *colouring* ships; the relative-cost `$$` glyph doesn't. |

### Shared infrastructure: the delta cache

A cluster of ideas (A2, A4, A5, A6, B5, C1) all need one primitive: a small
per-session cache recording the **previous** reading (used %, token totals,
cost, timestamp, invocation count) so the current run can compute a delta. Build
it once — pure-bash, keyed by `session_id` like the activity cache, TTL-swept —
and the whole "velocity/trend/per-turn" family unlocks together.

### Suggested first slice

Highest value, lowest effort, unique: **A1** (compact countdown), **B1**
(time-to-limit), **B4** (alert-only usage mode), **B3** (cleaner 100% state).
**B2** (pace delta) and **D1** (cache ratio) are strong P1 follow-ons.

---

## Other parked ideas (promote on demand)

Not planned, not promised — promote if users ask. The token-conservation issues
already tracked in Themes A–F above: **#7**→D1, **#28**→C2, **#29**→C1,
**#30**→B4, **#35**→C6, **#58**→A1, **#59**→B1, **#61**→A3, **#62**→E1,
**#65**→A2. The remaining distinct ideas:

| Idea | Status | Source |
|------|--------|--------|
| Fish-style directory truncation (`c/l/w/…` abbreviation) | 🟡 | #12 — `dir_style=basename`/`auto` ship; the per-component abbreviation specifically doesn't |
| API wait-time segment (`cost.total_api_duration_ms`) | ⬜ | #5 |
| Separator config / styles | ⬜ | #11, #20 (the powerline separator from v2.15.0 was removed in v2.18.0) |
| Display `workspace.project_dir` | ⬜ | #15 |
| Per-segment icon overrides | ⬜ | #17 (icons are global: `use_icons` + `icon_set`) |
| Overflow indicator (signal dropped segments) | ⬜ | #18 (truncation currently drops silently) |
| Progress-bar styles (dots, line, ascii) | ⬜ | #19 (only `█`/`░` today) |
| Right-aligned segments | ⬜ | #22 |
| Session history / `--stats` | ⬜ | #34, #36 |
| `--test` CLI flag | ⬜ | #38 |
| Plan-aware limits | ⬜ | #39 |
| Modular segment architecture | 🟡 | #42–#44 — v2.19.0 added named/addressable segments (`add_seg` names, `seg_index_by_name`, layout tokens); a full registry/plugin split doesn't exist |
| CONTRIBUTING.md / JSON-schema docs | ⬜ | #51 |

---

## Known Claude Code issues affecting the statusline

Open issues in [anthropics/claude-code](https://github.com/anthropics/claude-code/issues):

| Issue | Impact |
|-------|--------|
| [#30189](https://github.com/anthropics/claude-code/issues/30189) Expose plan_mode/sandbox | Can't show plan mode or sandbox status |
| [#30266](https://github.com/anthropics/claude-code/issues/30266) Invoke on session start | Status bar blank until first response |
| [#27929](https://github.com/anthropics/claude-code/issues/27929) Disable built-in content | "Context low" compresses custom statuslines |
| [#29411](https://github.com/anthropics/claude-code/issues/29411) Not rendered on resume | Status bar missing on resumed sessions |
| [#32406](https://github.com/anthropics/claude-code/issues/32406) Expand hook data | Missing model, effort, context in hooks |

(Resolved: [#31415](https://github.com/anthropics/claude-code/issues/31415) — `effort.level` is in stdin since CC 2.1.133; the effort segment shipped in v2.2.0.)

### Newly available stdin fields (CC 2.1.145+, unbuilt)

- `workspace.repo.{host,owner,name}`: repo identity without parsing `git remote`.
- `session_name`, `output_style.name`, `thinking.enabled`, `cost.total_api_duration_ms`: minor candidates.
- A `context_label=until-compact` style showing the same "% until auto-compact" number Claude Code's own UI uses, and a compaction counter.
- `COLUMNS`/`LINES` env vars (CC 2.1.153+): `COLUMNS` already drives truncation width; `LINES` could drive adaptive layouts.
- **Unused context/cost fields:** `context_window.{total_input_tokens, total_output_tokens, remaining_percentage}`, `current_usage.{input_tokens, cache_creation_input_tokens, cache_read_input_tokens}`, `cost.total_api_duration_ms`, `exceeds_200k_tokens` — these back most of Themes A–D.

---

## Key research numbers (grounding)

| Metric | Value | Source |
|--------|-------|--------|
| Auto-compact trigger | ~83.5% of window (~167K of 200K) | claudefa.st |
| Compact buffer reserved | ~33K tokens (16.5%) | official docs |
| File-read token overhead | 1.7–3.15× multiplier | CC issue #20223 |
| grep vs agentic search | ~100 vs ~40,000 tokens | community analysis |
| MCP idle overhead (50+ tools) | ~77K tokens (8.7K with Tool Search) | official docs |
| Session token growth | ~5K start → ~50K @30m → ~150K+ @2h | restato.github.io |
| Avg session cost | light $0.10–0.50 · heavy $2–10 | official docs |

## Differentiators (what competitors lack)

Pacing markers **with pace delta**; compact **countdown** and **detection**;
**time-to-limit**; **messages-remaining**; **cache hit ratio** — and all of it in
**pure bash** (no jq / Node / Python), cross-platform.

## Sources

- [How Claude Code works](https://code.claude.com/docs/en/how-claude-code-works) · [Manage costs](https://code.claude.com/docs/en/costs) · [Status line](https://code.claude.com/docs/en/statusline)
- [Context buffer management](https://claudefa.st/blog/guide/mechanics/context-buffer-management) · [Token economy](https://restato.github.io/blog/claude-code-token-economy/)
- CC issues: [#13579](https://github.com/anthropics/claude-code/issues/13579) (token-wasting patterns) · [#20223](https://github.com/anthropics/claude-code/issues/20223) (file-load overhead) · [#29604](https://github.com/anthropics/claude-code/issues/29604) (statusLine API) · [#31564](https://github.com/anthropics/claude-code/issues/31564) (per-session tokens) · [#18705](https://github.com/anthropics/claude-code/issues/18705) (hard-stop without warning)
- Prior art: [ccstatusline](https://github.com/sirmalloc/ccstatusline) · [ccburn](https://github.com/JuanjoFuchs/ccburn) · [Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor)
