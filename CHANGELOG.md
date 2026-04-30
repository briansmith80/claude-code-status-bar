# Changelog

All notable changes to this project will be documented in this file.

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
