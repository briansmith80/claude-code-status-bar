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
- `colour_theme` — Pick one of: `default`, `nord`, `dracula`, `solarized`, `tokyo-night`, `catppuccin`, `matrix`, `mono` (default: default). Tip: preview every theme (with its gradient bars) in the terminal first by running `bash ~/.claude/statusline-command.sh --demo`.

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
- `bar_gradient` — Progress-bar gradient (default: true). `true` = the theme's own gradient ramp; `false` = flat single-colour bars; `heat` = a fixed green→yellow→orange→red ramp regardless of theme
- `auto_hide` — Hide zero/empty values (default: true)
- `usage_label` — Usage bar reset label: countdown, e.g. 2h20m (default), or clock, e.g. 2pm
- `activity_ttl_seconds` — Hide the live activity line when its cache is older than this (default: 120)
- `activity_colour` — Per-segment theme colours on the activity line: spinner on running tools, heat-coloured elapsed times, red failures, completion flash, gradient todo bar. Set false for the classic all-dim line (default: true)
- `activity_fresh_seconds` — Drop the activity line back to all-dim when its data is older than this, so stale info reads as stale (default: 45)
- `activity_pulse` — Opt-in: the running tool/agent label breathes (alternates bold/faint each re-render) (default: false). Needs a low odd `refreshInterval` such as 3 to animate; this command offers to set that for you (see below).
- `activity_scanner` — Opt-in: a small sweeping tracker bar appears on line 2 while something has been running over 30 seconds (default: false). Needs a low `refreshInterval` such as 3 to animate (see below).

**If the user enables `activity_pulse` or `activity_scanner`, offer to set `refreshInterval: 3` for them.** These effects are wall-clock driven, so they only animate when the bar re-renders often; on the default `refreshInterval` of 60 they sit static (not broken, just not moving). A value of `3` is low enough to animate, odd (so the pulse alternates instead of getting stuck on one beat), and safe on every platform (comfortably above the script's runtime). If the user agrees, merge `refreshInterval` into the existing `statusLine` block in `settings.json` without disturbing anything else, for example:

```bash
settings_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
node -e '
const fs=require("fs"), f=process.argv[1];
const s=JSON.parse(fs.readFileSync(f,"utf8"));
if(!s.statusLine){console.error("No statusLine entry yet. Run /claude-code-status-bar:setup first."); process.exit(1);}
s.statusLine.refreshInterval=3;
fs.writeFileSync(f, JSON.stringify(s,null,2)+"\n");
console.log("Set statusLine.refreshInterval=3");
' "$settings_file"
```

(No Node.js available? Edit `settings.json` directly to add `"refreshInterval": 3` inside the `statusLine` block.) If the user would rather keep their current interval, leave it and tell them the effect stays static until they lower it.
- `pr_link` — Wrap the PR segment in an OSC 8 hyperlink to the pull request (clickable in terminals that support links) (default: true)
- `subagent_rows` — Set to false to keep Claude Code's default subagent panel rows (default: true)
- `usage_cache_seconds` — OAuth fallback refresh interval in seconds; ignored when stdin provides rate limits (default: 600)
- `auto_update` — Opt-in: when a newer version is detected, download and install it automatically in the background (atomic; never touches statusline.conf or settings.json) (default: false)
- `bar_width` — Progress bar width in characters (default: 10)
- `branch_max_length` — Truncate long branch names (default: unlimited)
- `dir_style` — Directory display: `auto` (full path when the line fits the terminal width, basename when it would overflow; the default), `full` (always the whole path), or `basename` (just the last folder)
- `context_warn_threshold` — auto = warn within 20k tokens of Claude Code's auto-compact point (default); or a raw percentage like 80
- `enable_truncation` — Drop low-priority segments when the line is too wide for the terminal (default: true; pairs with `dir_style=auto` so the path collapses before any segment is dropped)
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
