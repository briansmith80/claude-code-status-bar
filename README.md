# claude-code-status-bar

[![ShellCheck](https://github.com/briansmith80/claude-code-status-bar/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/briansmith80/claude-code-status-bar/actions/workflows/shellcheck.yml)
[![Version](https://img.shields.io/github/v/release/briansmith80/claude-code-status-bar?label=version)](https://github.com/briansmith80/claude-code-status-bar/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-brightgreen)](README.md)

A configurable status bar for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

```
~/projects/my-app on main  Sonnet  ████████░░ 78%  +42 -7  3 dirty  12m  $0.45
```

Pure bash. No dependencies. Works on macOS, Linux, and Windows (Git Bash / MSYS2).

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
| Directory | `show_directory` | Working directory, shortened with `~` |
| Branch | `show_branch` | Current git branch or short SHA |
| Model | `show_model` | Active model (Opus, Sonnet, Haiku) |
| Context bar | `show_context_bar` | Progress bar (green/yellow/red) |
| Lines changed | `show_lines_changed` | Lines added/removed in session |
| Dirty count | `show_dirty_count` | Uncommitted file count |
| Duration | `show_duration` | Session duration |
| Worktree | `show_worktree` | Worktree name when active |
| Cost | `show_cost` | Session cost in USD |

To customise, create `~/.claude/statusline.conf` with only the toggles you want to change. This file is never overwritten by updates.

```bash
# ~/.claude/statusline.conf
show_branch=false
show_cost=false
```

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
```

Then remove the `"statusLine"` block from `~/.claude/settings.json`.

## License

MIT
