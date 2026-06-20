# Improvement Roadmap & Findings

> Analysis performed June 2026 against v2.19.1. Complements
> [enhancement-backlog.md](enhancement-backlog.md) with strategic context,
> competitive gaps, and new ideas. Every claim below was verified against the
> source on this date (see [Verification notes](#verification-notes)).

> **Update (v2.20.1, 2026-06-20).** A second security + performance gap audit of
> v2.20.0 shipped these *new* fixes (not in the table below): a line-1
> control-sequence injection (line 1 printed with `%b` decoded untrusted
> `\033…` escape text; now real ESC at source + `%s`), `sanitize()` added to the
> uncovered `model`/`vim.mode` fields, **installer** `SHA256SUMS` verification
> (the G1 check extended to `install.sh`/`install.ps1`, the documented update
> path), three background spawns detached so they no longer hold the render's
> stdout pipe open (never-block guarantee), and a fork-free default cost segment
> (`printf -v` + pure-bash `to_cents`). G5 (tag-pinned updates + `--rollback`)
> and the helper-side P1/P2 refactor remain open.

---

## Findings from this review

Concrete, actionable issues surfaced while grounding the analysis:

| # | Finding | Action |
|---|---------|--------|
| F1 | **Test count is stale in the docs.** The suite has **146 `@test` blocks** across 16 `.bats` files, but `README.md`, `.claude-plugin/plugin.json` (description), and `enhancement-backlog.md` all cite **124**. | Update the three docs to 146; consider a CI step that injects the live count so it can't drift again. |
| F2 | **`--benchmark` exists but isn't gated in CI.** Only `tests.yml` (BATS ×3 platforms) and `shellcheck.yml` run; nothing guards the ~285ms Windows render budget that the README advertises. | Add a perf-gate job (see [Structural](#structural--dx-improvements)). |
| F3 | **`--diagnose` partially overlaps existing `--dump-stdin`.** `--dump-stdin` already reports field detection (`rate_limits`, `transcript_path`, nested `model`/`context_window`). | Build `--diagnose` as a superset (env/PATH/OAuth-scope/settings.json checks) rather than a parallel flag. |
| F4 | **Several "new" ideas are already parked.** CONTRIBUTING.md is #51; modular segment architecture is #42–#44 (🟡 partial since v2.19.0); session history / `--stats` is #34/#36. | Cross-referenced below so this doc and the backlog stay consistent. |
| F5 | **Adaptive refresh is not feasible as first imagined.** Claude Code controls invocation cadence via `refreshInterval` in `settings.json`; the script cannot self-schedule. | Dropped from the active list; reframed under [Rejected / not feasible](#rejected--not-feasible). |

---

## Additional gaps & risks

A second pass found gaps the feature-focused sections miss — mostly
**security, quality, and inclusivity** risks. Each is verified against the
source (see [Verification notes](#verification-notes)).

| # | Gap | Evidence | Recommendation | Category |
|---|-----|----------|----------------|----------|
| G1 | **Self-update has no integrity verification** | `perform_self_update` (`statusline-command.sh`) only checks the download is non-empty (`-s`); no checksum or signature. `auto_update` runs it **unattended** in the background. | Publish `SHA256SUMS` per release; verify each staged file before the swap (pure-bash `sha256sum`/`shasum -a 256`, skip gracefully if absent). Reject on mismatch. | Security |
| G2 | **No colourblind-safe theme** | The default metaphor is a green→red heat ramp (`CLR_BAR_LOW/MED/HIGH`, `RAMP_HEX="2ecc40…ff4136"`) — the exact axis ~8% of men (deuteran/protan) can't distinguish. Only `mono`/`NO_COLOR` escape it, but they drop **all** colour. | Add a CVD-safe theme (blue→orange / viridis ramp) where severity reads by a colourblind-distinguishable hue pair; keep the `▲`/text cues so meaning never relies on hue alone. | Accessibility |
| G3 | **Config typos fail silently** | `statusline.conf` is sourced as bash, so `color_theme=…` (US spelling), `show_cost=0` (vs `false`), or `bar_width=abc` are ignored or misbehave with no warning. | A `--check-config` (or fold into `--diagnose`) that flags unknown keys and bad value types against the known set used by `--dump-config`. | Robustness |
| G4 | **Installers lack functional tests** | CI only **syntax**-checks `install.ps1` (`tests.yml` pwsh tokenizer); `install.sh` has none, and no test covers fresh-install / idempotent re-run / `settings.json` merge / Windows path migration. | Add BATS coverage for `install.sh` (merge into a fake `$HOME`, assert idempotency + migration) and a real dry-run for `install.ps1`. Highest-stakes first-touch code. | Testing |
| G5 | **No update rollback; update tracks `main`** | `REPO_RAW` defaults to `…/main`, so `--update` pulls `main` HEAD, not the tagged release; there is no `--rollback` if an update breaks the bar. | Pull from the release tag matching the new `VERSION`; keep the previous `statusline-command.sh` as `.statusline-command.sh.prev` and add `--rollback`. | Reliability |
| G6 | **All failures are silent (no debug log)** | Helper parse errors, OAuth failures, and settings-merge issues vanish by design. `STATUSLINE_PROFILE` times phases but there is no error log. | An opt-in `STATUSLINE_DEBUG=1` that appends diagnostics to `~/.claude/.statusline-debug.log` (size-capped). Pairs with `--diagnose` (F3). | Observability |
| G7 | **English/locale assumptions are hardcoded** | Labels (`dirty`, `stash`, `fast`, `of`, `in`/`out`) and the `usage_label=clock` am/pm format assume English + a 12-hour clock. | Low priority, but at minimum offer a 24-hour clock option; longer term, route user-visible strings through a single label table for translation. | i18n |

**Highest priority of these: G1.** An unattended self-updater that executes
downloaded bash with only a non-empty check is the project's biggest
supply-chain risk. **G2** is the highest-impact inclusivity fix — the core
green→red signal is invisible to a meaningful slice of users today.

---

## Security gaps

The project is already security-conscious (see *Already hardened* below); these
are the **residual gaps** found in this review, beyond G1 (unverified
self-update).

| # | Gap | Evidence | Recommendation | Severity |
|---|-----|----------|----------------|----------|
| S1 | **wget-only OAuth fallback leaks the token via `ps`** | `http_get` passes `--header="Authorization: Bearer $token"` as a **command-line arg** to wget (visible in `ps aux` to any local user). The curl path correctly uses `--config -` (stdin). Acknowledged in the README, but absent from this roadmap and unmitigated. | On wget-only systems, skip the authenticated fetch (treat the OAuth fallback as curl-only), or write a `600`-mode temp header file. Don't pass the token on argv. | Medium (local) |
| S2 | **A malicious `statusline.conf` escalates to persistent RCE via the updater** | `statusline.conf` is sourced as bash (documented "trust like `.bashrc`"), so one line can `export STATUSLINE_REPO_RAW=<attacker>` **and** set `auto_update=true`. Combined with G1 (no checksum), the background updater then fetches + installs + executes attacker bash on **every render**. A one-time file write becomes ongoing code execution. | G1 checksums neutralise most of it. Also: ignore `STATUSLINE_REPO_RAW` unless an explicit opt-in is set, and never let a non-canonical update source be enabled purely from `conf`. | High (if conf is writable) |
| S3 | **`update_ver` is embedded in an OSC 8 hyperlink without the strict allowlist `pr_url` gets** | `pr_url` is sanitised **and** passed through a strict allowlist (`https://` only; rejects space `" ' \ ; ]`). The update notice builds `\033]8;;…/v${update_ver}\033\\` from `update_ver` (read from the update cache) with no equivalent character check. | Apply the same allowlist/`[0-9.]`-only check to `update_ver` before embedding it. Defense-in-depth consistency. | Low |

### Already hardened (verified — do not regress)

- `cwd` is sanitised **before** use in git commands (`sanitize "$cwd"`) — anti directory-traversal.
- `pr_url` strict `https`-only allowlist before OSC 8 embedding.
- Line 2 is printed with `%s` only (never `%b`), so transcript text can't decode into control sequences; two sanitise layers strip ANSI/control/zero-width.
- OAuth token via curl `--config -` (stdin), hidden from `ps`; `umask 077` on all caches; the usage cache stores API JSON, **not** the token.

---

## Performance improvements

The bar render itself is well-optimised (REPLY convention, two git forks,
`NOW_EPOCH` cached). The remaining cost is in the **activity helper**, which is
spawned every render and scales with transcript size.

| # | Improvement | Evidence | Approach |
|---|-------------|----------|----------|
| P1 | **Bound the cold-start transcript parse** | On any cache miss (new session, truncation, rewrite, post-`--uninstall`) the helper runs `readChunk(path, 0, stat.size)` — a **full** parse of a potentially multi-MB JSONL. Only the last 30 tools / 10 agents are ever displayed. | Tail-seek with a size cap for the cold parse; if the file exceeds the cap, parse from a recent offset and accept approximate whole-session tool counts (or track counts cheaply). |
| P2 | **Avoid re-spawning Node when the transcript is unchanged** | `main()` spawns a Node process **every render** even when `mtimeMs`/`size` match (it revives state, re-formats, and rewrites the cache with a fresh epoch). At a low `refreshInterval` this is continuous Node-startup churn. **Caveat:** the re-spawn is currently *load-bearing* — it re-ticks the live elapsed/heat timers for long-running tools. | Move time-derived rendering (elapsed, heat) into the already-running bash path (the spinner is already bash-side; cache `startTime`s), then spawn Node **only** on transcript-mtime change. |
| P3 | **Benchmark the helper, not just the bash render** | `--benchmark` uses a **1-line** canned transcript, so the most size-variable cost (P1) is never measured. | Add a large canned transcript to `--benchmark` and to the F2 CI perf-gate so helper regressions surface. |

---

## Quick Wins (high value, low effort)

Already spec'd in the backlog — should ship first:

| ID | Feature | Why | Effort |
|----|---------|-----|--------|
| B4 | **Alert-only usage mode** — hide bars until ≥80% | Massive noise reduction; one `if` statement | ~5 ln |
| A1 | **Compact countdown** — `~12k to compact` | Users want a number, not just the `│` marker | ~15 ln |
| B3 | **Replace the 100% bar** with countdown-to-reset | At-limit bar is useless; show something actionable | ~10 ln |
| B2 | **Pace-delta text** — `+8%` / `-5%` | Makes the abstract `│` marker instantly readable | ~10 ln |

All four reuse existing primitives: `build_progress_bar()` (B3 budget-style
bar), the `add_seg "..." <pri> <group> <name>` convention at
`statusline-command.sh` (every segment), and the `REPLY`-return hot-path rule.
Keep them fork-free to preserve the render budget.

### Prerequisite: the delta cache

A cluster of 6+ backlog features (A2, A4–A6, B5, C1) all need one primitive: a
small per-session cache recording the **previous** reading (used %, token
totals, cost, timestamp, invocation count). Build it once and the entire
velocity/trend/per-turn family unlocks together.

- **Storage**: `~/.claude/.statusline-delta-cache.<id8>`, mirroring the existing
  per-session activity cache (`.statusline-activity-cache.<id8>`, keyed by the
  stdin `session_id`). Reuse that file's 24h stale-sweep.
- **Shape**: one space-separated line — `epoch used5 used7 tok_in tok_out cost invocations`.
- **Read/compute/write** in the render path is cheap (no fork); deltas are
  integer subtraction. Honour `umask 077` like the other caches.
- **Effort**: ~30 lines, pure bash. This is the single highest-leverage build.

---

## Competitive Gaps to Close

| Gap | Competitor | Recommendation | Principle check |
|-----|-----------|----------------|-----------------|
| Interactive config | ccstatusline (Node.js TUI, 30+ widgets) | `--configure` with a **pure-bash numbered menu** (not a full TUI); writes a minimal diff to `statusline.conf` like the `/configure` slash command already does | ⚠️ A heavy TUI conflicts with "keep it simple / pure bash core". Keep it a menu; any `fzf` use must be optional. |
| Session summary | None do this well | `--summary`: total cost, tokens, time, compactions, tools run, from the transcript + caches | ✅ Read-only, runs on demand. Relates to parked `--stats` (#34/#36). |
| Multi-session view | None | `--dashboard`: aggregate the existing per-session caches (`.statusline-activity-cache.<id8>`, usage cache) into one read-only view a user runs in a spare terminal | ✅ Feasible *because* per-session caches already exist. |

---

## Structural / DX Improvements

| Area | Improvement | Impact |
|------|-------------|--------|
| CONTRIBUTING.md *(already #51)* | "How to add a segment" walkthrough — the `add_seg`/`seg_names[]`/`seg_index_by_name` arch (v2.19.0) is clean enough to document directly | Lowers the barrier for external contributors |
| Fix stale test count *(F1)* | Update README / plugin.json / backlog from 124 → 146; optionally compute it in CI | Doc accuracy / trust |
| CI performance gate *(F2)* | New job runs `--benchmark` and fails if it exceeds a budget (e.g. Linux > 150ms). Needs GNU `date %N`, already used by `--benchmark` | Prevents silent perf regressions |
| `--diagnose` flag *(F3)* | Superset of `--dump-stdin`: also checks Node.js on PATH, transcript path validity, OAuth scope, and the `settings.json` `statusLine` block | Cuts the most common support questions |
| JSON-schema-ish config doc | Document every `statusline.conf` key with type + default (the data already exists for `--dump-config`) | Lower config friction |

---

## New Feature Ideas

Net-new unless tagged; tags point at the existing backlog so the two docs stay in sync.

### Session summary & export *(relates to #34/#36)*

`--summary` prints an end-of-session report (cost, tokens, duration,
compactions, top tools) from the transcript + caches; `--export json|csv` emits
the same data for piping into a log aggregator or cost tracker. The transcript
parser in `statusline-helper.js` already extracts tool/subagent/todo data — most
of the work is aggregation, not parsing.

### Session bookmarks

A `/claude-code-status-bar:mark "<label>"` slash command appends
`<epoch> <label> <cost> <tokens>` to a per-session log; `--summary` then shows
cost-between-marks ("how much did that refactor cost?"). Builds naturally on the
delta cache.

### Theme discovery

`--demo`/`--demo all` already previews themes. Add `colour_theme=random` (pick
one per session, seeded by `session_id`) so users actually *see* the eight
themes instead of staying on `default`. Tiny, pure bash.

### Webhook / notification integration

On a threshold crossing (context > 90%, cost > $X, usage > Y%), fire a one-shot
webhook (Slack/Discord) or OS notification. **Must** run in a background
subshell with a spam-guard cache (principle 2: never block the render). Overlaps
backlog E3 (desktop notification) — could share the same crossing-detection +
spam-guard primitive.

### Segment plugins *(extends #42–#44, currently 🟡 partial)*

Load `~/.claude/statusline-segments.d/*.sh`, each defining one segment via the
existing `add_seg` API. v2.19.0 already made segments named/addressable; this is
the natural next step toward the parked "modular segment architecture" without a
full registry rewrite. Security note: these run as sourced bash (same trust
level as `statusline.conf`) — document that clearly.

---

## Growth & Distribution

| Action | Impact |
|--------|--------|
| **GitHub Actions marketplace action** | Auto-install in CI-driven Claude Code runs (headless); different audience, same tool |
| **Enhance the demo site** | The GitHub Pages demo already exists — add a live theme switcher + config playground to convert browsers into installers |
| **Shorter README** | 600 lines is intimidating — move details into `docs/`, keep README to install + 3 screenshots + links |
| **Video walkthrough** | 60-second GIF showing install → first render → theme change → activity line outperforms any text |

---

## Unique Strengths to Protect

These are what set the project apart — never regress on them:

- Pure bash core (no jq, no compiled binaries)
- Stdin-native rate limits (zero network requests on CC 2.1+)
- Pacing markers with visual `│` on usage bars
- Compaction-aware context warnings (real CC auto-compact maths)
- Never-blocking architecture (all slow ops in background subshells)
- Cross-platform from a single codebase (macOS, Linux, Windows/MSYS2)
- 146 automated tests (16 `.bats` files) on all three platforms, plus ShellCheck

---

## Known Upstream Blockers

Issues in [anthropics/claude-code](https://github.com/anthropics/claude-code/issues) that limit what we can build:

| Issue | What it blocks |
|-------|---------------|
| #30189 | Can't show plan mode or sandbox status |
| #30266 | Bar blank until first response (no session-start invoke) |
| #27929 | CC's built-in "Context low" compresses custom statuslines |
| #29411 | Status bar missing on resumed sessions |
| #32406 | Missing model/effort/context in hooks |

---

## Rejected / not feasible

- **Adaptive refresh interval** *(F5)* — the script is invoked *by* Claude Code
  on its own cadence (`refreshInterval` in `settings.json`); it cannot speed up
  or slow down its own scheduling. Writing `settings.json` to fake it would
  violate the "never touch settings.json" rule. The spinner already animates at
  whatever `refreshInterval` the user sets — that's the only lever available.
- **Full TUI config** — conflicts with the pure-bash / keep-it-simple
  principles. A numbered-menu `--configure` is the feasible compromise.

---

## Execution Plan

The single prioritised plan for everything in this doc (supersedes the earlier
standalone priority list). Sorted into delivery phases; within a phase, do the
higher-priority / lower-effort items first.

**Legend** — **Priority:** P0 (do now) · P1 (next) · P2 (soon) · P3 (later).
**Effort:** XS (<15 ln / <½ day) · S (½–1 day) · M (1–3 days) · L (refactor / >3 days).

### Phase 0 — Security & supply chain *(ship as one hardening release)* — ✅ SHIPPED v2.20.0

Goal: make the self-updater trustworthy before anything else, since it executes
downloaded code unattended.

| ID | Item | Priority | Effort | Depends on | Status |
|----|------|----------|--------|-----------|--------|
| G1 | `SHA256SUMS` per release + verify each staged file before swap | P0 | M | `release.yml` publishes sums | ✅ v2.20.0 — committed `SHA256SUMS` + `scripts/update-sha256sums.sh`; `perform_self_update` verifies, aborts on mismatch, skips gracefully when manifest/tool absent; CI `sha256sum -c` drift guard |
| S2 | Pin/opt-in `STATUSLINE_REPO_RAW`; don't let `conf` enable a non-canonical update source | P0 | S | G1 | ✅ v2.20.0 — source captured pre-conf, re-pinned post-conf; conf can't repoint the updater |
| S1 | Stop passing the OAuth token on wget argv (curl-only auth, or `600` temp header) | P1 | S | — | ✅ v2.20.0 — `0600` temp wgetrc via `--config`; skips auth fetch if unwritable |
| G5 | Pull updates from the release **tag** (not `main`); keep `.prev` + add `--rollback` | P2 | M | G1 | ⬜ next (deferred) |
| S3 | Allowlist `update_ver` before OSC 8 embedding (match `pr_url`) | P2 | XS | — | ✅ already mitigated — the existing `*[!0-9.]*` guard is stricter than `pr_url`'s allowlist (verified, no code change) |

### Phase 1 — Quality, trust & foundations

Goal: inclusivity, regression safety, and the one primitive that unlocks a whole
feature family.

| ID | Item | Priority | Effort | Depends on |
|----|------|----------|--------|-----------|
| G2 | Colourblind-safe theme (CVD ramp; keep `▲`/text cues) | P0 | M | — |
| G4 | Functional installer tests (`install.sh` idempotency/merge/migration; `install.ps1` dry-run) | P1 | M | — |
| F1 | Fix the 124→146 test-count drift (README, plugin.json, backlog) | P1 | XS | — |
| P3 | Add a large-transcript case to `--benchmark` | P1 | S | — |
| F2 | CI perf-gate job using `--benchmark` (incl. P3 case) | P1 | M | P3 |
| — | **Delta cache** primitive (`.statusline-delta-cache.<id8>`) | P1 | M | — |
| B4 | Alert-only usage mode (`usage_alert_threshold`) | P1 | XS | — |
| A1 | Compact countdown (`~12k to compact`) | P1 | S | — |

### Phase 2 — Support burden & UX

Goal: cut the common support questions and finish the usage/pacing story.

| ID | Item | Priority | Effort | Depends on |
|----|------|----------|--------|-----------|
| F3 | `--diagnose` (superset of `--dump-stdin`) | P1 | M | — |
| G3 | Config key/type validation — fold into `--diagnose` | P1 | S | F3 |
| G6 | `STATUSLINE_DEBUG=1` error log | P2 | S | F3 |
| B3 | Replace the useless 100% usage bar with a reset countdown | P2 | S | — |
| B2 | Pace-delta text (`+8%` / `-5%`) | P2 | S | — |
| — | `--summary` session report (+ `--export json\|csv`) | P2 | M | delta cache |
| — | CONTRIBUTING.md ("how to add a segment") *(#51)* | P2 | S | — |
| — | Config reference doc (every key + type + default) | P2 | S | — |
| — | Interactive `--configure` (pure-bash menu) | P2 | M | — |
| — | Shorter README (move detail into `docs/`) | P2 | S | — |

### Phase 3 — Performance refactor & reach

Goal: the deeper helper refactor plus growth and long-tail features.

| ID | Item | Priority | Effort | Depends on |
|----|------|----------|--------|-----------|
| P1 | Bound the cold-start transcript parse (tail-seek + cap) | P2 | M | — |
| P2 | Move elapsed/heat to bash; spawn Node only on transcript change | P2 | L | P1 |
| — | Session bookmarks (`/mark`) | P3 | M | delta cache, `--summary` |
| — | Theme discovery (`colour_theme=random`) | P3 | XS | — |
| — | Webhook / OS notification on threshold (shares E3 primitive) | P3 | M | delta cache |
| — | Segment plugins (`segments.d/*.sh`) *(#42–44)* | P3 | L | — |
| — | GitHub Actions marketplace action | P3 | M | — |
| — | Enhance demo site (theme switcher + playground) | P3 | M | — |
| G7 | 24-hour clock option (full i18n later) | P3 | S | — |
| — | Video walkthrough | P3 | S | — |

### At a glance

- **Do-now (P0):** G1, S2, G2 — two security, one accessibility.
- **Biggest leverage:** the **delta cache** (one M unlocks A2/A4–A6/B5/C1) and
  **F3 `--diagnose`** (absorbs G3 + G6).
- **Cheapest wins (XS):** F1, B4, S3, `colour_theme=random`.
- **Heaviest single item (L):** P2 (Node-spawn refactor) and segment plugins —
  schedule deliberately, not opportunistically.

### Suggested first three PRs

1. **Hardening release** — G1 + S2 + S1 (+ S3 while in the file). One coherent
   security story; unblocks safe `auto_update`.
2. **Accessibility + accuracy** — G2 colourblind theme, F1 test-count fix,
   and the `--demo` preview for the new theme.
3. **Foundations** — delta cache + B4 + A1, landing the first user-visible
   "fuel gauge" features on top of the new primitive.

---

## Verification notes

Checked against the working tree at v2.19.1 on 2026-06-18:

- **CLI flags present** (`statusline-command.sh`): `--help`, `--version`,
  `--check-update`, `--update`, `--dump-stdin`, `--dump-config`, `--uninstall`,
  `--benchmark`, `--demo`. **Absent** (so genuinely new): `--diagnose`,
  `--summary`, `--export`, `--stats`, `--configure`, `--dashboard`.
- **Tests**: 146 `@test` blocks across 16 `.bats` files in `tests/`.
- **CI** (`.github/workflows/`): `tests.yml` (BATS on ubuntu/macos/windows-MSYS2),
  `shellcheck.yml`, `release.yml`. No performance gate.
- **Segment API**: `add_seg "content" priority [group] [name]` with stable names
  confirmed throughout `statusline-command.sh` — segment-plugin idea is viable.
- **Per-session caches**: activity cache keyed by `session_id`
  (`.statusline-activity-cache.<id8>`) confirms the delta-cache + dashboard designs.
- **Line counts**: `statusline-command.sh` ~2286, `README.md` 600.
- **No `CONTRIBUTING.md`** in the tree (matches backlog #51).
- **Self-update** (`perform_self_update`): downloads via `http_get`, checks only
  `-s` (non-empty), swaps in place — **no checksum/signature**. `REPO_RAW`
  defaults to the `main` branch, not the release tag. No rollback path.
- **Install CI**: `tests.yml` runs a pwsh **tokenizer** check on `install.ps1`
  only; no functional installer test for either script.
- **Themes**: bar colours are green/yellow/red (`CLR_BAR_LOW/MED/HIGH`) with a
  green→red `RAMP_HEX`; no CVD-safe palette. `mono`/`NO_COLOR` drop all colour.
- **Config**: sourced as bash with no key/value validation.
- **OAuth fetch**: curl uses `--config -` (token off argv); the **wget fallback**
  passes `--header="Authorization: Bearer …"` on argv (S1). Usage cache stores
  API JSON only, not the token.
- **OSC 8 inputs**: `pr_url` is sanitised + strict-`https` allowlisted (well
  defended); `update_ver` is embedded without the same allowlist (S3).
- **`cwd`** is sanitised before git use (anti-traversal). Line 2 prints via `%s`.
- **Activity helper**: full parse from offset 0 on cache miss (P1); Node
  re-spawned every render, rewriting the cache with a fresh epoch (P2);
  `--benchmark` uses a 1-line transcript (P3).

*Last updated: 2026-06-18*
