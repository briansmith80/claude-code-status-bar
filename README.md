# claude-code-status-bar

A configurable statusline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows directory, git branch, model, context usage, lines changed, session cost, and more — all in one line.

```
~/projects/my-app on main  Sonnet  ████████░░ 78%  +42 -7  3 dirty  12m  $0.45
```

Pure bash. No dependencies. Works on macOS, Linux, and Windows (Git Bash / MSYS2).

## Install

One command. It downloads the script and updates your Claude Code settings automatically.

**macOS / Linux / Windows (Git Bash):**

```bash
curl -fsSL https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main/install.sh | bash
```

**Windows (PowerShell):**

```powershell
curl.exe -fsSL https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main/install.sh | bash
```

Restart Claude Code and the statusline appears.

## Per-project install

To install for a single project instead of globally, run this from the project root:

```bash
curl -fsSL https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main/install.sh | bash -s -- --local
```

## Segments

| Segment | Toggle | Description |
|---------|--------|-------------|
| Directory | `show_directory` | Working directory, shortened with `~` |
| Branch | `show_branch` | Current git branch or short SHA |
| Model | `show_model` | Active model name (Opus, Sonnet, Haiku) |
| Context bar | `show_context_bar` | Visual progress bar (green/yellow/red) |
| Lines changed | `show_lines_changed` | Lines added/removed in the session |
| Dirty count | `show_dirty_count` | Number of uncommitted files |
| Duration | `show_duration` | Session duration (Xh Ym) |
| Worktree | `show_worktree` | Worktree name when active |
| Cost | `show_cost` | Cumulative session cost in USD |

## Configuration

Edit the toggle variables at the top of `statusline-command.sh` (at `~/.claude/statusline-command.sh` for a global install):

```bash
show_directory=true
show_branch=true
show_model=true
show_context_bar=true
show_lines_changed=true
show_dirty_count=true
show_duration=true
show_worktree=true
show_cost=true
```

Set any to `false` to hide that segment.

## Manual install

If you prefer not to use the installer:

1. Download `statusline-command.sh` to `~/.claude/` (global) or `.claude/` (per-project)
2. Make it executable: `chmod +x statusline-command.sh`
3. Add to `~/.claude/settings.json` (global) or `.claude/settings.json` (per-project):

```json
{
  "statusline": {
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
```

## License

MIT
