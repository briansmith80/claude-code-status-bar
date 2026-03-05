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
elif command -v wget > /dev/null 2>&1; then
  wget -qO "$version_file" "${REPO_RAW}/VERSION"
  VERSION=$(tr -d '[:space:]' < "$version_file")

  if [ -f "$target_file" ]; then
    echo "Updating claude-code-status-bar to v${VERSION}..."
  else
    echo "Installing claude-code-status-bar v${VERSION}..."
  fi

  wget -qO "$target_file" "${REPO_RAW}/${SCRIPT_NAME}"
else
  echo "Error: curl or wget is required."
  exit 1
fi

chmod +x "$target_file"
echo "  Script installed to: ${target_file}"
echo "  Version: ${VERSION}"

# ── Update settings.json ─────────────────────────────────────
command_value="bash ${target_file}"

if [ ! -f "$settings_file" ]; then
  cat > "$settings_file" <<EOF
{
  "statusLine": {
    "type": "command",
    "command": "${command_value}"
  }
}
EOF
  echo "  Created settings: ${settings_file}"
elif grep -q '"statusLine"' "$settings_file"; then
  echo "  settings.json already has a statusLine entry — skipped."
elif command -v node > /dev/null 2>&1; then
  node -e "
    const fs = require('fs');
    const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
    data.statusLine = { type: 'command', command: process.argv[2] };
    fs.writeFileSync(process.argv[1], JSON.stringify(data, null, 2) + '\n');
  " "$settings_file" "$command_value"
  echo "  Updated settings: ${settings_file}"
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
