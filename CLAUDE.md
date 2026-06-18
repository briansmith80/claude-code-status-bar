# Claude Code Status Bar — Project Guide

## What this is

A configurable status bar for Claude Code. Pure bash core with optional Node.js helper for live activity. Cross-platform (macOS, Linux, Windows/MSYS2).

## Architecture

```
VERSION                    # Single source of truth for version (bump ONLY this file for releases)
statusline-command.sh      # The runtime script — installed to ~/.claude/
statusline-helper.js       # Optional Node.js transcript parser — installed to ~/.claude/
statusline-subagent.js     # Optional Node.js subagent panel renderer — installed to ~/.claude/
install.sh                 # Installer/updater — downloads script + helpers + VERSION from GitHub
install.ps1                # Windows PowerShell installer/updater — native JSON settings merge
.claude-plugin/plugin.json # Plugin manifest for marketplace distribution
.claude-plugin/marketplace.json # Marketplace catalog (required by /plugin marketplace add)
commands/setup.md          # Slash command: /claude-code-status-bar:setup
commands/configure.md      # Slash command: /claude-code-status-bar:configure
docs/assets/               # README images + their generators (hero, animated hero-demo.svg/.gif, banner pair, social card)
docs/assets/themes/        # per-theme --demo preview SVGs + generate-theme-demos.sh (captures real --demo output) + ansi-to-svg.js
README.md                  # User-facing docs
```

### Installed files (at ~/.claude/)

| File | Purpose | Overwritten on update? |
|------|---------|----------------------|
| `statusline-command.sh` | The script Claude Code runs | Yes |
| `statusline-helper.js` | Node.js transcript parser (optional) | Yes |
| `statusline-subagent.js` | Node.js subagent panel renderer (optional) | Yes |
| `.statusline-version` | Local copy of VERSION | Yes |
| `statusline.conf` | User config overrides | **Never** (created from the template on first install only) |
| `statusline.conf.example` | Commented reference template (all options, all commented) | Yes |
| `.statusline-update-cache` | Update check cache (timestamp + version) | Cleared on update |
| `.statusline-usage-cache` | Usage API response cache (JSON) | Auto-refreshes every 10 min |
| `.statusline-activity-cache` | Transcript activity cache (JSON) | Auto-refreshes every call |
| `.statusline-transcript-cache/` | Parsed transcript cache (by SHA256) | Auto-invalidates on change |

## Key design decisions

- **No jq** — Uses bash regex (`BASH_REMATCH`) for JSON parsing. Windows/MSYS2 users don't have jq.
- **Bash 3.2 minimum** — Must work on stock macOS. No associative arrays, no `readarray`, no `${var,,}`.
- **Background update check** — Fetches VERSION from GitHub every 6h in a background subshell. Never blocks the status bar. The `↑ <version>` notice is an OSC 8 link to that release's notes (reuses the PR segment's hyperlink form; gated on `pr_link`).
- **`--update` self-update (v2.11.0)** — Downloads `statusline-command.sh` + both helpers from `REPO_RAW` to `.<name>.update.$$` staging files beside their targets, then renames them in only after *all* downloads succeed (so a failed fetch changes nothing). `statusline-command.sh` moves first because it is the running file: rename is safe while running (the live shell keeps its original inode), and going first means a Windows in-use failure aborts before any version mismatch. Never touches `settings.json`, and never *overwrites* `statusline.conf` — but since v2.18.1, after the script+helpers swap it best-effort refreshes `statusline.conf.example` and seeds `statusline.conf` from it **only if absent** (so `--update`/`auto_update`-only users still get the commented starter config; a failed template fetch never affects the update). `REPO_RAW` is overridable via `STATUSLINE_REPO_RAW` (fork, or `file://` for tests). The installer re-run remains the fallback for installs too old to have the flag.
- **`auto_update` (opt-in, v2.12.0)** — Shares `perform_self_update` with `--update`. When `auto_update=true` and `check_for_update` has flagged a newer version (`update_available`, from the cache), `run_auto_update` installs it. Detached as `run_auto_update ... >/dev/null 2>&1 </dev/null &` — unlike the version probe, the download is long, so it must not hold the render's stdout (else the bar blocks until the pipe closes). A lock dir (`.statusline-autoupdate.lock`, atomic `mkdir`, 10-min stale sweep) serialises parallel sessions. Default off so the tool never self-replaces unasked. `STATUSLINE_AUTOUPDATE_SYNC` runs it inline for deterministic tests. The trigger sits after the management-flag dispatch so `--dump-config`/`--uninstall`/`--benchmark` never fire it.
- **External config** — User overrides go in `statusline.conf`, sourced after defaults. Survives updates.
- **Single version source** — Only `VERSION` file needs bumping. Installer downloads it; script reads it at runtime.
- **Sanitize untrusted strings** — Branch names, paths, and worktree names are stripped of ANSI escapes before output.
- **Colour themes via CLR_* variables** — All ANSI codes use theme variables set by `apply_theme()`. Eight built-in themes spread across a saturation/temperature ladder so none read alike: default (bold primary), dracula (neon), tokyo-night (deep midnight blue), catppuccin (soft warm pastel), solarized (earthy), nord (muted cool steel), matrix (monochrome digital-rain green, separated by brightness not hue), mono (greyscale). The six named themes store **hex palettes** and render in **24-bit truecolour** (`38;2;r;g;b`) when available, falling back to the nearest **xterm-256** colour (`38;5;N`) otherwise. Truecolour is detected from `$COLORTERM` (override `STATUSLINE_TRUECOLOR=1`/`0`); `tc_clr()`/`cube_index()`/`apply_palette()` do the pure-bash conversion (single source of truth = the hex). `default` stays basic-ANSI (tracks the terminal's palette), `mono` stays empty. Supports NO_COLOR standard.
- **Model tier coloring** — Model name colour varies by tier (Haiku=green, Sonnet=yellow, Opus=orange, Fable/Mythos=purple) via a case statement. Respects NO_COLOR and mono theme.
- **Auto-compact awareness** — Claude Code auto-compacts at (autocompact window - 33000) tokens and warns itself 20000 tokens earlier (constants extracted from CC 2.1.170; display-only, drift is cosmetic). The context bar carries a `│` marker at the compact point and `context_warn_threshold=auto` (default) fires `▲` within 20k tokens of it, using `total_input_tokens`. Resolution order mirrors CC: `CLAUDE_CODE_AUTO_COMPACT_WINDOW` env > settings.json `autoCompactWindow` > full window; `DISABLE_AUTO_COMPACT`/`DISABLE_COMPACT` remove the marker and fall back to a raw 80% rule. The `▲ 200k+` segment was retired in v2.6.0 (long-context premium pricing was abolished March 2026).
- **Array-based segments** — Segments are built into `seg_vals[]`/`seg_pris[]`/`seg_groups[]` arrays for truncation and grouping support. The inter-segment separator is `seg_sep` (a double space).
- **Gradient bars + theme preview** — `bar_gradient` is **on by default** (`true`); `false` gives flat single-colour bars. It colours the filled progress-bar cells with a **smooth per-cell** gradient: each cell's RGB is linearly interpolated across four stops, truecolour per cell with a nearest-256 fallback (pure-bash integer lerp, no forks — `--benchmark` shows no measurable cost vs flat). `bar_gradient=true` uses the theme's four ramp stops (the hexes are stashed in `RAMP_HEX` by `apply_palette()`/the default theme — note the `default` theme's ramp is itself a green→red "heat" ramp); `bar_gradient=heat` uses a fixed green→yellow→orange→red ramp regardless of theme. No-op under mono/NO_COLOR (gated on `CLR_RESET` being non-empty). `--demo [theme|all]` previews themes by re-invoking the script per theme with a `STATUSLINE_THEME` env override and the `--benchmark` canned payload — no recursion, no conf changes. The env value is captured into `_env_theme` *before* the conf is sourced and applied after, so a stray `STATUSLINE_THEME` line in `statusline.conf` can't clobber it (env-only knob; `colour_theme` is the conf key). (The `nerd_font`/`powerline` glyph options from v2.15.0 were later removed — they needed a patched terminal font and added noise.)
- **set -e safety** — Git commands that may fail (e.g., `rev-list` with no upstream) use `|| fallback` pattern to prevent script death.
- **Usage limits: stdin-native + OAuth fallback** — Prefers `rate_limits.five_hour` and `rate_limits.seven_day` from stdin (CC >= 2.1, zero-cost, real-time). Falls back to OAuth API (`api.anthropic.com/api/oauth/usage`) for older CC versions. OAuth uses background subshell, Keychain/credentials.json, 10-min cache.
- **Live activity via transcript** — Optional Node.js helper (`statusline-helper.js`) parses Claude Code's JSONL transcript for tool calls, subagent status, and todo progress. Runs in background with a SHA256-keyed disk cache that stores the parse state plus a byte offset, so each run parses only newly appended lines (incremental). Completed/failed items age out of the display after 5 minutes; tool counts cover the whole session. Only activates when `transcript_path` is in stdin and Node.js is available.
- **Configurable multi-line layout (v2.19.0)** — Segments build into the `seg_*` arrays as before, each now carrying a stable name (`seg_names[]`, set via `add_seg`'s 4th arg; looked up by `seg_index_by_name`). A `layout` preset (`classic`/`three-line`/`stacked`) expands to per-line token strings `lp1/lp2/lp3`; explicit `line1`/`line2`/`line3` conf values override per line (detected with `${lineN+s}` so an empty `line2=""` hides that row vs an unset one falling back to the preset). `classic` line 1 is the sentinel `__ALL__` (every segment in add order) so the **default output stays byte-identical** and new segments auto-appear. `parse_line` tokenises each line (whitespace split, `set -e`-safe — unknown/disabled tokens skipped, deduped across lines, first occurrence wins) into per-line index plans + an `activity` flag. `assemble_line` runs the dir auto-collapse, priority truncation, and `use_groups` bracketing **scoped per line** (replacing the old single-pass blocks; the forking `calc_total_width` is gone — totals are summed inline). The render loop prints each non-empty line, a newline only *between* printed lines (never trailing, never a blank row — preserving "activity only when there's data"). **dir/branch are split** into separate `dir`/`branch` tokens but the assembler emits the attached " on <icon>branch" form (no separator) when `branch` immediately follows `dir`, so the combined look is preserved; `branch_attached_w` keeps the width maths exact. Activity stays its own `%s` print path (never `%b`-concatenated). Disable activity with `show_activity=false`. **Caveat:** `lineN` values with spaces must be quoted in `statusline.conf` (it's sourced as shell).
- **Icon sets (v2.19.0)** — `apply_icon_set()` sets `ICON_*` globals for the glyphs that *differ* between `icon_set=classic` (default, the original icons) and `icon_set=modern` (dir `↱`, branch `⑂`, lines `⇄`, duration `⏱` — fills the previously-empty duration slot; model `◆` unchanged). Glyphs identical in both sets stay inline at their build sites. `use_icons=false` zeroes every `ICON_*`. The chosen glyphs are standard Unicode (not Nerd-Font PUA, the reason the v2.15.0 `nerd_font`/`powerline` experiment was removed). Subagent renderer glyphs (`⚒ ✓ ✗ ◌`) are independent of `icon_set`.
- **Colourful activity line via tokens** — With `activity_colour=true` (default) the bash script passes `--colour` to the helper, which wraps segments in zero-width plain-text tokens (`{w}` warn, `{o}` ok, `{e}` err, `{i}` info, `{d}` back-to-dim, `{O}` completion flash, `{h1}`-`{h3}` elapsed heat, `{r0}`-`{r3}` todo gradient, `{s}` spinner slot). Tokens survive both sanitize layers; bash maps them to CLR_* theme constants AFTER sanitizing, substituting raw escape bytes, and prints line 2 with `%s` (never `%b`) so transcript-derived text can't decode into controls. The spinner frame comes from `NOW_EPOCH % 4` so it animates at the `refreshInterval` rate. Colours drop to all-dim when the cache is older than `activity_fresh_seconds` (45, stale-reads-as-stale) and under NO_COLOR/mono. The width trim is colour-aware: whole `  │  ` parts are dropped, never mid-escape cuts. Helper output without `--colour` stays byte-identical to pre-2.7 (version-skew safe both ways).
- **Per-session activity cache** — The activity cache is keyed by stdin `session_id` (`.statusline-activity-cache.<id8>`), so parallel sessions never clobber each other's line 2. Stale per-session caches are swept after 24h by the helper-spawn subshell; `--uninstall` removes them.
- **Subagent panel rows** — `statusline-subagent.js` implements Claude Code's `subagentStatusLine` protocol: stdin `{columns, tasks[]}` per ~5s tick, stdout one `{"id","content"}` JSON line per row. Renders status icon, elapsed, tokens, and a tok/s rate from `tokenSamples` (cumulative counts, one per tick, max 16). Errors exit silently so Claude Code keeps its default rows; `subagent_rows=false` in statusline.conf disables it. **Scope:** CC 2.1.170 only delegates Task-tool subagent rows (task type `local_agent`); workflow and background-task rows render through a separate panel path that ignores custom renderers, so they keep Claude Code's built-in style. Settings must carry quoted Windows-native paths (`node "C:/..."`): CC prefers Git Bash to spawn the command but falls back to PowerShell/cmd when it's missing, where node cannot resolve MSYS `/c/...` paths and fails silently. Both installers write that form and migrate their own older commands on re-run.
- **`usage_label` config** — Usage bar labels show the remaining time (`countdown`, default, e.g. `2h20m`) or the reset moment (`clock`). The default changed to `countdown` in v2.10.0. Countdown pairs well with the `refreshInterval` statusLine setting (CC re-runs the script on a timer) so the label stays fresh while idle.
- **Plugin marketplace** — `.claude-plugin/plugin.json` enables `/plugin install`. Slash commands for setup and configuration.
- **Pacing markers** — Progress bars support an optional `│` marker (CLR_PACE) showing where usage *should* be for even consumption across the window.
- **Token security** — OAuth tokens are passed to curl via `--config -` (stdin), not command-line args, so they're hidden from `ps`. wget uses `--max-redirect=0` to prevent token leakage on redirects. Since v2.20.0 the wget fallback also keeps the token off argv (S1): it writes the `Authorization` header to a `0600` temp wgetrc passed via `--config`, and if that temp file can't be created it skips the authenticated fetch rather than leaking the token. Curl is still strongly preferred; wget is a last-resort fallback.
- **Self-update integrity (v2.20.0)** — `perform_self_update` verifies every staged download against a per-release `SHA256SUMS` (fetched from `REPO_RAW`) before the swap; a mismatch/tamper/truncation aborts with nothing changed (G1). `sha256_of`/`have_sha256` do the hashing (sha256sum → shasum -a 256). The check is **skipped gracefully** when the manifest is unfetchable (old fork) or no sha tool exists, so those installs still update. `SHA256SUMS` is committed at repo root and kept honest by a CI `sha256sum -c` drift guard (`tests.yml` + `release.yml`); regenerate with `scripts/update-sha256sums.sh` after editing any of the three runtime files. The update source is hardened too (S2): `STATUSLINE_REPO_RAW` is captured into `_ENV_REPO_RAW` **before** `statusline.conf` is sourced and `REPO_RAW` is re-pinned from it **after**, so a sourced conf line can never repoint the (possibly unattended `auto_update`) updater — only a real env var can.
- **Shared helpers** — `http_get()` consolidates curl/wget fallback, `iso_to_epoch()` consolidates cross-platform date parsing. Avoids duplicated patterns.
- **`extract_block()` for nested JSON** — Extracts a JSON object block by key (content between `{ }`) to support nested structures like `vim`, `agent`, `workspace`, and `context_window`. Used by vim mode, agent name, token count, and workspace directory segments.
- **`umask 077`** — All cache/temp files are created with restrictive permissions (not world-readable).
- **`NOW_EPOCH` cached once** — A single `date +%s` call at startup is reused everywhere to minimise fork overhead.
- **REPLY return convention (hot path)** — Internal helpers (extract_*, sanitize, visible_width, build_progress_bar, format_reset_label, calc_pacing_target, iso_to_epoch) return via the `REPLY` global, never `$(fn)` command substitution: each substitution forks a subshell costing 15-25ms under MSYS, and ~50 ran per render before v2.8.0 (1286ms → 285ms on Windows). Keep new helpers on this convention. `REPLY` is safe because the script never uses bare `read`. `--benchmark` and `STATUSLINE_PROFILE=1` measure regressions.
- **Git via porcelain v2, two forks total** — One `rev-parse --git-dir --git-common-dir` (gate + stash-log location, worktree-correct) and one `status --porcelain=v2 --branch` (branch, ahead/behind, dirty count parsed in pure bash; entry count via line arithmetic). Stash count is a pure-bash line count of `logs/refs/stash`. Never add per-segment git calls.
- **`bar_width` config** — Progress bar width is configurable (default 10), used by `build_progress_bar()`.
- **`branch_max_length` config** — Long branch names are truncated with an ellipsis when set.
- **`dir_style` config** — `auto` (default; responsive: full path when the whole line fits the detected width, basename when it would overflow), `full` (always whole path), or `basename` (last path component only, splitting on both `/` and `\`). The dir+branch segment is built in both full (`dir_branch`) and compact (`dir_branch_base`) forms; a shared width-detection step (factored out of the truncation block, runs when `dir_style=auto` or `enable_truncation`) swaps `seg_vals[dir_seg_idx]` to the compact form before truncation drops any segments. So on a narrow terminal the path collapses to its basename *before* metrics start dropping.

## Roadmap & Sprints

See [docs/enhancement-backlog.md](docs/enhancement-backlog.md) for the single living planning doc — outstanding work, parked ideas, principles, and the competitive landscape. (The former `ROADMAP.md`/`SPRINTS.md` were retired once everything they planned shipped; release history lives in [CHANGELOG.md](CHANGELOG.md).)

Current version: **v2.20.0** (shipped). Release history begins at **Sprint 4 (v2.1.0)**, Testing & CLI :white_check_mark: shipped. BATS scaffold (28 tests), three-platform CI matrix, and four new CLI flags (`--help`, `--version`, `--dump-config`, `--uninstall`) all landed. v2.1.1 followed with the README overhaul, the NO_COLOR/mono progress bar fix, and `.claude-plugin/marketplace.json`. v2.2.0 audited the bar against Claude Code 2.1.170 (Fable 5): Fable/Mythos purple tier colour, effort + fast-mode segments, rate-limit extraction scoped to the `rate_limits` block, ISO `resets_at` tolerance, and `$COLUMNS`-first width detection. v2.3.0 added countdown usage labels (`usage_label`), the PR segment, worktree fallback via `workspace.git_worktree`, and per-session activity caches. v2.4.0 overhauled the live activity line: incremental transcript parsing, 5-minute age-out of finished items, `✗` failure indicator, elapsed time on running tools, `activity_ttl_seconds`, and `$COLUMNS` trimming. v2.5.0 added the subagent panel renderer (`statusline-subagent.js`, wired via the `subagentStatusLine` setting). v2.6.0 rebuilt context warnings around Claude Code's real auto-compact maths (marker + `context_warn_threshold=auto`), retired `▲ 200k+` (premium pricing abolished March 2026), and added `install.ps1` for Windows. v2.6.1 hardened Windows installs (quoted Windows-native paths in settings.json, migration of older command formats on re-run) and corrected the subagent renderer docs to its real scope (Task-tool subagent rows only; Claude Code 2.1.170 draws workflow and background-task rows itself). v2.7.0 shipped the colourful activity line (token architecture, spinner, heat colours, completion flash, gradient todo bar, stale fade; 12 new BATS tests, suite now 81) plus ANSI-aware line-2 trimming and four long-standing portability/safety fixes. v2.8.0 (Sprint 5) was the Windows performance overhaul: REPLY return convention, porcelain-v2 git consolidation, pure-bash sanitize/width maths, fork-free countdown labels, `--benchmark` + `STATUSLINE_PROFILE`, and the first git-segment tests (suite 87); measured 1286ms → 285ms per render on Windows with byte-identical output. v2.9.0 (Sprint 6) added the clickable PR segment (OSC 8 hyperlink, strict https allowlist, `pr_link`), opt-in `activity_pulse`/`activity_scanner` effects (pure bash-side, no helper skew), and tag-driven release automation (`release.yml`: verify VERSION/plugin.json/CHANGELOG agree, publish from the changelog section); suite 93. v2.10.0 flipped the `usage_label` default from `clock` to `countdown` (the usage bars now show time-remaining out of the box; `usage_label=clock` opts back in), with the BATS default-case test updated and a new `clock` opt-out test. v2.10.1 had both installers write a default `refreshInterval: 60` into the `statusLine` block (so the countdown default stays fresh), but only when first creating the block, so an existing `refreshInterval` is never clobbered. v2.10.2 documented (README + `/configure`) that `activity_pulse`/`activity_scanner` need a low odd `refreshInterval` like 3 to animate (the effects are wall-clock driven; an even interval like 2 can leave the pulse stuck on one beat), docs-only. v2.11.0 added one-command self-update: the `--update` flag (atomic staged download of script + helpers, `STATUSLINE_REPO_RAW`-overridable source) and an update notice that shows the new version as an OSC 8 link to its release notes (`tests/update.bats`, suite 102). v2.12.0 added opt-in `auto_update` (default false): when the background check flags a newer version, a detached background process runs the same atomic self-update, serialised with a lock dir; `--update` and the auto path share one `perform_self_update` core (suite 106). v2.13.0 added the `matrix` theme (eighth palette; monochrome digital-rain phosphor green, separated by brightness not hue) with a swatch, README gallery entry, and a themes.bats case (suite 107). v2.14.0 adopted the theme-palette redesign: the six named themes were re-palette'd to distinct official colours rendered in 24-bit truecolour with a 256-colour fallback (`tc_clr`/`apply_palette`), fixing the near-identical look the old 256 codes produced (suite 110); the preview scaffolding was removed. v2.15.0 added opt-in styling adapted from kcchien/claude-code-statusline: `bar_gradient` (gradient progress bars), `--demo` (theme preview), and `nerd_font`/`powerline` glyphs (suite 118) — all default-off. v2.16.x made `bar_gradient` a smooth per-cell interpolation (was 4 bands) and filled `--demo` bars so the full ramp shows. v2.17.0 added `bar_gradient=heat` (fixed green→red on any theme). v2.18.0 made gradient bars the default (`bar_gradient=true`; `false` = flat), turned the `default` theme's ramp into a green→red heat ramp, added `dir_style=full/basename/auto` (responsive path collapse before truncation) and made `dir_style=auto` + `enable_truncation=true` the **defaults** (graceful narrow-terminal cascade: collapse path, then drop low-priority segments), shipped a commented `statusline.conf.example` that the installers drop as `statusline.conf` on first install only (discoverable, editable, all-commented so it pins nothing), trimmed the redundant " context" from the model name, and **removed `nerd_font`/`powerline`** (the patched-font experiment from v2.15.0). v2.18.1 made `--update`/`auto_update` also refresh `statusline.conf.example` and seed `statusline.conf` when absent (best-effort, never overwriting), so self-update-only users get the commented starter config too (suite 123). v2.19.0 added the **customizable multi-line layout** (`layout` presets + `line1`/`line2`/`line3` token overrides, up to three lines, the live-activity line now a placeable `activity` token) and the **`icon_set=modern`** refreshed glyph set — both opt-in, default output byte-identical to v2.18.1. The single-line assembler was generalised into a per-line engine (`add_seg` now records a name; `seg_index_by_name`/`parse_line`/`assemble_line`; dir/branch split with a `" on "` connector; `calc_total_width` fork removed); 20 new BATS tests (`tests/layout.bats`, `tests/icons.bats`), suite 144. Both installers also gained a **`refreshInterval` back-fill**: they now add the default (`60`) to an *existing* `statusLine` block that lacks one (idempotent; never clobbers a user value), closing the gap where pre-v2.10.1 installs had no refresh timer — and `statusline.conf.example` got a "Refresh rate" note clarifying that `refreshInterval` lives in `settings.json`, not the conf. v2.19.1 fixed a phantom "update available" notice: the cache check fired on any cached version *different* from current, so right after a release (while the raw CDN still served the old `VERSION`) a user already on the new version saw a stale `↑ <older>` downgrade notice; it now uses a strict `version_gt` dotted-numeric compare and fires only for a genuinely newer version (the `auto_update` trigger inherits the guard), 2 regression tests, suite 146. v2.20.0 was a **self-updater security-hardening release** (Phase 0 of `docs/improvement-roadmap.md`): the self-update now verifies every staged download against a per-release `SHA256SUMS` before swapping (G1; aborts on mismatch, skips gracefully when the manifest/tool is absent), `statusline.conf` can no longer repoint the update source (S2; `STATUSLINE_REPO_RAW` is captured before the conf loads and re-pinned after), and the wget OAuth fallback no longer leaks the bearer token on argv (S1; `0600` temp wgetrc via `--config`). Added the committed `SHA256SUMS` manifest, `scripts/update-sha256sums.sh`, and CI `sha256sum -c` drift guards. The release also shipped the **`--open-config`** flag (opens `statusline.conf` in `$STATUSLINE_EDITOR`/VS Code/`$EDITOR`/the platform opener, seeding it from the example template if absent). 9 new BATS tests (`tests/update.bats` ×4, `tests/open_config.bats` ×5), suite 155. S3 (`update_ver` in the OSC 8 link) was found already mitigated — the existing `*[!0-9.]*` guard is stricter than `pr_url`'s allowlist. **Current version: v2.20.0.** Next (per the roadmap): Phase 1 — colourblind-safe theme (G2, needs design sign-off), the delta-cache primitive, and the first "fuel gauge" features.

## How to release a new version

**IMPORTANT: Do not skip any of these steps.** Tags, GitHub releases, and the plugin manifest version have all been missed before — always update them alongside the version bump.

1. Bump `VERSION` file (e.g., `1.5.0`)
2. Update `CHANGELOG.md` with a new `[1.5.0] - YYYY-MM-DD` section
3. Bump `.claude-plugin/plugin.json` `"version"` to match `VERSION`
4. Update all docs: README.md, CLAUDE.md (current milestone), docs/enhancement-backlog.md (move shipped items out of the backlog; update status labels)
4b. **If `statusline-command.sh`, `statusline-helper.js`, or `statusline-subagent.js` changed, regenerate the checksum manifest: `scripts/update-sha256sums.sh`.** The self-updater verifies downloads against `SHA256SUMS` (G1) and CI fails on drift, so a stale manifest blocks both the release and every user's `--update`.
5. Commit everything: `git add -A && git commit -m "release: v1.5.0" && git push`
6. Create annotated tag: `git tag -a v1.5.0 -m "v1.5.0" && git push origin v1.5.0`
7. The tag push triggers `.github/workflows/release.yml` (since v2.9.0): it verifies VERSION, plugin.json, and CHANGELOG agree, extracts the CHANGELOG section, and publishes the GitHub release. Verify it succeeded with `gh run list --limit 1` and `gh release view v1.5.0`. (Manual fallback: `gh release create v1.5.0 --title "v1.5.0" --notes "..."`)
8. Copy files to local install: `cp statusline-command.sh ~/.claude/statusline-command.sh && cp statusline-helper.js ~/.claude/statusline-helper.js`

Users with the update check will see `↑ update available` within 6 hours.

## Testing

Test with old schema (backward compat):

```bash
echo '{"cwd":"/tmp","display_name":"Sonnet","used_percentage":60,"total_cost_usd":0.50}' | bash statusline-command.sh
```

Test with new nested schema (model, context_window):

```bash
echo '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":78,"context_window_size":200000},"total_cost_usd":2.50}' | bash statusline-command.sh
```

Test with stdin rate limits (no OAuth needed):

```bash
echo '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":65},"total_cost_usd":0.50,"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1743019200},"seven_day":{"used_percentage":71,"resets_at":1743278400}}}' | bash statusline-command.sh
```

Test with v1.4.0 fields (vim mode, agent, workspace, tokens):

```bash
echo '{"cwd":"/tmp","display_name":"Sonnet","used_percentage":60,"total_cost_usd":0.50,"vim":{"mode":"NORMAL"},"agent":{"name":"my-agent"},"workspace":{"current_dir":"/home/user/project"},"context_window":{"total_input_tokens":45000,"total_output_tokens":12000}}' | bash statusline-command.sh
```

Test compaction awareness (marker at 83% of a 200k window, ▲ within 20k tokens of the compact point):

```bash
echo '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":74,"context_window_size":200000,"total_input_tokens":148000}}' | bash statusline-command.sh
```

Test live activity (Node.js helper):

```bash
# Create a test transcript
cat > /tmp/test-transcript.jsonl << 'EOF'
{"timestamp":"2026-03-26T10:00:00Z","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/src/main.ts"}}]}}
{"timestamp":"2026-03-26T10:00:01Z","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}
{"timestamp":"2026-03-26T10:00:02Z","message":{"content":[{"type":"tool_use","id":"t2","name":"Edit","input":{"file_path":"/src/main.ts"}}]}}
EOF
# Pre-populate cache then test
node statusline-helper.js /tmp/test-transcript.jsonl ~/.claude/.statusline-activity-cache
echo '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":65},"total_cost_usd":0.50,"transcript_path":"/tmp/test-transcript.jsonl"}' | bash statusline-command.sh
```

Test update notification by writing a fake cache:

```bash
echo "$(date +%s) 9.9.9" > ~/.claude/.statusline-update-cache
```

Test config overrides:

```bash
echo "show_cost=false" > ~/.claude/statusline.conf
```

After testing, update your local install:

```bash
cp statusline-command.sh ~/.claude/statusline-command.sh
cp statusline-helper.js ~/.claude/statusline-helper.js
```

## Code conventions

- Bash with `set -e` — strict error handling
- Comments use `# ── Section ───` separator style
- Colour codes use `CLR_*` theme variables (not inline ANSI codes)
- Default palette: cyan=dir, magenta=branch, green/yellow/orange=model (tier-dependent), green=additions, red=removals, yellow=warnings/cost
- All git commands use `-c core.fsmonitor=false` to avoid filesystem monitoring overhead
- Fallback chains: curl > wget, node > python3 > python > manual instructions

## Common pitfalls

- **GitHub raw CDN caches aggressively** — After pushing VERSION, it can take 5+ minutes for `raw.githubusercontent.com` to serve the new content.
- **Local install gets stale** — After editing the repo's `statusline-command.sh`, remember to copy it to `~/.claude/` for your own status bar to update.
- **`set -e` in subshells** — Background update fetch runs in `( ) &`. If curl/wget fails inside, only the subshell dies (by design).
- **Usage API requires OAuth scopes** — The token must have `user:profile` scope. Tokens created via `claude setup-token` only have `user:inference` and won't work. Users need browser OAuth (quit all CC instances and restart).
- **`date` portability for pacing** — macOS uses `date -juf`, GNU/MSYS2 uses `date -ud`. The `format_reset_label()` and `calc_pacing_target()` functions handle both.
- **Do NOT use `read -r -d ''` to capture stdin** — It silently fails on MSYS2/Windows bash, producing an empty variable. Always use `input=$(cat)` instead. The fork cost is negligible compared to broken input on Windows.
- **`refreshInterval` below the script's runtime blanks the whole bar** — Claude Code aborts an in-flight statusLine run when the next one starts, and an aborted run clears `statusLineText`. Measure with `--benchmark`: since the v2.8.0 fork overhaul the script takes ~285ms on Windows (was 1.3-2.5s) and well under 100ms on macOS/Linux. Recommend `2`+ on Windows for load headroom, `1` elsewhere.
