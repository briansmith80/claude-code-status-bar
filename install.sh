#!/usr/bin/env bash
#
# Claude Code Status Bar — Installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main/install.sh | bash -s -- --local
#
# Options:
#   --global   Install to ~/.claude/ (default)
#   --local    Install to .claude/ in the current project directory

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

# ── Download and install ─────────────────────────────────────
echo "Installing claude-code-status-bar (${mode})..."

mkdir -p "$target_dir"

if command -v curl > /dev/null 2>&1; then
  curl -fsSL "${REPO_RAW}/${SCRIPT_NAME}" -o "$target_file"
elif command -v wget > /dev/null 2>&1; then
  wget -qO "$target_file" "${REPO_RAW}/${SCRIPT_NAME}"
else
  echo "Error: curl or wget is required to download the script."
  exit 1
fi

chmod +x "$target_file"

echo ""
echo "Installed to: ${target_file}"
echo ""
echo "To enable, add this to your Claude Code settings"
echo "(~/.claude/settings.json or .claude/settings.json):"
echo ""
echo '  {'
echo '    "statusline": {'
echo "      \"command\": \"bash ${target_file}\""
echo '    }'
echo '  }'
echo ""
echo "Done!"
