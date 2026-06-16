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

# ── Config template ────────────────────────────────────────────
# Ship a commented reference template (always refreshed) and create the live
# statusline.conf from it on first install ONLY — never overwrite an existing
# one (user config survives updates). Every line in it is commented, so a fresh
# copy changes nothing; it just makes the options discoverable and editable.
conf_example="${target_dir}/statusline.conf.example"
conf_file="${target_dir}/statusline.conf"
if command -v curl > /dev/null 2>&1; then
  curl -fsSL "${REPO_RAW}/statusline.conf.example" -o "$conf_example" 2>/dev/null || true
elif command -v wget > /dev/null 2>&1; then
  wget -qO "$conf_example" "${REPO_RAW}/statusline.conf.example" 2>/dev/null || true
fi
if [ -f "$conf_example" ] && [ ! -f "$conf_file" ]; then
  cp "$conf_example" "$conf_file"
  echo "  Config created: ${conf_file} (commented — edit to customise)"
elif [ -f "$conf_file" ]; then
  echo "  Config kept: ${conf_file} (new options are in statusline.conf.example)"
fi

# ── Update settings.json ─────────────────────────────────────
# On Windows, settings.json needs native paths (C:/...): Claude Code spawns
# these commands via PowerShell or cmd when Git Bash is missing, and native
# node resolves an MSYS path like /c/Users/... to C:\c\Users\... and dies.
settings_script_path="$target_file"
settings_subagent_path="${target_dir}/statusline-subagent.js"
if command -v cygpath > /dev/null 2>&1; then
  settings_script_path=$(cygpath -m "$settings_script_path" 2>/dev/null || echo "$settings_script_path")
  settings_subagent_path=$(cygpath -m "$settings_subagent_path" 2>/dev/null || echo "$settings_subagent_path")
fi

# Quote the script paths so the commands survive profile dirs with spaces
# (e.g. C:/Users/John Smith) under every spawn shell (bash, PowerShell, cmd)
command_value="bash \"${settings_script_path}\""
# Subagent panel rows need Node.js; only wire them when node is available
subagent_value=""
if command -v node > /dev/null 2>&1; then
  subagent_value="node \"${settings_subagent_path}\""
fi
# JSON-escaped copies for contexts that write raw JSON text
command_value_json=${command_value//\"/\\\"}
subagent_value_json=${subagent_value//\"/\\\"}

if [ ! -f "$settings_file" ]; then
  if [ -n "$subagent_value" ]; then
    cat > "$settings_file" <<EOF
{
  "statusLine": {
    "type": "command",
    "command": "${command_value_json}",
    "refreshInterval": 60
  },
  "subagentStatusLine": {
    "type": "command",
    "command": "${subagent_value_json}"
  }
}
EOF
  else
    cat > "$settings_file" <<EOF
{
  "statusLine": {
    "type": "command",
    "command": "${command_value_json}",
    "refreshInterval": 60
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
    if (!data.statusLine) { data.statusLine = { type: 'command', command: process.argv[2], refreshInterval: 60 }; added.push('statusLine'); }
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
data['statusLine'] = {'type': 'command', 'command': cmd, 'refreshInterval': (data.get('statusLine') or {}).get('refreshInterval', 60)}
with open(path, 'w') as f: json.dump(data, f, indent=2); f.write('\n')
" "$settings_file" "$command_value"
  echo "  Updated settings: ${settings_file}"
elif command -v python > /dev/null 2>&1; then
  python -c "
import json, sys
path, cmd = sys.argv[1], sys.argv[2]
with open(path) as f: data = json.load(f)
data['statusLine'] = {'type': 'command', 'command': cmd, 'refreshInterval': (data.get('statusLine') or {}).get('refreshInterval', 60)}
with open(path, 'w') as f: json.dump(data, f, indent=2); f.write('\n')
" "$settings_file" "$command_value"
  echo "  Updated settings: ${settings_file}"
else
  echo ""
  echo "  Could not update settings automatically."
  echo "  Add this to ${settings_file} manually:"
  echo ""
  echo "    \"statusLine\": { \"type\": \"command\", \"command\": \"${command_value_json}\", \"refreshInterval\": 60 }"
fi

# ── Migrate: ensure the statusLine block carries a refreshInterval ──
# Installs predating v2.10.1 created a statusLine block with no refreshInterval,
# so the bar only updated on a new message — countdown labels and the live
# activity line went stale while idle, and statusline.conf edits didn't show
# until the next message. Add the default to an existing block that lacks one;
# a refreshInterval the user already set is never touched. Idempotent.
if [ -f "$settings_file" ] && grep -q '"statusLine"' "$settings_file"; then
  if command -v node > /dev/null 2>&1; then
    node -e "
      const fs = require('fs');
      const f = process.argv[1];
      const data = JSON.parse(fs.readFileSync(f, 'utf8'));
      const sl = data.statusLine;
      if (sl && typeof sl === 'object' && sl.refreshInterval === undefined) {
        sl.refreshInterval = 60;
        fs.writeFileSync(f, JSON.stringify(data, null, 2) + '\n');
        console.log('  Added statusLine.refreshInterval (60): ' + f);
      }
    " "$settings_file" 2>/dev/null || true
  elif command -v python3 > /dev/null 2>&1 || command -v python > /dev/null 2>&1; then
    py=python3; command -v python3 > /dev/null 2>&1 || py=python
    "$py" -c "
import json, sys
path = sys.argv[1]
with open(path) as f: data = json.load(f)
sl = data.get('statusLine')
if isinstance(sl, dict) and 'refreshInterval' not in sl:
    sl['refreshInterval'] = 60
    with open(path, 'w') as f: json.dump(data, f, indent=2); f.write('\n')
    print('  Added statusLine.refreshInterval (60): ' + path)
" "$settings_file" 2>/dev/null || true
  fi
fi

# ── Migrate commands written by older installs (Windows) ─────
# Pre-2.6.1 installs wrote MSYS-style paths (e.g. "node /c/Users/..."), which
# fail when Claude Code spawns the command via PowerShell or cmd instead of
# Git Bash, and unquoted paths, which break on profile dirs with spaces.
# Rewrite only exact matches of this installer's own old commands; customised
# entries are never touched.
if [ -f "$settings_file" ] && [ -n "$subagent_value" ] \
  && command -v cygpath > /dev/null 2>&1; then
  node -e "
    const fs = require('fs');
    const [file, newBash, oldBash1, oldBash2, newNode, oldNode1, oldNode2] = process.argv.slice(1);
    const data = JSON.parse(fs.readFileSync(file, 'utf8'));
    const migrated = [];
    const fix = (key, fresh, ...old) => {
      const entry = data[key];
      if (entry && old.includes(entry.command)) { entry.command = fresh; migrated.push(key); }
    };
    fix('statusLine', newBash, oldBash1, oldBash2);
    fix('subagentStatusLine', newNode, oldNode1, oldNode2);
    if (migrated.length) {
      fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
      console.log('  Migrated to Windows-native quoted paths (' + migrated.join(', ') + '): ' + file);
    }
  " "$settings_file" \
    "$command_value" "bash ${target_file}" "bash ${settings_script_path}" \
    "$subagent_value" "node ${target_dir}/statusline-subagent.js" "node ${settings_subagent_path}" \
    || echo "  Settings migration check skipped (could not parse settings.json)."
fi

# ── Clear update cache ────────────────────────────────────────
rm -f "${target_dir}/.statusline-update-cache"

echo ""
echo "Done! Your status bar should appear automatically."
