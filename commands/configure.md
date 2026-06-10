---
description: Customize your claude-code-status-bar settings
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
---

# claude-code-status-bar Configuration

You are helping the user customize their status bar. The config file is `~/.claude/statusline.conf`.

## Step 1: Read Current Config

```bash
conf_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline.conf"
if [ -f "$conf_file" ]; then
  echo "Current config:"
  cat "$conf_file"
else
  echo "No config file yet — using defaults."
fi
```

## Step 2: Ask What to Change

Ask the user what they'd like to customize. Present these categories:

### Themes
- `colour_theme` — Pick one of: `default`, `nord`, `dracula`, `solarized`, `tokyo-night`, `catppuccin`, `mono` (default: default)

### Segments (toggle on/off)
- `show_directory` — Working directory
- `show_branch` — Git branch
- `show_model` — Model name (tier-colored)
- `show_context_bar` — Context window progress bar
- `show_lines_changed` — Lines added/removed
- `show_dirty_count` — Uncommitted file count
- `show_ahead_behind` — Commits ahead/behind remote
- `show_stash` — Git stash count
- `show_duration` — Session duration
- `show_worktree` — Worktree indicator
- `show_cost` — Session cost in USD
- `show_cost_rate` — Cost per hour (off by default)
- `show_usage_5h` — 5-hour usage limit
- `show_usage_7d` — 7-day usage limit
- `show_pr` — Open pull request number, coloured by review state (needs Claude Code 2.1.145+)
- `show_tokens` — Token counts (off by default)
- `show_effort` — Reasoning effort level, e.g. eff:xhigh (needs Claude Code 2.1.133+)
- `show_fast_mode` — Fast mode indicator while fast mode is on
- `show_vim_mode` — Vim mode indicator
- `show_agent` — Agent name
- `show_activity` — Live activity line (tools, agents, todos)

### Display Options
- `use_icons` — Unicode icons before segments (default: true)
- `auto_hide` — Hide zero/empty values (default: true)
- `usage_label` — Usage bar reset label: clock, e.g. 2pm (default), or countdown, e.g. 2h20m
- `activity_ttl_seconds` — Hide the live activity line when its cache is older than this (default: 120)
- `subagent_rows` — Set to false to keep Claude Code's default subagent panel rows (default: true)
- `usage_cache_seconds` — OAuth fallback refresh interval in seconds; ignored when stdin provides rate limits (default: 600)
- `bar_width` — Progress bar width in characters (default: 10)
- `branch_max_length` — Truncate long branch names (default: unlimited)
- `context_warn_threshold` — auto = warn within 20k tokens of Claude Code's auto-compact point (default); or a raw percentage like 80
- `enable_truncation` — Drop segments on narrow terminals (default: false)
- `max_width` — Override terminal width for truncation

### Grouping
- `use_groups` — Wrap related segments in brackets (default: false)
- `group_open` / `group_close` — Bracket characters (default: `[` / `]`)

## Step 3: Apply Changes

Write the user's preferences to `~/.claude/statusline.conf`. Only include settings that differ from defaults. Format as `key=value`, one per line, with comments.

## Step 4: Test

```bash
echo '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":65},"total_cost_usd":1.50}' | bash ~/.claude/statusline-command.sh
```

Tell the user the changes will take effect after the next Claude Code response.
