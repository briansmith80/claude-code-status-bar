# Changelog

All notable changes to this project will be documented in this file.

## [2.19.1] - 2026-06-16

### Fixed

- **Phantom "update available" notice showing an OLDER version.** The update-cache check fired whenever the cached remote version *differed* from the running version, not only when it was *newer*. So right after a release — while `raw.githubusercontent.com` still served the previous `VERSION` for a few minutes — a user already on the new version could see a stale `↑ <older>` downgrade notice until the next background check. The notice now uses a strict dotted-numeric `version_gt` comparison and fires only for a genuinely newer version (the `auto_update` trigger inherits the same guard, so it can never try to "update" to an older cached version). 2 new regression tests; suite 146.

## [2.19.0] - 2026-06-16

Put any segment on any of up to three lines, and refresh the icon set — both opt-in, with a byte-identical default.

### Added

- **Customizable multi-line layout** (`layout`, `line1`/`line2`/`line3`). Pick a preset — `classic` (the unchanged default), `three-line`, or `stacked` — or hand-assign individual segment tokens to each of up to three lines, in any order. The live activity line is now a placeable `activity` token, so it can sit on any line (or none). Full token vocabulary in `statusline.conf.example`. A token still obeys its `show_*` toggle; unknown tokens are ignored; a segment lives on the first line that lists it; an empty line is hidden (no blank row). **Quote any `lineN` value with spaces** (the conf is sourced as shell), e.g. `line2="dir branch lines_changed"`.
- **Refreshed icon set** (`icon_set=modern`). A more coherent set: directory ↱, branch ⑂, lines-changed ⇄, and a duration ⏱ that fills the previously-empty slot; model ◆ unchanged. `icon_set=classic` (the default) keeps today's exact icons, and `use_icons=false` still disables all icons.

### Changed

- The directory and branch segments are now separately addressable (`dir`, `branch`) but still render as the combined "path on <branch>" when adjacent (the default), so the out-of-the-box bar is byte-identical to v2.18.1.
- **Both installers now back-fill `statusLine.refreshInterval` on an existing block that lacks one** (default `60`; a value you already set is never touched). Previously the default was written only when the block was first created, so anyone who installed before v2.10.1 had no refresh timer — their countdown labels and live-activity line only updated on a new message. The config template (`statusline.conf.example`) also gained a "Refresh rate" note explaining that `refreshInterval` lives in `settings.json`, not the conf, since that's the file users open to configure the bar.

### Internal

- The single-line assembler became a per-line engine: dir auto-collapse, priority truncation, and group bracketing now run scoped to each line. The forking `calc_total_width` was replaced with inline, REPLY-convention width sums (a small fork reduction). 20 new BATS tests (`tests/layout.bats`, `tests/icons.bats`); suite 144.

## [2.18.1] - 2026-06-14

### Changed

- **`--update` and `auto_update` now also deliver the commented config.** When they install a new version they refresh `statusline.conf.example` and create `statusline.conf` from it **only if absent** (never overwriting an existing one) — best-effort, so a failed template fetch never affects the update. Previously only fresh installs and installer re-runs seeded the starter config; now users who only ever self-update get it too, with their tweaks always taking precedence (the template is all-commented, so it pins nothing). 1 new BATS test (suite 123).

## [2.18.0] - 2026-06-14

Better defaults out of the box (gradient bars, responsive layout), a commented config users can edit, a tidier model name, and the Nerd Font/Powerline experiment removed.

### Added

- **`dir_style` config** (`auto` default, `full`, or `basename`): `basename` shows just the last folder; `auto` is **responsive** — the full path when the line fits the terminal width, collapsing to the basename when it would overflow. The collapse happens *before* truncation drops any segments, so on a narrow terminal the path shrinks first and your model/usage/context survive longer. Handles both `/` and `\` separators. 4 new BATS tests.
- **A commented `statusline.conf.example`**, and the installers now create `~/.claude/statusline.conf` from it **on first install only** (never overwriting an existing one). Every line is commented and shows its default, so a fresh copy changes nothing — it just makes every option discoverable and editable in place. The `.example` is always refreshed so new options show up after an update.

### Changed

- **`bar_gradient` is now on by default** (`true`). Set `bar_gradient=false` for the classic flat single-colour bars. (`heat` forces a fixed green→yellow→orange→red ramp on any theme.) Measured with `--benchmark`: no perceptible cost vs flat (pure-bash integer lerp, no forks).
- **`dir_style` defaults to `auto`** and **`enable_truncation` defaults to `true`** — together they make narrow terminals graceful: the path collapses to its basename first, then low-priority segments drop only if it's still too tight, instead of the line wrapping. Both rely on `COLUMNS` (set by Claude Code 2.1.153+); set `dir_style=full` / `enable_truncation=false` to opt out.
- **The `default` theme's gradient is now a green→yellow→orange→red "heat" ramp**, so out of the box the bars read green→red by usage. Other themes keep their own gradient ramps.
- **The model name drops the redundant " context"**: `Opus 4.8 (1M context)` → `Opus 4.8 (1M)`. Saves ~8 chars; only touches that exact suffix.

### Removed

- **`nerd_font` and `powerline`** (added in v2.15.0) are removed — they required a patched Nerd Font in the terminal and added noise for little benefit. The scattered glyph overrides, the `printf -v` glyph block, the separator logic, the `--dump-config` entries, the tests, and all docs references are gone. Segment icons are back to plain Unicode (`use_icons`). Any `nerd_font`/`powerline` lines left in a `statusline.conf` are harmless no-ops.

## [2.17.0] - 2026-06-13

### Added

- **`bar_gradient=heat`**: a third value for `bar_gradient` that paints the progress bars with a fixed **green→yellow→orange→red** ramp regardless of the colour theme. `bar_gradient=true` still uses the theme's own green→accent ramp; `heat` is for keeping a theme's look (e.g. `matrix`'s all-green palette) while still getting classic usage-heat bars. Reuses the existing per-cell interpolation engine (so it's smooth and truecolour/256-aware) and stays a no-op under `mono`/`NO_COLOR`. New BATS test (suite 121).

## [2.16.1] - 2026-06-13

### Changed

- **`--demo` now fills the bars to ~92%** (context, plus the 5h/7d usage bars) instead of 65%, so the full progress-bar gradient is visible across the whole bar when previewing themes. Demo-only; no change to live rendering.

## [2.16.0] - 2026-06-13

### Changed

- **`bar_gradient` now renders a smooth per-cell gradient instead of four colour bands.** Each filled cell gets its own colour, linearly interpolated (in RGB) across the theme's four ramp stops, so a 10-wide bar shows ten distinct shades rather than the old `3 + 2 + …` banding. Truecolour per cell, with a nearest-256 fallback. Still theme-aware (e.g. `matrix` stays a smooth dark→bright green) and still a no-op under `mono`/`NO_COLOR`. The ramp hexes are stashed in `RAMP_HEX` by `apply_palette()` (and the `default` theme); interpolation is pure-bash integer math (no forks). Test tightened to assert a smooth spread.

## [2.15.1] - 2026-06-13

### Fixed

- **`--demo` (and the `STATUSLINE_THEME` env override) could be defeated by a config line.** The override was applied *after* `statusline.conf` was sourced, so a `STATUSLINE_THEME=...` line in the conf (an easy mistake — it looks like a config key) clobbered the per-theme value `--demo` passes, making every previewed theme render identically (and pinning the live bar to that theme). The env value is now captured *before* the conf is sourced and applied after, so it always wins and a `STATUSLINE_THEME` line in the conf is a harmless no-op (use `colour_theme` to set the theme in the conf). 2 new BATS tests (suite 120).

## [2.15.0] - 2026-06-13

Opt-in styling: gradient bars, a theme preview flag, and Nerd Font / Powerline glyphs (ideas adapted from kcchien/claude-code-statusline).

### Added

- **`bar_gradient` (opt-in, default false):** colour the progress bars along the active theme's green→accent gradient instead of one flat colour, reusing the existing per-theme `CLR_RAMP0-3` stops (and the truecolour engine). No-op under `mono`/`NO_COLOR`; the dim track and pacing marker are unchanged.
- **`--demo [theme]` flag:** preview a theme with a realistic canned payload without faking stdin or touching `statusline.conf`. `--demo tokyo-night` renders one; `--demo` / `--demo all` cycles all eight, labelled. Uses a new `STATUSLINE_THEME` env override (applied after the conf) to force the theme per render.
- **`nerd_font` and `powerline` (opt-in, default false):** `nerd_font` swaps the Unicode segment icons for Nerd Font glyphs (encoded as UTF-8 bytes via `printf -v`, so still Bash 3.2-safe and fork-free); `powerline` adds an arrow () separator between segments. Both need a patched Nerd Font installed and degrade to the Unicode/space defaults otherwise.
- **8 new BATS tests** (`tests/styling.bats`; suite 118): gradient on/off, `--demo` single/all, nerd-font on/off, powerline on/off.

All three are off by default, so existing output is unchanged. Not adopted from kcchien: its `jq` requirement, macOS-only `stat`, and 5s git cache (we're jq-free and already lean via porcelain-v2).

## [2.14.0] - 2026-06-13

Truecolour theme palettes, redesigned to be distinct.

### Changed

- **The six named themes were re-palette'd to official, distinct colours and rendered in 24-bit truecolour.** They're now spread across a deliberate saturation/temperature ladder so no two read alike: **dracula** neon, **default** bold primary, **tokyo-night** deep midnight blue + neon accents, **catppuccin** soft warm pastel, **solarized** earthy, **nord** muted cool steel, **matrix** monochrome green, **mono** greyscale. This fixes themes (notably nord vs catppuccin, and tokyo-night vs catppuccin) reading as near-identical, which happened because the old 256-colour codes quantized distinct palettes onto the same cells.
- **Truecolour with a 256-colour fallback.** `apply_theme()` now stores hex palettes and emits `38;2;r;g;b` when truecolour is available (detected via `$COLORTERM`, overridable with `STATUSLINE_TRUECOLOR=1`/`0`), falling back to the nearest xterm-256 colour so Terminal.app and older terminals still get sensible, distinct colours. `default` still tracks your terminal's own ANSI palette; `mono` is unchanged.
- README theme gallery regenerated with the new palettes and a "vibe" column; swatch generator updated. **3 new BATS tests** (truecolour/256/override paths; suite 110).

## [2.13.0] - 2026-06-13

A *Matrix* theme.

### Added

- **`matrix` colour theme**: a digital-rain phosphor-green palette (the eighth theme). It's monochrome by design, like a green CRT, so segments are separated by brightness rather than hue: bright `#00ff5f` directory, the palest "lead" green for the Opus accent and the pacing marker, chartreuse for warnings/cost, and a dim `#008700` for removals (no red). Respects `NO_COLOR`/mono like every theme. Added to `apply_theme()`, the swatch generator (new `docs/assets/themes/matrix.svg`), the README theme gallery, and the `setup`/`configure` commands. New BATS test in `tests/themes.bats`.

## [2.12.0] - 2026-06-13

Opt-in automatic updates.

### Added

- **`auto_update` config (opt-in, default `false`)**: when the background check flags a newer version, the bar installs it for you in a detached background process that never blocks rendering. It reuses the v2.11.0 atomic self-update (staged downloads swapped in only once all succeed; a failed or interrupted fetch changes nothing; `statusline.conf`/`settings.json` untouched) and serialises with a lock dir so parallel sessions don't all download at once. Stays off by default so the tool never replaces its own executable without you asking. The manual `--update` flag and the auto path now share one `perform_self_update` core.
- **4 new BATS tests** (`tests/update.bats`; suite now 106): `auto_update` default-off + `--dump-config`, install-on-pending, leave-alone-when-off, and no-op-when-current. A `STATUSLINE_AUTOUPDATE_SYNC` seam runs the otherwise-detached update inline so the tests are deterministic.

## [2.11.0] - 2026-06-13

One-command self-update, and an update notice that tells you the version and links the release notes.

### Added

- **`--update` flag**: `bash ~/.claude/statusline-command.sh --update` downloads the latest `statusline-command.sh` and both Node helpers, bumps `.statusline-version`, and clears the update cache. Each file is staged beside its target and only swapped in once **every** download succeeds, so a failed or interrupted fetch leaves the install untouched; `statusline-command.sh` moves first (it is the running file) so a Windows in-use rename can't leave a version mismatch. Never touches `statusline.conf` or `settings.json`. The download source is overridable with `STATUSLINE_REPO_RAW` (a fork, or a `file://` path for testing).
- **9 new BATS tests** (`tests/update.bats`; suite now 102): the `--update` happy path, no-op-when-current, config preservation, and the notice's version + OSC 8 hyperlink behaviour.

### Changed

- **The update notice now shows the new version and links to its release notes.** `↑ update available` became `↑ <version>` (e.g. `↑ 2.11.0`), wrapped in an OSC 8 hyperlink to that release's GitHub page so it click-opens the changelog (honours `pr_link`; falls back to plain text when the version string isn't clean or links are off). `--check-update` now points at `--update` instead of the install one-liner.

## [2.10.2] - 2026-06-13

Documented the `refreshInterval` the animated activity effects need.

### Changed

- **Docs: `activity_pulse` and `activity_scanner` now explain their `refreshInterval` dependency.** The spinner, the scanner sweep, and the pulse breath are all driven by the wall clock, so they only animate when the bar re-renders often. The README and the `/configure` command now recommend a low **odd** `refreshInterval` such as `3` when either effect is enabled, and call out that an even value like `2` can leave the pulse stuck (its breath toggles each whole second, so an even interval keeps sampling the same beat). No behaviour change; defaults remain `activity_pulse=false`, `activity_scanner=false`, `refreshInterval` written as `60`, which is why both effects ship off.

## [2.10.1] - 2026-06-13

Installers set a default `refreshInterval` so the new countdown label stays fresh.

### Changed

- **Both installers now write `"refreshInterval": 60` into the `statusLine` block** (`install.sh` and `install.ps1`). With the v2.10.0 countdown default, the label would otherwise only update when Claude Code re-rendered the bar (after each response); a 60-second timer keeps it current and keeps the live activity line's elapsed times moving. The value is written **only when the installer first creates the `statusLine` entry** (new install, or `statusLine` absent on update), so an existing `refreshInterval` is never overwritten. The Python no-node fallback preserves any existing value and defaults to 60. Tune or remove it in `settings.json`; keep it at `2`+ on Windows.

## [2.10.0] - 2026-06-13

The usage-bar label now counts down by default.

### Changed

- **`usage_label` now defaults to `countdown`** (was `clock`): the 5hr and weekly usage bars show the time remaining until reset (`5hr (2h20m)`, `wk (3d4h)`) out of the box, instead of the reset moment (`5hr (2pm)`, `wk (fri,3am)`). Set `usage_label=clock` in `statusline.conf` to keep the old reset-moment label. Because a countdown sits stale between renders, pairing it with a `refreshInterval` on the `statusLine` setting is recommended (see the README). BATS coverage updated: the default case now asserts countdown, and a new test covers the `usage_label=clock` opt-out.

## [2.9.0] - 2026-06-12

Clickable PR links, two opt-in activity effects, and tag-driven release automation.

### Added

- **Clickable PR segment** (`pr_link=true`, default on): the `PR #1234` segment now wraps in an OSC 8 hyperlink to `pr.url` from stdin, so it click-opens the pull request in terminals with hyperlink support (Claude Code converts OSC 8 into real links; unsupported terminals degrade to plain text). URLs pass a strict allowlist (https only, no characters that could escape the OSC payload); anything else renders the plain segment. The truncation width maths is OSC 8 aware.
- **`activity_pulse=false`** (opt-in): the running tool/agent label on line 2 breathes, alternating bold and faint each re-render. Intensity is cleared with SGR 22 at segment boundaries so it never bleeds.
- **`activity_scanner=false`** (opt-in): while something has been running long enough to earn a heat tier (30s+), a small 8-cell tracker with a theme-accent cell sweeps left-right-left at the end of line 2, one step per re-render. Both effects are pure bash-side, so there is no helper version skew, and both are no-ops under `NO_COLOR`/mono defaults.
- **Tag-driven release automation** (`.github/workflows/release.yml`): pushing a `v*` tag verifies that `VERSION`, `plugin.json`, and `CHANGELOG.md` agree, extracts the matching changelog section, and publishes the GitHub release. Retires the manual `gh release create` step and the drift class of release mistakes.
- **6 new BATS tests** (`tests/pr_link.bats` plus pulse/scanner/defaults coverage in `tests/activity_colour.bats`; suite now 93).

## [2.8.0] - 2026-06-12

4.5x faster on Windows: the script now renders in ~285ms there (down from ~1286ms), making `refreshInterval: 2` comfortable on Windows and keeping macOS/Linux well under 100ms.

### Added

- **`--benchmark [N]` CLI flag**: times N end-to-end runs (default 5) against a realistic canned payload (current directory as cwd, stdin rate limits, a tiny transcript) and reports min/avg/max. Requires GNU date `%N`; degrades with a clear message elsewhere.
- **`STATUSLINE_PROFILE=1`**: per-phase wall-clock breakdown (startup+config, stdin+fields, git, activity, usage, segments+render) to stderr on any run, for finding where time goes on a given machine.
- **6 new BATS tests** (`tests/git_states.bats`, suite now 87): the first direct coverage of the git segments — branch/dirty/ahead-behind from the porcelain parser, stash reflog counting, detached HEAD, no-upstream repos — plus `--help`/`--benchmark` checks.

### Changed

- **Fork-count overhaul** (the entire speedup; output is byte-identical across all documented stdin schemas):
  - Internal helpers return via a `REPLY` global instead of `$(fn)` command substitution — every substitution forks a subshell, which costs 15-25ms under MSYS process emulation, and ~50 of them ran per render.
  - **Git work consolidated**: one `rev-parse --git-dir --git-common-dir` plus one `status --porcelain=v2 --branch` now provide the branch name, ahead/behind, and dirty count (parsed in pure bash, entry count via line arithmetic so huge dirty trees stay cheap). The stash count reads the stash reflog (`logs/refs/stash` in the common dir, correct in linked worktrees) instead of forking `git stash list | wc -l`. Five git forks and six pipeline forks became two git forks.
  - **`sanitize()` and `visible_width()` are pure bash** (no sed/tr/printf pipelines).
  - **Stdin `resets_at` epochs stay epochs**: previously they were converted epoch→ISO with a date fork only for `iso_to_epoch` to convert them straight back with another. Pacing targets and countdown labels are now fork-free; clock/day labels cost one date fork instead of 3-6 (bash-native lowercasing of day/AM-PM vocab).
  - The stale activity-cache sweep (`find`) runs on ~1 in 37 refreshes instead of every run, and the `autoCompactWindow` settings probe reads the file without a `$(cat ...)` fork.
- **Windows `refreshInterval` guidance relaxed**: with ~285ms runs, `2` is comfortable on Windows (was "5 or higher"); `1` is fine on macOS/Linux.

## [2.7.0] - 2026-06-12

The activity line gets colour: active work pops in theme colours while history stays dim.

### Added

- **Colourful activity line** (`activity_colour=true`, default on): line 2 graduates from all-dim grey to per-segment theme colours. Running tools and agents render in the theme's warning colour behind a clock-driven spinner (`⠋⠙⠸⠴`, advances on every re-render; pair with a `refreshInterval` statusLine setting comfortably above the script's runtime, e.g. `1` on macOS/Linux, `5`+ on Windows where MSYS bash runs take 1-3s and a too-low interval makes Claude Code abort every run and blank the bar); elapsed times are heat-coloured (green under 30s, yellow under 2m, red beyond); failures are red; a just-finished tool flashes bright green with a `✓` for ~5 seconds; the todo bar's filled cells shade through a per-theme 4-step gradient (new `CLR_RAMP0`-`CLR_RAMP3` in every theme). When the cached data is older than `activity_fresh_seconds` (default 45) the colours drop back to all-dim, so stale data reads as stale. All seven themes, `NO_COLOR`, and mono degrade cleanly. Architecture: the helper emits zero-width plain-text tokens that survive both sanitize layers; bash maps them to theme constants after sanitization and prints line 2 with `%s`, so transcript-derived text is never `%b`-decoded.
- **12 new BATS tests** (`tests/activity_colour.bats`, suite now 81) covering token emission, back-compat plain output, token-lookalike defusing, theme mapping, flash/gradient, stale fade, the `activity_colour` toggle, `NO_COLOR`, quote unescaping, decode-injection safety, the colour-aware trim, and `--dump-config`.

### Fixed

- **Line 2 width trim is now ANSI-aware**: it drops whole `  │  ` parts until the line fits instead of hard-cutting by byte count (which over-counted escape bytes and could slice mid-sequence).
- **A double quote in displayed content no longer truncates line 2**: the cache extraction now tolerates JSON-escaped quotes and unescapes them for display.
- **`NO_COLOR` leak in the `Starting...` placeholder**: it emitted a hardcoded `\033[2m` fallback even under `NO_COLOR`/mono.
- **`sanitize`/`strip_ansi` now work on BSD sed (stock macOS)**: the patterns interpolate real ESC/BEL bytes instead of `\x1b` hex escapes that only GNU sed understands.
- **Non-UTF-8 locales no longer over-trim line 2**: the script probes `${#}` character semantics at startup and adopts a UTF-8 locale when the active one counts bytes, so multibyte glyphs aren't sliced by the width trim.
- **A corrupted activity cache timestamp with leading zeroes (e.g. `0089`) no longer prints a bash arithmetic error** to stderr.

## [2.6.1] - 2026-06-10

Scope honesty for the subagent renderer, and Windows installs that survive every spawn shell.

### Fixed

- **`install.sh` on Windows (MSYS2/Git Bash) now writes Windows-native paths into `settings.json`** (via `cygpath -m`, e.g. `node "C:/Users/name/.claude/statusline-subagent.js"` instead of `node /c/Users/...`). Claude Code prefers Git Bash to spawn `statusLine`/`subagentStatusLine` commands but falls back to PowerShell or cmd when Git Bash is missing, and native node resolves an MSYS `/c/...` path to the nonexistent `C:\c\...`, so the subagent renderer died silently on such machines. Native paths work under the Git Bash, PowerShell, and cmd spawn paths alike. `/setup` carries the same guidance.
- **Both installers migrate the commands they previously wrote.** Re-running `install.sh` or `install.ps1` on Windows upgrades an existing `statusLine`/`subagentStatusLine` entry in place when its command exactly matches one of this project's own older formats (MSYS-style or unquoted native paths). Customised entries are still never touched.
- **Script paths in the written commands are now quoted**, so installs survive profile directories with spaces (e.g. `C:/Users/John Smith`) under every spawn shell. Previously such a path split at the space and the command died with exit 127.
- **Docs no longer claim the subagent renderer styles workflow and background-task rows.** Claude Code (verified against 2.1.170) only delegates Task-tool subagent rows (task type `local_agent`) to `subagentStatusLine`; workflow and background-task rows are drawn by a separate panel path that ignores custom renderers. README, CLAUDE.md, and the script header now state the real scope. The renderer keeps its handling for the other task shapes in case a later Claude Code starts sending them.

## [2.6.0] - 2026-06-10

Context warnings rebuilt around how Claude Code actually compacts, plus a first-class Windows install experience.

### Added

- **Auto-compact awareness on the context bar**: Claude Code auto-compacts at a fixed token reserve below the window (window minus 33000 tokens, constants extracted from CC 2.1.170), which lands at roughly 83% of a 200k window but almost 97% of a 1M window. The context bar now carries a `│` marker at that point, and the new default `context_warn_threshold=auto` fires the `▲` warning within 20000 tokens of it, matching Claude Code's own context-low timing on any window size. The maths honours `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, the `autoCompactWindow` setting from `/autocompact`, and `DISABLE_AUTO_COMPACT`/`DISABLE_COMPACT` (marker off, raw 80% fallback). A numeric `context_warn_threshold` keeps the legacy fixed-percentage rule. No other status line reads Claude Code's real compaction config.
- **`install.ps1`**: native Windows PowerShell installer/updater. One-liner: `irm https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main/install.ps1 | iex`. Merges `settings.json` natively (no node/python needed), writes BOM-free JSON with forward-slash paths, checks for Git Bash, wires `subagentStatusLine` when Node.js is present, never touches existing entries, and is idempotent. Supports `-SourceDir`/`-TargetDir` for offline installs and CI.
- **CI**: the Windows job now parse-checks and smoke-tests `install.ps1` (fresh install plus idempotent re-run against a sandbox).
- **7 new BATS tests** for compaction awareness (suite now 69).

### Removed

- **The `▲ 200k+` segment**: it signalled long-context premium pricing, which Anthropic abolished on March 13, 2026 (1M context is GA at flat standard pricing). On 1M models the warning just nagged permanently from 200k onwards while signalling nothing actionable. The `exceeds_200k_tokens` stdin field is now ignored.

### Changed

- **README**: install section restructured with separate macOS/Linux and Windows (PowerShell) one-liners; the previous advice to pipe `curl.exe` into `bash` from PowerShell was replaced (PowerShell 5.1 re-encodes pipeline data between native programs and can corrupt the script); PowerShell examples added for updating; doc refresh for current test counts, the v2.5.0 installer behaviour, the Node.js requirements row, the manual uninstall list (per-session activity caches), and `tests/README.md`.

### Fixed

- **Config docs consistency**: `subagent_rows` is now declared in the script's defaults block so it shows up in `--dump-config` (it is consumed by `statusline-subagent.js`); `colour_theme` and `usage_cache_seconds` are now documented in the `/configure` command; the README config example includes `subagent_rows`.

## [2.5.0] - 2026-06-10

### Added

- **Subagent panel renderer** (`statusline-subagent.js`): implements Claude Code's `subagentStatusLine` protocol to restyle the agent panel rows shown while subagents, workflows, and background tasks run. *(Correction: Claude Code only delegates Task-tool subagent rows to custom renderers; workflow and background-task rows keep its built-in style. See 2.6.1.)* Each row gets a theme-aware status icon (`⚒` running, `✓` done, `✗` failed, `◌` queued), elapsed time, compact token cost, and a live `tok/s` burn rate with sparkline computed from Claude Code's per-tick token samples. Descriptions align into a column across rows; rows trim to the panel width. Any error makes the script print nothing, so Claude Code falls back to its default rows. Disable with `subagent_rows=false` in `statusline.conf`.
- **Installer wiring**: `install.sh` downloads the renderer and adds a `subagentStatusLine` entry to `settings.json` when Node.js is available, never touching an existing entry. The `/setup` slash command does the same from the plugin cache. `--uninstall` removes the new file.
- **8 new BATS tests** (`tests/subagent.bats`, suite now 62) covering rendering, status icons, NO_COLOR, width fitting, malformed input, default-row passthrough, the `subagent_rows` toggle, and output validity.

## [2.4.0] - 2026-06-10

Live activity line overhaul, driven by measurements against a real long-running session.

### Added

- **Incremental transcript parsing**: the per-transcript cache now stores the parse state plus a byte offset, so each helper run parses only the lines appended since the last run instead of re-reading the whole transcript. Long sessions stay constant-cost; old-format caches upgrade transparently via a one-time full parse.
- **Failed-tool indicator**: the most recent tool failure shows as `✗ Bash npm test` for five minutes. Errors were already tracked internally but never displayed.
- **Elapsed time on running tools**: a tool running longer than 5 seconds shows its duration, e.g. `▶ Bash npm run build 1m20s` (previously only subagents had elapsed time).
- **`activity_ttl_seconds` config** (default 120): how old the activity cache may be before line 2 hides. The old hardcoded 30 seconds meant idle timer refreshes (`refreshInterval: 60`) hid line 2 exactly when you were idle-watching a long subagent run.
- **Terminal-width trimming**: line 2 is trimmed to `$COLUMNS` so it never wraps and pushes line 1 out of view.
- **8 new BATS tests** (`tests/activity.bats`, suite now 54), exercising the helper directly plus the bash-side TTL and trimming.

### Fixed

- **Completed items no longer linger forever**: the last completed tool, failures, and finished subagents (`⚒ desc ✓`) age out of the display five minutes after finishing. Previously a subagent that completed hours earlier stayed on line 2 for the rest of the session. Tool counts still cover the whole session.
- **Stale helper header comment**: the usage comment described a cache format (including a token-speed feature) that never existed; it now documents the real format.

## [2.3.0] - 2026-06-10

Leverages Claude Code capabilities surfaced during the 2.2.0 audit: countdown labels, the stdin `pr` block, broader worktree detection, and session IDs for cache keying.

### Added

- **Countdown usage labels** (`usage_label=countdown`): the usage bars can show time remaining until reset (`5hr (2h20m)`, `wk (3d4h)`) instead of the reset moment (`5hr (2pm)`, default `clock`). Pairs well with Claude Code's `refreshInterval` statusLine setting (documented in the README) so the countdown stays fresh while idle.
- **Pull request segment** (`show_pr`, on by default): shows `PR #N` for the current branch from the stdin `pr` block (Claude Code 2.1.145+), no `gh` calls. Coloured by review state: green approved, yellow pending, red changes requested, dim draft. Disappears when the PR merges or closes.
- **Worktree fallback**: the worktree segment now also reads `workspace.git_worktree`, so it works in any linked git worktree, not only `--worktree` sessions.
- **8 new BATS tests** (suite now 46) covering countdown labels, the clock default, the PR segment and its toggle, and worktree fallback precedence.

### Fixed

- **Per-session activity cache**: line 2 was read from a single global cache, so two Claude Code sessions running in parallel overwrote each other and could show the other session's activity. The cache is now keyed by the stdin `session_id` (`.statusline-activity-cache.<id>`); stale per-session caches are swept after 24 hours and `--uninstall` removes them.

## [2.2.0] - 2026-06-10

Audited against Claude Code 2.1.170 (the Fable 5 release) using a live captured stdin payload, the current statusline docs, and the Claude Code changelog. Rate limits, the nested `cost` block, `context_window.current_usage`, and 1M context all verified working; the items below are what needed fixing or was newly possible.

### Added

- **Fable/Mythos tier colour**: the new flagship model family now gets a theme-aware purple in all 7 themes (default/dracula/tokyo-night 141, nord 139, solarized 61, catppuccin 183), matching how Opus gets theme-aware orange. Previously Fable 5 rendered in the generic blue used for unknown models.
- **Effort level segment** (`show_effort`, on by default): shows the live reasoning effort as `eff:low|medium|high|xhigh|max` from the `effort.level` stdin field (Claude Code 2.1.133+). Closes the roadmap item that was blocked on anthropics/claude-code#31415.
- **Fast mode indicator** (`show_fast_mode`, on by default): `⚡ fast` in yellow while `fast_mode` is true, since fast mode bills at a higher rate.
- **11 new BATS tests** (`tests/cc21.bats`, suite now 39) covering the CC 2.1.x schema: nested `cost` block, `current_usage`, Fable/Mythos colours, `model.id` `[1m]` suffix containment, effort and fast-mode segments, rate-limits scoping, and ISO `resets_at`.

### Fixed

- **Rate-limit extraction scoped to the `rate_limits` block**: previously a `five_hour`/`seven_day` object anywhere in the stdin JSON was honoured as rate-limit data as long as a `rate_limits` key existed somewhere. Schema additions elsewhere in the payload can no longer corrupt the usage bars.
- **ISO-8601 `resets_at` tolerated**: a quoted timestamp now keeps the reset label and pacing marker instead of silently dropping both. Claude Code currently sends epoch seconds; this is future-proofing against a format change.
- **Truncation width prefers `$COLUMNS`**: Claude Code 2.1.153+ sets `COLUMNS` for statusline commands, and `tput cols` is unreliable when output is captured, so the detection order is now `max_width`, then `$COLUMNS`, then `tput cols`, then 120.

### Changed

- Token-count segment documentation now reflects Claude Code 2.1.132 semantics: `total_input_tokens`/`total_output_tokens` are tokens currently in context, not cumulative session totals, on CC >= 2.1.132.
- ROADMAP: marked the effort-level idea shipped and catalogued newly available stdin fields (`pr.*`, `workspace.repo.*`, `session_name`, `thinking.enabled`) as candidate segments.

## [2.1.1] - 2026-06-10

### Added

- **`.claude-plugin/marketplace.json`**: marketplace catalog so `/plugin marketplace add briansmith80/claude-code-status-bar` works as documented. The command requires a `marketplace.json`; `plugin.json` alone is not enough.
- **README banner and terminal demo images** (`docs/assets/`): dark/light banner SVGs and a colour terminal demo. `docs/` was removed from `.gitignore` so the images actually ship.

### Changed

- **README rewritten**: banner with dark/light variants, CI badges, table of contents, requirements table, line-2 symbol legend, truncation and grouping documentation, expanded troubleshooting, security notes, and a how-it-works diagram. Every example and default was verified against real script output.

### Fixed

- **Progress bars rendered twice under `NO_COLOR` and the mono theme**: `build_progress_bar()` returned `bar\ncolour`, and with an empty colour string the command substitution stripped the trailing newline, so callers extracted the whole bar again in place of the colour and printed it twice. The function now returns `colour\nbar` so the separator survives. Coloured output is byte-identical to before.

## [2.1.0] - 2026-04-30

### Added

- **BATS test scaffold** (`tests/`) — 28 tests across 5 files covering schema parsing (old flat + new nested + stdin `rate_limits`), segment rendering, all 7 themes, config overrides, and context-window formatting (200k / 1M / 1.5M, 0% / 100% bar fill). Run locally with `bats tests/`.
- **CI matrix on three platforms** (`.github/workflows/tests.yml`) — runs the BATS suite on `ubuntu-latest`, `macos-latest`, and `windows-latest` (MSYS2). Existing ShellCheck workflow is unchanged.
- **`--dump-config` flag** — prints the resolved configuration (defaults overridden by `~/.claude/statusline.conf`) as alphabetised `key=value` lines. Useful for debugging "why isn't my override taking effect?"
- **`--uninstall` flag** — interactive removal of installed files. Prompts before deleting; prompts separately before removing `statusline.conf` so users can keep their config; reminds users to remove the `"statusLine"` block from `settings.json` manually (does not auto-edit JSON).
- **`--version` flag** — prints the installed version and exits.
- **`--help` flag** — prints usage info for all CLI flags.
- **README "Testing" and "CLI Flags" sections** documenting the new tooling.

### Changed

- Update-check background subshell is now skipped when `--dump-config` or `--uninstall` is invoked, so diagnostic flags never make network calls.

## [2.0.4] - 2026-04-30

### Removed

- **Dead `.statusline-usage-log` writer** — `fetch_usage_data()` was appending `200`/`429`/`bad_response` lines to a log file that was never read by anything. Pure debug residue from old rate-limit work; removing it eliminates ~6 lines of code and two extra `tail`+`mv` disk operations per OAuth fetch. Existing log files at `~/.claude/.statusline-usage-log` are now orphaned and can be deleted manually.

### Changed

- **Opus orange is now theme-aware** — previously hardcoded as `\033[38;5;208m` (default-theme orange) in every theme. Each of the 7 themes now defines its own `CLR_MODEL_OPUS` so the Opus tier colour fits the palette: nord aurora orange, dracula `#ffb86c`, solarized `#cb4b16`, tokyo-night `#ff9e64`, catppuccin peach `#fab387`. Default theme keeps `208` (visually identical to before).

## [2.0.3] - 2026-04-30

### Fixed

- **`.claude-plugin/plugin.json` version drift** — manifest was stuck at `2.0.0` despite v2.0.1 and v2.0.2 shipping. Now matches `VERSION`.
- **README typos** — "18 segments" → 17 (actual count); `5hr(2pm)` → `5hr (2pm)` and `wk(fri,3am)` → `wk (fri,3am)` to match real script output.
- **Stray Chinese character** in `statusline-command.sh` cwd-sanitize comment (autocomplete artefact).

### Changed

- **Release checklist in `CLAUDE.md`** now includes a step to bump `.claude-plugin/plugin.json` (root cause of past drift).
- **`SPRINTS.md`** now acknowledges v2.0.x patch releases shipped between v2.0.0 and the upcoming v2.1.0.

## [2.0.2] - 2026-04-30

### Changed

- **Context window suffix uses `M` for million-token windows** — previously displayed as `of 1000k`, now shows `of 1M` (or `of 1.5M`, etc.). Sub-1M windows continue to display in `k`.

## [2.0.1] - 2026-04-09

### Fixed

- **Context window 0% on 1M context models** — `extract_block()` regex stopped at the first `}` inside nested JSON objects, causing `used_percentage` to be missed when `context_window` contains sub-objects (affects Opus 4.6 with 1M context)

## [2.0.0] - 2026-03-26

### Added

- **Stdin-native rate limits** — reads `rate_limits.five_hour` and `rate_limits.seven_day` directly from Claude Code's stdin JSON (CC >= 2.1). Zero network requests, real-time data. Falls back to OAuth API for older versions.
- **Live activity line** (`show_activity`) — optional second line showing running tools, completed tool counts, subagent status, and todo progress. Parses Claude Code's JSONL transcript via a Node.js helper. Enabled by default; disable with `show_activity=false`.
- **`statusline-helper.js`** — Node.js transcript parser with SHA256-keyed disk cache. Runs in background, never blocks the status bar. Only invoked when `transcript_path` is available and Node.js is installed.
- **Plugin marketplace support** — `.claude-plugin/plugin.json` manifest, `/claude-code-status-bar:setup` and `/claude-code-status-bar:configure` slash commands. Install via `/plugin install` or submit to the Anthropic plugin directory.
- **Updated stdin schema** — handles both legacy flat format (`display_name`, `used_percentage` at top level) and new nested format (`model.display_name`, `context_window.used_percentage`, `rate_limits`).

### Changed

- **Usage limits architecture** — stdin is now the primary data source; OAuth API is a fallback. This eliminates credential extraction, background HTTP requests, and cache management for users on current Claude Code versions.
- **Git commands** now use `--no-optional-locks` to prevent index lock contention.
- **Installer** now downloads `statusline-helper.js` alongside the main script (optional, failure does not block installation).

## [1.5.1] - 2026-03-12

### Changed

- **Safe Unicode icons** — replaced 6 problematic icons with universally compatible alternatives: `⚙`→`◆`, `⚡`→`▸`, `⚠`→`▲`, `⎇`→`⊞`, `⬆`→`↑`, dropped `◷` (duration needs no icon)
- **Dim progress bar shading** — empty `░` slots now use `CLR_DIM` for better contrast against filled `█` blocks
- **Coloured percentage text** — progress bar percentages now match the bar colour (green/yellow/red)
- **Cost colour tiers** — cost displays green under $1, yellow $1–$5, red $5+
- **Warning icon coloured** — context warning `▲` now uses `CLR_WARN` colour
- **Update notification** — changed from yellow to green
- **Usage cache interval** — reduced default from 30 minutes to 10 minutes for more accurate 5-hour readings

### Added

- **`CLR_DIM` theme variable** — new colour variable across all 7 themes for dimmed/secondary elements

## [1.5.0] - 2026-03-12

### Added

- **Model tier coloring** — model name colour varies by tier: Haiku=green, Sonnet=yellow, Opus=orange. Uses a case statement on the model name. Respects NO_COLOR and mono theme.
- **tokyo-night theme** — new colour theme inspired by the Tokyo Night colour palette
- **catppuccin theme** — new colour theme inspired by the Catppuccin colour palette

## [1.4.0] - 2026-03-12

### Added

- **`extract_block()` helper** — new function for extracting nested JSON object blocks by key, enabling access to `vim`, `agent`, `workspace`, and `context_window` sub-objects
- **Vim mode segment** (`show_vim_mode`) — shows NORMAL/INSERT from `vim.mode` in the JSON input (default: true)
- **Agent name segment** (`show_agent`) — shows the agent name from `agent.name` when running with `--agent` (default: true)
- **Token count segment** (`show_tokens`) — shows cumulative input/output tokens as `Xk in Yk out` from the `context_window` block (default: false, opt-in)
- **200k token warning** — automatic `⚠ 200k+` warning when `exceeds_200k_tokens` is true in the JSON input (no config toggle — always active)
- **`bar_width` config option** — configurable progress bar width in characters (default: 10), replaces previously hardcoded value
- **`branch_max_length` config option** — truncates long branch names with an ellipsis when set (default: empty = no limit)

### Changed

- **Directory segment** now prefers `workspace.current_dir` (extracted via `extract_block`) with fallback to top-level `cwd`
- `build_progress_bar()` now uses `bar_width` config instead of hardcoded width

## [1.3.0] - 2026-03-10

### Added

- **5-hour usage limit segment** (`show_usage_5h`) — shows rolling 5-hour utilization from the Anthropic API with a colour-coded progress bar and reset time label
- **7-day usage limit segment** (`show_usage_7d`) — shows rolling 7-day utilization with reset day and time
- **Pacing markers** — a `│` marker on usage bars shows where you *should* be for even consumption across the window; helps avoid hitting limits early
- **Usage cache** (`usage_cache_seconds`) — API responses cached to `~/.claude/.statusline-usage-cache`, refreshes every 60 seconds by default
- **Cross-platform credential reading** — macOS Keychain, Linux `~/.claude/.credentials.json`, Windows/MSYS2 `~/.claude/.credentials.json`
- **`CLR_PACE` theme variable** — pacing marker colour added to all themes (default, nord, dracula, solarized, mono)
- `http_get()` shared helper — consolidates curl/wget fallback pattern (was duplicated 3 times)
- `iso_to_epoch()` shared helper — consolidates cross-platform ISO timestamp parsing
- `umask 077` — cache and temp files are no longer world-readable
- Segment priority table documented in config section comments
- CHANGELOG.md

### Changed

- `build_progress_bar()` now accepts an optional second argument for a pacing target percentage
- `extract()` / `extract_num()` are now thin wrappers around `extract_from()` / `extract_num_from()` (consolidated from 4 independent functions to 2 + 2 wrappers)
- Usage API fetch runs in background subshell (never blocks the statusline)
- Usage cache uses embedded timestamp format (portable, no platform-specific `stat` needed)
- `input=$(cat)` kept for MSYS2 compatibility (`read -r -d ''` silently fails on Windows bash)
- Version reading uses `read -r` instead of `tr` (avoids fork)
- `NOW_EPOCH` cached once at startup (eliminates 5-9 repeated `date +%s` forks)
- Cost formatting uses `printf` builtin instead of `awk` subprocess

### Fixed

- **Security:** AWK code injection via cost values — now uses `-v` variable passing
- **Security:** OAuth token was visible in `ps aux` — curl now uses `--config -` to pass auth headers via stdin
- **Security:** wget followed redirects with Bearer token — added `--max-redirect=0`
- **Security:** `cwd` from JSON input was not sanitized before `git -C` — now passes through `sanitize()` and `[ -d ]` guard
- **Security:** ANSI sanitization now handles ST-terminated OSC sequences and DCS/APC escapes
- Cache file race condition when reading old-format or partially-written files
- `show_usage_weekly` renamed to `show_usage_7d` for naming consistency (old name still accepted via backwards compat shim)

## [1.2.0] - 2026-03-07

### Added

- Ahead/behind remote segment (`show_ahead_behind`)
- Stash count segment (`show_stash`)
- Context window size display (e.g., "45% of 200k")
- Context warning threshold (`context_warn_threshold`)
- Cost rate segment (`show_cost_rate`) — burn rate in $/hr
- Priority-based truncation for narrow terminals (`enable_truncation`, `max_width`)
- Segment grouping with configurable brackets (`use_groups`, `group_open`, `group_close`)
- Colour themes: nord, dracula, solarized, mono
- `NO_COLOR` environment variable support

## [1.1.0] - 2026-03-05

### Added

- Configurable segments with `show_*` toggles
- `auto_hide` — hide segments with zero/empty values
- `use_icons` — toggle unicode icons
- External config via `~/.claude/statusline.conf`
- Background update check with `⬆ update available` notification
- CLI flags: `--help`, `--version`, `--check-update`

## [1.0.0] - 2026-03-04

### Added

- Initial release
- Directory, branch, model, context bar, lines changed, dirty count, duration, worktree, cost segments
- Pure bash JSON parsing (no jq dependency)
- Cross-platform support (macOS, Linux, Windows/MSYS2)
- One-line installer
