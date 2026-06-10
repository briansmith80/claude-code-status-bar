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
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
```

When Node.js is available, also merge a subagentStatusLine entry (skip if one already exists, asking the user before replacing). This styles the agent panel rows shown while subagents run:
```json
{
  "subagentStatusLine": {
    "type": "command",
    "command": "node ~/.claude/statusline-subagent.js"
  }
}
```

## Step 4: Test

Run a quick test to verify the status bar works:

```bash
echo '{"cwd":"/tmp","model":{"display_name":"Sonnet"},"context_window":{"used_percentage":42},"total_cost_usd":0.25}' | bash ~/.claude/statusline-command.sh
```

If the output shows a formatted status line with colors, the installation is successful.

## Step 5: Optional Configuration

Ask the user if they want to customize their status bar. Available options:

- **Theme**: default, nord, dracula, solarized, tokyo-night, catppuccin, mono
- **Live activity line**: Shows running tools, agents, and todo progress (enabled by default, requires Node.js)
- **Usage pacing markers**: Shows where usage should be for even consumption (enabled by default)
- **Toggle segments**: Each segment can be turned on/off

If the user wants customization, create or update `~/.claude/statusline.conf` with their preferences.

## Step 6: Done

Tell the user:
- The status bar will appear after the next Claude Code response
- To customize, edit `~/.claude/statusline.conf`
- To update, run `/claude-code-status-bar:setup` again
- Full documentation at https://github.com/briansmith80/claude-code-status-bar
