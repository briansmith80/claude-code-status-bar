# claude-code-status-bar

A configurable status bar for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

```
~/projects/my-app on main  Sonnet  ████████░░ 78%  +42 -7  3 dirty  12m  $0.45
```

Pure bash. No dependencies. Works on macOS, Linux, and Windows (Git Bash / MSYS2).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main/install.sh | bash
```

Restart Claude Code and the status bar appears.

> **Windows (PowerShell):** use `curl.exe` instead of `curl`.

### Per-project install

To install for a single project instead of globally:

```bash
curl -fsSL https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main/install.sh | bash -s -- --local
```

### Manual install

1. Download `statusline-command.sh` to `~/.claude/`
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

To toggle segments, edit the variables at the top of `~/.claude/statusline-command.sh`:

```bash
show_directory=true
show_branch=true
show_model=true
# set any to false to hide
```

## License

MIT
