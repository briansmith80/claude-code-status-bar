---
description: Install and configure claude-code-status-bar as your statusline
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
---

# claude-code-status-bar Setup

You are setting up the claude-code-status-bar plugin. Follow these steps exactly.

## Step 1: Detect Environment

Run these commands to detect the platform and locate the plugin:

```bash
echo "OS: $(uname -s)" && echo "Shell: $SHELL" && echo "Home: $HOME"
```

Find the plugin installation directory:

```bash
plugin_dir=""
for d in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/claude-code-status-bar/claude-code-status-bar/*/; do
  [ -d "$d" ] && plugin_dir="$d"
done
echo "Plugin dir: ${plugin_dir:-NOT FOUND}"
```

## Step 2: Install Files

Copy the statusline script and helper to ~/.claude/:

```bash
target_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
cp "${plugin_dir}statusline-command.sh" "${target_dir}/statusline-command.sh"
chmod +x "${target_dir}/statusline-command.sh"

# Copy Node.js helpers: live activity line + subagent panel rows
# (optional but recommended)
if [ -f "${plugin_dir}statusline-helper.js" ]; then
  cp "${plugin_dir}statusline-helper.js" "${target_dir}/statusline-helper.js"
fi
if [ -f "${plugin_dir}statusline-subagent.js" ]; then
  cp "${plugin_dir}statusline-subagent.js" "${target_dir}/statusline-subagent.js"
fi

# Copy version file
if [ -f "${plugin_dir}VERSION" ]; then
  cp "${plugin_dir}VERSION" "${target_dir}/.statusline-version"
fi

# Commented config template: always refresh the reference, and create the live
# statusline.conf from it on first install only — never overwrite an existing one.
if [ -f "${plugin_dir}statusline.conf.example" ]; then
  cp "${plugin_dir}statusline.conf.example" "${target_dir}/statusline.conf.example"
  [ -f "${target_dir}/statusline.conf" ] || cp "${plugin_dir}statusline.conf.example" "${target_dir}/statusline.conf"
fi

echo "Files installed to ${target_dir}"
```

## Step 3: Configure Settings

Read the current settings.json and merge in the statusLine configuration:

```bash
target_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings_file="${target_dir}/settings.json"
command_value="bash ${target_dir}/statusline-command.sh"
```

If settings.json doesn't exist, create it. If it exists and already has a statusLine entry, ask the user if they want to replace it. Otherwise, merge the statusLine key using node/python.

The statusLine config should be:
```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh",
    "refreshInterval": 60
  }
}
```

`refreshInterval` (seconds) controls how often Claude Code re-runs the bar while idle — without it, the countdown labels and live-activity line only update on a new message. Recommended: `2`+ on Windows, `1` on macOS/Linux (a value below the script's runtime blanks the bar). Set a low odd value like `3` if the user enables `activity_pulse`/`activity_scanner` (see Step 5).

When Node.js is available, also merge a subagentStatusLine entry (skip if one already exists, asking the user before replacing). This styles the agent panel rows shown while Task-tool subagents run (Claude Code draws workflow and background-task rows itself):
```json
{
  "subagentStatusLine": {
    "type": "command",
    "command": "node ~/.claude/statusline-subagent.js"
  }
}
```

On Windows, write the expanded Windows-native path, quoted, instead of `~` (for example `node \"C:/Users/name/.claude/statusline-subagent.js\"`). Claude Code may spawn this command via PowerShell or cmd, which do not expand `~` or resolve MSYS-style `/c/...` paths for node, making the renderer fail silently; quoting keeps the command working when the profile directory contains spaces. The same applies to the statusLine entry: prefer `bash \"C:/Users/name/.claude/statusline-command.sh\"`.

## Step 4: Test

Run a quick test to verify the status bar works:

```bash
echo '{"cwd":"/tmp","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":42},"total_cost_usd":0.25}' | bash ~/.claude/statusline-command.sh
```

If the output shows a formatted status line with colors, the installation is successful.

## Step 5: Optional Configuration

Ask the user if they want to customize their status bar. Available options:

- **Theme**: default, nord, dracula, solarized, tokyo-night, catppuccin, matrix, mono (preview them all first with `bash ~/.claude/statusline-command.sh --demo`)
- **Layout**: `layout=three-line` or `stacked` spreads the bar across up to three lines (default `classic` is the single metrics line + activity line); or hand-build `line1`/`line2`/`line3` from segment tokens (quote values with spaces). `icon_set=modern` switches to the refreshed icon set.
- **Live activity line**: Shows running tools, agents, and todo progress (enabled by default, requires Node.js)
- **Usage pacing markers**: Shows where usage should be for even consumption (enabled by default)
- **Toggle segments**: Each segment can be turned on/off
- **Animated effects** (`activity_pulse`, `activity_scanner`): opt-in motion on line 2, off by default. If the user enables either, also set `refreshInterval: 3` on the `statusLine` block in `settings.json` (they only animate when the bar re-renders often; on the default interval they sit static). Merge it in without touching the rest of the block.

If the user wants customization, create or update `~/.claude/statusline.conf` with their preferences.

## Step 6: Done

Tell the user:
- The status bar will appear after the next Claude Code response
- To customize, edit `~/.claude/statusline.conf`
- To update, run `/claude-code-status-bar:setup` again
- Full documentation at https://github.com/briansmith80/claude-code-status-bar
