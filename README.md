# claude-code-status-bar

A configurable statusline script for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows directory, git branch, model, context usage, lines changed, dirty count, duration, worktree, and cost — all in one line.

```
~/projects/my-app on main  Opus  ████████░░ 78%  +42 -7  3 dirty  12m  $0.45
```

Pure bash. No jq required. Works on macOS, Linux, and Windows (MSYS2/Git Bash).

## Install

**One-liner (global):**

```bash
curl -fsSL https://raw.githubusercontent.com/briansmith_80/claude-code-status-bar/main/install.sh | bash
```

**Per-project:**

```bash
curl -fsSL https://raw.githubusercontent.com/briansmith_80/claude-code-status-bar/main/install.sh | bash -s -- --local
```

**Manual:**

1. Download `statusline-command.sh` to `~/.claude/` (global) or `.claude/` (per-project)
2. Make it executable: `chmod +x statusline-command.sh`
3. Add to your Claude Code settings (see below)

## Enable in Claude Code

Add this to `~/.claude/settings.json` (global) or `.claude/settings.json` (per-project):

```json
{
  "statusline": {
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
```

## Segments

| Segment | Toggle | Description |
|---------|--------|-------------|
| Directory | `show_directory` | Working directory, shortened with `~` |
| Branch | `show_branch` | Current git branch or short SHA |
| Model | `show_model` | Active model name (Opus, Sonnet, Haiku) |
| Context bar | `show_context_bar` | Visual progress bar with colour thresholds (green/yellow/red) |
| Lines changed | `show_lines_changed` | Lines added/removed in the session |
| Dirty count | `show_dirty_count` | Number of uncommitted files |
| Duration | `show_duration` | Session duration (Xh Ym) |
| Worktree | `show_worktree` | Worktree name when active |
| Cost | `show_cost` | Cumulative session cost in USD |

## Configuration

Edit the toggle variables at the top of `statusline-command.sh`:

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

## JSON Input Schema

Claude Code pipes JSON to the script via stdin on each refresh. The script extracts these fields:

| Field | Path | Type | Description |
|-------|------|------|-------------|
| `current_dir` | `workspace.current_dir` | string | Working directory |
| `display_name` | `model.display_name` | string | Model name |
| `used_percentage` | `context.used_percentage` | number | Context window usage (0-100) |
| `total_cost_usd` | `session.total_cost_usd` | number | Cumulative cost |
| `total_lines_added` | `session.total_lines_added` | number | Lines added |
| `total_lines_removed` | `session.total_lines_removed` | number | Lines removed |
| `total_duration_ms` | `session.total_duration_ms` | number | Session duration in ms |
| `worktree.name` | `worktree.name` | string | Worktree name (when active) |

## Platform Compatibility

- **macOS** — works out of the box
- **Linux** — works out of the box
- **Windows** — works in MSYS2/Git Bash (ships with Claude Code); no jq needed

## License

MIT
