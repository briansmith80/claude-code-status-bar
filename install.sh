#!/usr/bin/env bash
#
# Claude Code Status Bar — Installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main/install.sh | bash

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main"
SCRIPT_NAME="statusline-command.sh"

target_dir="$HOME/.claude"
target_file="${target_dir}/${SCRIPT_NAME}"
settings_file="${target_dir}/settings.json"

# ── Download files ─────────────────────────────────────────────
version_file="${target_dir}/.statusline-version"

mkdir -p "$target_dir"

# Download VERSION first so we can display it
if command -v curl > /dev/null 2>&1; then
  curl -fsSL "${REPO_RAW}/VERSION" -o "$version_file"
  VERSION=$(tr -d '[:space:]' < "$version_file")

  if [ -f "$target_file" ]; then
    echo "Updating claude-code-status-bar to v${VERSION}..."
  else
    echo "Installing claude-code-status-bar v${VERSION}..."
  fi

  curl -fsSL "${REPO_RAW}/${SCRIPT_NAME}" -o "$target_file"
  # Download Node.js helpers: live activity line + subagent panel rows (optional)
  curl -fsSL "${REPO_RAW}/statusline-helper.js" -o "${target_dir}/statusline-helper.js" 2>/dev/null || true
  curl -fsSL "${REPO_RAW}/statusline-subagent.js" -o "${target_dir}/statusline-subagent.js" 2>/dev/null || true
elif command -v wget > /dev/null 2>&1; then
  wget -qO "$version_file" "${REPO_RAW}/VERSION"
  VERSION=$(tr -d '[:space:]' < "$version_file")

  if [ -f "$target_file" ]; then
    echo "Updating claude-code-status-bar to v${VERSION}..."
  else
    echo "Installing claude-code-status-bar v${VERSION}..."
  fi

  wget -qO "$target_file" "${REPO_RAW}/${SCRIPT_NAME}"
  # Download Node.js helpers: live activity line + subagent panel rows (optional)
  wget -qO "${target_dir}/statusline-helper.js" "${REPO_RAW}/statusline-helper.js" 2>/dev/null || true
  wget -qO "${target_dir}/statusline-subagent.js" "${REPO_RAW}/statusline-subagent.js" 2>/dev/null || true
else
  echo "Error: curl or wget is required."
  exit 1
fi

chmod +x "$target_file"
echo "  Script installed to: ${target_file}"
echo "  Version: ${VERSION}"

# ── Update settings.json ─────────────────────────────────────
command_value="bash ${target_file}"
# Subagent panel rows need Node.js; only wire them when node is available
subagent_value=""
if command -v node > /dev/null 2>&1; then
  subagent_value="node ${target_dir}/statusline-subagent.js"
fi

if [ ! -f "$settings_file" ]; then
  if [ -n "$subagent_value" ]; then
    cat > "$settings_file" <<EOF
{
  "statusLine": {
    "type": "command",
    "command": "${command_value}"
  },
  "subagentStatusLine": {
    "type": "command",
    "command": "${subagent_value}"
  }
}
EOF
  else
    cat > "$settings_file" <<EOF
{
  "statusLine": {
    "type": "command",
    "command": "${command_value}"
  }
}
EOF
  fi
  echo "  Created settings: ${settings_file}"
elif grep -q '"statusLine"' "$settings_file" && { [ -z "$subagent_value" ] || grep -q '"subagentStatusLine"' "$settings_file"; }; then
  echo "  settings.json already configured — skipped."
elif command -v node > /dev/null 2>&1; then
  node -e "
    const fs = require('fs');
    const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
    const added = [];
    if (!data.statusLine) { data.statusLine = { type: 'command', command: process.argv[2] }; added.push('statusLine'); }
    if (process.argv[3] && !data.subagentStatusLine) { data.subagentStatusLine = { type: 'command', command: process.argv[3] }; added.push('subagentStatusLine'); }
    if (added.length) {
      fs.writeFileSync(process.argv[1], JSON.stringify(data, null, 2) + '\n');
      console.log('  Updated settings (' + added.join(', ') + '): ' + process.argv[1]);
    } else {
      console.log('  settings.json already configured — skipped.');
    }
  " "$settings_file" "$command_value" "$subagent_value"
elif command -v python3 > /dev/null 2>&1; then
  python3 -c "
import json, sys
path, cmd = sys.argv[1], sys.argv[2]
with open(path) as f: data = json.load(f)
data['statusLine'] = {'type': 'command', 'command': cmd}
with open(path, 'w') as f: json.dump(data, f, indent=2); f.write('\n')
" "$settings_file" "$command_value"
  echo "  Updated settings: ${settings_file}"
elif command -v python > /dev/null 2>&1; then
  python -c "
import json, sys
path, cmd = sys.argv[1], sys.argv[2]
with open(path) as f: data = json.load(f)
data['statusLine'] = {'type': 'command', 'command': cmd}
with open(path, 'w') as f: json.dump(data, f, indent=2); f.write('\n')
" "$settings_file" "$command_value"
  echo "  Updated settings: ${settings_file}"
else
  echo ""
  echo "  Could not update settings automatically."
  echo "  Add this to ${settings_file} manually:"
  echo ""
  echo "    \"statusLine\": { \"type\": \"command\", \"command\": \"${command_value}\" }"
fi

# ── Clear update cache ────────────────────────────────────────
rm -f "${target_dir}/.statusline-update-cache"

echo ""
echo "Done! Your status bar should appear automatically."
