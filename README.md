# claude-code-status-bar

[![ShellCheck](https://github.com/briansmith80/claude-code-status-bar/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/briansmith80/claude-code-status-bar/actions/workflows/shellcheck.yml)
[![Version](https://img.shields.io/github/v/release/briansmith80/claude-code-status-bar?label=version)](https://github.com/briansmith80/claude-code-status-bar/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-brightgreen)](README.md)

A pure bash status bar for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows your API usage limits, context window, git state, session cost, and more — with pacing markers that tell you if you're burning through your quota too fast.

```
~/my-app on ↱ main  ⚙ Opus 4.6  ████████░░ 78% of 200k  5hr(2pm) ███│░░░░░░ 37%  wk(fri,3am) ██████░│░░ 72%  +42 -7  ● 3 dirty  ↓2 ↑1  ◷ 12m  $0.45
```

18 segments. 7 colour themes. Zero dependencies. One-line install. Works on macOS, Linux, and Windows (Git Bash / MSYS2).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main/install.sh | bash
```

The status bar appears automatically.

> **Windows (PowerShell):** use `curl.exe` instead of `curl`.

### Manual install

1. Download `statusline-command.sh` and `VERSION` to `~/.claude/`:

```bash
curl -fsSL https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main/statusline-command.sh -o ~/.claude/statusline-command.sh
curl -fsSL https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main/VERSION -o ~/.claude/.statusline-version
```

2. Make it executable: `chmod +x ~/.claude/statusline-command.sh`
3. Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
```

## Segments

| Segment | Toggle | Description |
|---------|--------|-------------|
| Directory | `show_directory` | Working directory (prefers `workspace.current_dir`, falls back to `cwd`) |
| Branch | `show_branch` | Current git branch or short SHA (truncated by `branch_max_length`) |
| Vim mode | `show_vim_mode` | Shows NORMAL/INSERT from `vim.mode` |
| Model | `show_model` | Active model with tier coloring (Haiku=green, Sonnet=yellow, Opus=orange; respects NO_COLOR) |
| Agent name | `show_agent` | Agent name when running with `--agent` |
| Context bar | `show_context_bar` | Progress bar with warning at threshold |
| 200k warning | *(automatic)* | Shows `⚠ 200k+` when `exceeds_200k_tokens` is true |
| Token count | `show_tokens` | Cumulative input/output tokens (`Xk in Yk out`) |
| 5-hour usage | `show_usage_5h` | Rolling 5-hour API usage with pacing marker |
| Weekly usage | `show_usage_7d` | Rolling 7-day API usage with pacing marker |
| Lines changed | `show_lines_changed` | Lines added/removed in session |
| Dirty count | `show_dirty_count` | Uncommitted file count |
| Ahead/behind | `show_ahead_behind` | Commits ahead/behind remote (`↓3 ↑1`) |
| Stash count | `show_stash` | Git stash count |
| Duration | `show_duration` | Session duration |
| Worktree | `show_worktree` | Worktree name when active |
| Cost | `show_cost` | Session cost in USD |
| Cost rate | `show_cost_rate` | Burn rate in $/hr |

## Configuration

Create `~/.claude/statusline.conf` with your overrides. This file is never overwritten by updates.

```bash
# ~/.claude/statusline.conf

# Segment toggles (true/false)
show_branch=false
show_cost=false

# New segments (v1.4.0)
show_vim_mode=true       # Vim mode indicator (default: true)
show_agent=true          # Agent name segment (default: true)
show_tokens=false        # Token counts — opt-in (default: false)

# Usage limit segments (default: true)
show_usage_5h=true
show_usage_7d=true
usage_cache_seconds=60

# Auto-hide segments with zero/empty values (default: true)
auto_hide=true

# Unicode icons before segments (default: true)
use_icons=false

# Colour theme: default, nord, dracula, solarized, mono, tokyo-night, catppuccin
colour_theme=nord

# Context warning threshold percentage (default: 80)
context_warn_threshold=85

# Progress bar width in characters (default: 10)
bar_width=10

# Truncate long branch names with ellipsis (default: "" = no limit)
branch_max_length=20

# Priority truncation for narrow terminals (default: false)
enable_truncation=true
max_width=100

# Segment grouping with brackets (default: false)
use_groups=true
group_open="["
group_close="]"
```

The `NO_COLOR` environment variable is respected — when set, all colours are disabled regardless of theme.

## Usage Limits

The status bar shows your Anthropic API usage limits with colour-coded progress bars:

```
5hr(2pm) ▓▓▓│░░░░░░ 37%  wk(fri,3am) ██░░░░│░░░ 29%
```

- **5hr** — rolling 5-hour usage window, with reset time
- **wk** — rolling 7-day usage window, with reset day and time
- **`│` pacing marker** — shows where you *should* be for even usage across the window; if your bar is past the marker, you're ahead of pace

Usage data is fetched from the Anthropic OAuth API and cached locally (default: every 60 seconds). If credentials are missing or the API is unreachable, the usage segments are silently hidden.

### Credentials

The script reads your Claude Code OAuth token automatically:

| Platform | Credential source |
|----------|------------------|
| macOS | Keychain (`Claude Code-credentials`) |
| Linux | `~/.claude/.credentials.json` |
| Windows / MSYS2 | `~/.claude/.credentials.json` |

Your token must have the `user:profile` scope. This is included automatically when you sign in via the browser. If usage data doesn't appear, quit all Claude Code instances and restart — this triggers a fresh OAuth login with the correct scopes.

### Troubleshooting usage limits

If usage segments don't appear:

1. Check that credentials exist:
   ```bash
   # Linux / Windows
   cat ~/.claude/.credentials.json | grep accessToken

   # macOS
   security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | grep accessToken
   ```

2. Delete stale cache and let it refresh:
   ```bash
   rm -f ~/.claude/.statusline-usage-cache
   ```

3. If your token was created with `claude setup-token`, it only has `user:inference` scope. Delete the credentials and restart Claude Code for a browser OAuth flow.

## Updating

When a new version is available, you'll see `⬆ update available` in your status bar. To update, run the same install command:

```bash
curl -fsSL https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main/install.sh | bash
```

The installer detects the existing installation and updates in place. The update notification checks GitHub every 6 hours and runs in the background — it never slows down your status bar.

To manually check for updates and see the install command:

```bash
bash ~/.claude/statusline-command.sh --check-update
# Current: 1.0.0
# Latest:  1.1.0
#
# Update available! Run:
#   curl -fsSL https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main/install.sh | bash
```

## CLI Flags

```bash
bash ~/.claude/statusline-command.sh --help          # show usage info
bash ~/.claude/statusline-command.sh --version        # print version
bash ~/.claude/statusline-command.sh --check-update   # force update check
```

## Uninstall

```bash
rm -f ~/.claude/statusline-command.sh
rm -f ~/.claude/statusline.conf
rm -f ~/.claude/.statusline-version
rm -f ~/.claude/.statusline-update-cache
rm -f ~/.claude/.statusline-usage-cache
```

Then remove the `"statusLine"` block from `~/.claude/settings.json`.

## License

MIT
