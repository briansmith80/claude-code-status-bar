# Changelog

All notable changes to this project will be documented in this file.

## [1.3.0] - 2026-03-10

### Added

- **5-hour usage limit segment** (`show_usage_5h`) — shows rolling 5-hour utilization from the Anthropic API with a colour-coded progress bar and reset time label
- **Weekly usage limit segment** (`show_usage_weekly`) — shows rolling 7-day utilization with reset day and time
- **Pacing markers** — a `│` marker on usage bars shows where you *should* be for even consumption across the window; helps avoid hitting limits early
- **Usage cache** (`usage_cache_seconds`) — API responses cached to `~/.claude/.statusline-usage-cache`, refreshes every 60 seconds by default
- **Cross-platform credential reading** — macOS Keychain, Linux `~/.claude/.credentials.json`, Windows/MSYS2 `~/.claude/.credentials.json`
- **`CLR_PACE` theme variable** — pacing marker colour added to all themes (default, nord, dracula, solarized, mono)
- **`extract_from()` / `extract_num_from()` helpers** — JSON parsing from arbitrary strings (not just stdin), used by usage API parsing
- CHANGELOG.md

### Changed

- `build_progress_bar()` now accepts an optional second argument for a pacing target percentage

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
