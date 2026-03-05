#!/usr/bin/env bash
#
# Claude Code Status Bar — Installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main/install.sh | bash -s -- --local
#
# Options:
#   --global   Install to ~/.claude/ and update ~/.claude/settings.json (default)
#   --local    Install to .claude/ and update .claude/settings.json in current project

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main"
SCRIPT_NAME="statusline-command.sh"

# ── Parse arguments ──────────────────────────────────────────
mode="global"
for arg in "$@"; do
  case "$arg" in
    --local)  mode="local" ;;
    --global) mode="global" ;;
    *)
      echo "Unknown option: $arg"
      echo "Usage: install.sh [--global | --local]"
      exit 1
      ;;
  esac
done

# ── Determine target directory ───────────────────────────────
if [ "$mode" = "local" ]; then
  target_dir=".claude"
else
  target_dir="$HOME/.claude"
fi

target_file="${target_dir}/${SCRIPT_NAME}"
settings_file="${target_dir}/settings.json"

# ── Download script ──────────────────────────────────────────
echo "Installing claude-code-status-bar (${mode})..."

mkdir -p "$target_dir"

if command -v curl > /dev/null 2>&1; then
  curl -fsSL "${REPO_RAW}/${SCRIPT_NAME}" -o "$target_file"
elif command -v wget > /dev/null 2>&1; then
  wget -qO "$target_file" "${REPO_RAW}/${SCRIPT_NAME}"
else
  echo "Error: curl or wget is required."
  exit 1
fi

chmod +x "$target_file"
echo "  Script installed to: ${target_file}"

# ── Update settings.json ─────────────────────────────────────
command_value="bash ${target_file}"

update_settings() {
  local file="$1"
  local cmd="$2"

  if [ ! -f "$file" ]; then
    cat > "$file" <<EOF
{
  "statusline": {
    "command": "${cmd}"
  }
}
EOF
    echo "  Created settings: ${file}"
    return
  fi

  if grep -q '"statusline"' "$file"; then
    echo "  settings.json already has a statusline entry — skipped."
    echo "  To update manually: \"command\": \"${cmd}\""
    return
  fi

  # Merge using Python (available on macOS, Linux, and Windows with Git Bash)
  if command -v python3 > /dev/null 2>&1; then
    python3 - "$file" "$cmd" <<'PYEOF'
import json, sys
path, cmd = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
data['statusline'] = {'command': cmd}
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PYEOF
    echo "  Updated settings: ${file}"
  elif command -v python > /dev/null 2>&1; then
    python - "$file" "$cmd" <<'PYEOF'
import json, sys
path, cmd = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
data['statusline'] = {'command': cmd}
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PYEOF
    echo "  Updated settings: ${file}"
  else
    echo ""
    echo "  Python not found — add this to ${file} manually:"
    echo '  {'
    echo '    "statusline": {'
    echo "      \"command\": \"${cmd}\""
    echo '    }'
    echo '  }'
  fi
}

update_settings "$settings_file" "$command_value"

echo ""
echo "Done! Restart Claude Code to see your statusline."
