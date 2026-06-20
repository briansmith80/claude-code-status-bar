#!/usr/bin/env bash
#
# Claude Code Status Bar — Installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main/install.sh | bash

set -euo pipefail

# Overridable so forks / CI / offline installs can point at another source
# (e.g. a local file:// or http:// mirror). The integrity check below still
# verifies every download against that source's SHA256SUMS.
REPO_RAW="${STATUSLINE_REPO_RAW:-https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main}"
SCRIPT_NAME="statusline-command.sh"

target_dir="$HOME/.claude"
target_file="${target_dir}/${SCRIPT_NAME}"
settings_file="${target_dir}/settings.json"

# ── Download files ─────────────────────────────────────────────
version_file="${target_dir}/.statusline-version"

mkdir -p "$target_dir"

if ! command -v curl > /dev/null 2>&1 && ! command -v wget > /dev/null 2>&1; then
  echo "Error: curl or wget is required."
  exit 1
fi

# Download $1 -> $2 using curl (preferred) or wget. Returns non-zero on failure.
fetch() {
  if command -v curl > /dev/null 2>&1; then
    curl -fsSL "$1" -o "$2"
  else
    wget -qO "$2" "$1"
  fi
}

# SHA-256 of $1 into REPLY (hash field only). sha256sum (Linux/MSYS2) then
# `shasum -a 256` (macOS); non-zero if no tool / unreadable file.
have_sha256() { command -v sha256sum > /dev/null 2>&1 || command -v shasum > /dev/null 2>&1; }
sha256_of() {
  REPLY=""
  if command -v sha256sum > /dev/null 2>&1; then REPLY="$(sha256sum "$1" 2>/dev/null)" || return 1
  elif command -v shasum > /dev/null 2>&1; then REPLY="$(shasum -a 256 "$1" 2>/dev/null)" || return 1
  else return 1; fi
  REPLY="${REPLY%% *}"; [ -n "$REPLY" ]
}

# Download VERSION first so we can display it.
fetch "${REPO_RAW}/VERSION" "$version_file"
VERSION=$(tr -d '[:space:]' < "$version_file")
if [ -f "$target_file" ]; then
  echo "Updating claude-code-status-bar to v${VERSION}..."
else
  echo "Installing claude-code-status-bar v${VERSION}..."
fi

# Stage the runtime files to a temp dir, verify each against the release's
# SHA256SUMS, and only THEN move them into ~/.claude — mirroring the runtime
# self-updater (security finding G1). This installer doubles as the documented
# update path, so it must not write or chmod+x a tampered / truncated / MITM'd
# download. On a checksum mismatch we abort leaving ~/.claude untouched; when no
# sha256 tool exists or the manifest can't be fetched (older fork) the check is
# skipped gracefully so those installs still work, exactly like --update.
runtime_files="${SCRIPT_NAME} statusline-helper.js statusline-subagent.js"
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/ccsb-install-XXXXXX")"
cleanup_stage() { [ -n "${stage_dir:-}" ] && rm -rf "$stage_dir"; }
trap cleanup_stage EXIT

for f in $runtime_files; do
  if ! fetch "${REPO_RAW}/${f}" "${stage_dir}/${f}" 2>/dev/null; then
    if [ "$f" = "$SCRIPT_NAME" ]; then
      echo "Error: failed to download ${f} — aborting (nothing installed)." >&2
      exit 1
    fi
    rm -f "${stage_dir}/${f}"   # the two .js helpers are optional
  fi
done

if have_sha256 && fetch "${REPO_RAW}/SHA256SUMS" "${stage_dir}/SHA256SUMS" 2>/dev/null \
   && [ -s "${stage_dir}/SHA256SUMS" ]; then
  for f in $runtime_files; do
    [ -f "${stage_dir}/${f}" ] || continue   # optional helper not downloaded
    actual=""; sha256_of "${stage_dir}/${f}" && actual="$REPLY"
    expected=""
    while read -r h n _; do
      n="${n#\*}"; n="${n##*/}"   # drop binary marker; compare basenames
      if [ "$n" = "$f" ]; then expected="$h"; break; fi
    done < "${stage_dir}/SHA256SUMS"
    if [ -z "$actual" ] || [ -z "$expected" ] || [ "$actual" != "$expected" ]; then
      echo "Error: checksum verification failed for ${f} — aborting (nothing installed)." >&2
      exit 1
    fi
  done
  echo "  Integrity verified against SHA256SUMS."
fi

# Verified (or skipped gracefully) — move staged files into place.
mv -f "${stage_dir}/${SCRIPT_NAME}" "$target_file"
[ -f "${stage_dir}/statusline-helper.js" ]   && mv -f "${stage_dir}/statusline-helper.js"   "${target_dir}/statusline-helper.js"
[ -f "${stage_dir}/statusline-subagent.js" ] && mv -f "${stage_dir}/statusline-subagent.js" "${target_dir}/statusline-subagent.js"

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
