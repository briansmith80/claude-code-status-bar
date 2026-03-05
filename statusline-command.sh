#!/usr/bin/env bash
#
# Claude Code statusline script
#
# Displays a single-line status bar with configurable segments:
#   - Working directory (shortened with ~)
#   - Git branch name
#   - Model name (Opus, Sonnet, Haiku)
#   - Context window progress bar with colour thresholds
#   - Lines added/removed in session
#   - Uncommitted (dirty) file count from git
#   - Session duration
#   - Worktree indicator (when active)
#   - Cumulative session cost in USD
#
# This script receives JSON via stdin each time the statusline refreshes
# (after every assistant message, permission change, or vim mode toggle).
#
# Uses pure bash regex for JSON parsing — no jq dependency required.

set -e

SCRIPT_DIR="${HOME}/.claude"
VERSION_FILE="${SCRIPT_DIR}/.statusline-version"
VERSION="unknown"
[ -f "$VERSION_FILE" ] && VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")

UPDATE_CHECK_INTERVAL=21600  # seconds between update checks (6 hours)
UPDATE_CACHE_FILE="${SCRIPT_DIR}/.statusline-update-cache"
REPO_RAW="https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main"

# ── CLI Flags ─────────────────────────────────────────────────
case "${1:-}" in
  --help|-h)
    echo "Usage: echo '<json>' | bash statusline-command.sh"
    echo ""
    echo "Reads Claude Code statusline JSON from stdin and outputs"
    echo "a formatted single-line status bar for your terminal."
    echo ""
    echo "Version: ${VERSION}"
    exit 0
    ;;
  --version|-v)
    echo "$VERSION"
    exit 0
    ;;
  --check-update)
    # Force a synchronous update check and print result
    rm -f "$UPDATE_CACHE_FILE"
    remote_version=""
    if command -v curl > /dev/null 2>&1; then
      remote_version=$(curl -fsSL --max-time 5 "${REPO_RAW}/VERSION" 2>/dev/null | tr -d '[:space:]')
    elif command -v wget > /dev/null 2>&1; then
      remote_version=$(wget -qO- --timeout=5 "${REPO_RAW}/VERSION" 2>/dev/null | tr -d '[:space:]')
    fi
    echo "Current: ${VERSION}"
    if [ -z "$remote_version" ]; then
      echo "Latest:  (could not reach GitHub)"
    elif [ "$remote_version" = "$VERSION" ]; then
      echo "Latest:  ${remote_version}"
      echo "You're up to date."
    else
      echo "Latest:  ${remote_version}"
      echo ""
      echo "Update available! Run:"
      echo "  curl -fsSL ${REPO_RAW}/install.sh | bash"
    fi
    exit 0
    ;;
esac

# ── Update Check ─────────────────────────────────────────────
# Periodically fetches the remote VERSION file and caches the result.
# Runs in the background so it never slows down the statusline.
update_available=""

check_for_update() {
  local now
  now=$(date +%s)

  # Read cache: "timestamp remote_version"
  if [ -f "$UPDATE_CACHE_FILE" ]; then
    local cached_time cached_version
    read -r cached_time cached_version < "$UPDATE_CACHE_FILE" 2>/dev/null || true
    if [ -n "$cached_time" ] && [ $(( now - cached_time )) -lt $UPDATE_CHECK_INTERVAL ]; then
      # Cache is fresh — use cached result
      if [ -n "$cached_version" ] && [ "$cached_version" != "$VERSION" ]; then
        update_available="$cached_version"
      fi
      return
    fi
  fi

  # Cache is stale or missing — fetch in background and write cache
  (
    remote_version=""
    if command -v curl > /dev/null 2>&1; then
      remote_version=$(curl -fsSL --max-time 3 "${REPO_RAW}/VERSION" 2>/dev/null | tr -d '[:space:]')
    elif command -v wget > /dev/null 2>&1; then
      remote_version=$(wget -qO- --timeout=3 "${REPO_RAW}/VERSION" 2>/dev/null | tr -d '[:space:]')
    fi
    if [ -n "$remote_version" ]; then
      echo "$(date +%s) $remote_version" > "$UPDATE_CACHE_FILE"
    fi
  ) &
}

check_for_update

# ── Configuration ─────────────────────────────────────────────
# Defaults — toggle each segment on/off (true/false).
# To customise, create ~/.claude/statusline.conf with your overrides.
# That file is never overwritten by updates.
#
# Example ~/.claude/statusline.conf:
#   show_branch=false
#   show_cost=false

show_directory=true
show_branch=true
show_model=true
show_context_bar=true
show_lines_changed=true
show_dirty_count=true
show_duration=true
show_worktree=true
show_cost=true
auto_hide=true
use_icons=true
colour_theme="default"

# Load user overrides (if any)
STATUSLINE_CONF="${SCRIPT_DIR}/statusline.conf"
# shellcheck disable=SC1090
[ -f "$STATUSLINE_CONF" ] && . "$STATUSLINE_CONF"

# ── Colour Themes ────────────────────────────────────────────
# Respect NO_COLOR standard (https://no-color.org/)
[ -n "${NO_COLOR:-}" ] && colour_theme="mono"

apply_theme() {
  case "${colour_theme:-default}" in
    nord)
      CLR_DIR="\033[38;5;81m"     # frost blue
      CLR_BRANCH="\033[38;5;139m"  # aurora purple
      CLR_MODEL="\033[38;5;111m"   # frost lighter blue
      CLR_ADD="\033[38;5;108m"     # aurora green
      CLR_DEL="\033[38;5;174m"     # aurora red
      CLR_WARN="\033[38;5;179m"    # aurora yellow
      CLR_INFO="\033[38;5;110m"    # frost cyan
      CLR_BAR_OK="\033[38;5;108m"  # aurora green
      CLR_BAR_MED="\033[38;5;179m" # aurora yellow
      CLR_BAR_HIGH="\033[38;5;174m" # aurora red
      CLR_RESET="\033[0m"
      ;;
    dracula)
      CLR_DIR="\033[38;5;141m"     # purple
      CLR_BRANCH="\033[38;5;212m"  # pink
      CLR_MODEL="\033[38;5;117m"   # cyan
      CLR_ADD="\033[38;5;84m"      # green
      CLR_DEL="\033[38;5;210m"     # red
      CLR_WARN="\033[38;5;228m"    # yellow
      CLR_INFO="\033[38;5;117m"    # cyan
      CLR_BAR_OK="\033[38;5;84m"   # green
      CLR_BAR_MED="\033[38;5;228m" # yellow
      CLR_BAR_HIGH="\033[38;5;210m" # red
      CLR_RESET="\033[0m"
      ;;
    solarized)
      CLR_DIR="\033[38;5;37m"     # cyan
      CLR_BRANCH="\033[38;5;61m"  # violet
      CLR_MODEL="\033[38;5;33m"   # blue
      CLR_ADD="\033[38;5;64m"     # green
      CLR_DEL="\033[38;5;160m"    # red
      CLR_WARN="\033[38;5;136m"   # yellow
      CLR_INFO="\033[38;5;37m"    # cyan
      CLR_BAR_OK="\033[38;5;64m"  # green
      CLR_BAR_MED="\033[38;5;136m" # yellow
      CLR_BAR_HIGH="\033[38;5;160m" # red
      CLR_RESET="\033[0m"
      ;;
    mono)
      CLR_DIR="" CLR_BRANCH="" CLR_MODEL=""
      CLR_ADD="" CLR_DEL="" CLR_WARN="" CLR_INFO=""
      CLR_BAR_OK="" CLR_BAR_MED="" CLR_BAR_HIGH=""
      CLR_RESET=""
      ;;
    *) # default — original colours
      CLR_DIR="\033[0;36m"     # cyan
      CLR_BRANCH="\033[0;35m"  # magenta
      CLR_MODEL="\033[0;34m"   # blue
      CLR_ADD="\033[0;32m"     # green
      CLR_DEL="\033[0;31m"     # red
      CLR_WARN="\033[0;33m"    # yellow
      CLR_INFO="\033[0;36m"    # cyan
      CLR_BAR_OK="\033[0;32m"  # green
      CLR_BAR_MED="\033[0;33m" # yellow
      CLR_BAR_HIGH="\033[0;31m" # red
      CLR_RESET="\033[0m"
      ;;
  esac
}

apply_theme

# ── End Configuration ─────────────────────────────────────────

input=$(cat)

# ── JSON Parsing Helpers ──────────────────────────────────────
# These extract values from the JSON input using bash regex since
# jq is not available in MSYS2/Git Bash on Windows by default.

# Extract a string value by key, e.g. "key": "value"
extract() {
  local key="$1"
  local pattern="\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]+)\""
  if [[ $input =~ $pattern ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

# Extract a numeric value by key, e.g. "key": 42 or "key": 0.45
extract_num() {
  local key="$1"
  local pattern="\"$key\"[[:space:]]*:[[:space:]]*([0-9]+\.?[0-9]*)"
  if [[ $input =~ $pattern ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

# Strip ANSI escape sequences and control characters from untrusted strings
sanitize() {
  local val="$1"
  # Remove ANSI escape sequences (CSI and OSC)
  val=$(printf '%s' "$val" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\][^\x07]*\x07//g')
  # Remove remaining control characters (except space)
  val=$(printf '%s' "$val" | tr -d '\000-\037\177')
  echo "$val"
}

# ── Extract Fields ────────────────────────────────────────────

# Working directory: prefer workspace.current_dir, fall back to top-level cwd
cwd=$(extract "current_dir")
[ -z "$cwd" ] && cwd=$(extract "cwd")

# Model display name, e.g. "Opus", "Sonnet", "Haiku"
model=$(extract "display_name")

# Context window usage as a percentage (0-100)
used=$(extract_num "used_percentage")

# Cumulative session cost in USD
total_cost=$(extract_num "total_cost_usd")

# Lines changed during this session
lines_added=$(extract_num "total_lines_added")
lines_removed=$(extract_num "total_lines_removed")

# Session duration in milliseconds
duration_ms=$(extract_num "total_duration_ms")

# Worktree name (only present when working in an isolated worktree)
worktree_name=$(extract "name")
# Disambiguate: worktree.name only exists inside a "worktree" object.
# Check if the input actually contains a worktree block.
worktree=""
local_pattern="\"worktree\"[[:space:]]*:[[:space:]]*\{"
if [[ $input =~ $local_pattern ]]; then
  worktree=$(sanitize "$worktree_name")
fi

# ── Working Directory ─────────────────────────────────────────
# Replace home directory prefix with ~ for a shorter display
home_dir="$HOME"
short_cwd="${cwd/#$home_dir/\~}"
short_cwd=$(sanitize "$short_cwd")

# ── Git Branch & Dirty Count ─────────────────────────────────
# Detect the current branch name (or short SHA if detached HEAD).
# Uses -c core.fsmonitor=false to skip filesystem monitoring overhead.
# Also counts uncommitted files for the dirty indicator.
branch=""
dirty_count=""
if [ -n "$cwd" ] && git -C "$cwd" -c core.fsmonitor=false rev-parse --git-dir > /dev/null 2>&1; then
  if [ "$show_branch" = "true" ]; then
    branch=$(git -C "$cwd" -c core.fsmonitor=false symbolic-ref --short HEAD 2>/dev/null \
      || git -C "$cwd" -c core.fsmonitor=false rev-parse --short HEAD 2>/dev/null)
    branch=$(sanitize "$branch")
  fi

  # Count uncommitted files (staged + unstaged + untracked).
  # Uses --porcelain for stable machine-readable output.
  if [ "$show_dirty_count" = "true" ]; then
    dirty_count=$(git -C "$cwd" -c core.fsmonitor=false status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  fi
fi

# ── Context Window Progress Bar ───────────────────────────────
# Visual bar showing how much of the context window has been consumed.
# Colour shifts from green → yellow → red as usage increases.
# Note: only context window data is available — account-level usage
# limits are not exposed in the statusline JSON input.
build_progress_bar() {
  local pct=${1:-0}
  local width=10
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))

  # Colour based on usage: green < 50%, yellow 50-79%, red 80%+
  local colour
  if [ "$pct" -ge 80 ]; then
    colour="$CLR_BAR_HIGH"
  elif [ "$pct" -ge 50 ]; then
    colour="$CLR_BAR_MED"
  else
    colour="$CLR_BAR_OK"
  fi

  local bar="${colour}"
  for (( i=0; i<filled; i++ )); do bar+="█"; done
  for (( i=0; i<empty; i++ ));  do bar+="░"; done
  bar+="$CLR_RESET"

  echo "$bar"
}

# ── Build Output Segments ─────────────────────────────────────
# Each segment is conditionally built based on config toggles.
# Segments that are disabled produce empty strings and are skipped.

output=""

# Directory
if [ "$show_directory" = "true" ]; then
  output+="${CLR_DIR}${short_cwd}${CLR_RESET}"
fi

# Branch
if [ "$show_branch" = "true" ] && [ -n "$branch" ]; then
  branch_icon=""
  [ "$use_icons" = "true" ] && branch_icon="⌥ "
  output+="${CLR_BRANCH} on ${branch_icon}${branch}${CLR_RESET}"
fi

# Model
if [ "$show_model" = "true" ]; then
  model_icon=""
  [ "$use_icons" = "true" ] && model_icon="⚙ "
  output+="  ${CLR_MODEL}${model_icon}${model:-?}${CLR_RESET}"
fi

# Context bar
if [ "$show_context_bar" = "true" ]; then
  pct="${used:-0}"
  pct_int="${pct%%.*}"
  progress_bar=$(build_progress_bar "$pct_int")
  output+="  ${progress_bar} ${pct_int}%"
fi

# Lines changed — green for additions, red for removals
if [ "$show_lines_changed" = "true" ]; then
  added="${lines_added:-0}"
  removed="${lines_removed:-0}"
  added_int="${added%%.*}"
  removed_int="${removed%%.*}"
  if [ "$auto_hide" != "true" ] || [ "$added_int" -gt 0 ] || [ "$removed_int" -gt 0 ]; then
    output+="  ${CLR_ADD}+${added_int}${CLR_RESET} ${CLR_DEL}-${removed_int}${CLR_RESET}"
  fi
fi

# Dirty file count — yellow reminder to commit
if [ "$show_dirty_count" = "true" ] && [ -n "$dirty_count" ]; then
  if [ "$auto_hide" != "true" ] || [ "$dirty_count" -gt 0 ] 2>/dev/null; then
    dirty_icon=""
    [ "$use_icons" = "true" ] && dirty_icon="● "
    output+="  ${CLR_WARN}${dirty_icon}${dirty_count} dirty${CLR_RESET}"
  fi
fi

# Session duration — converted from ms to Xh Ym or Ym
if [ "$show_duration" = "true" ] && [ -n "$duration_ms" ] && [ "$duration_ms" != "0" ]; then
  total_secs=$(( ${duration_ms%%.*} / 1000 ))
  hours=$(( total_secs / 3600 ))
  mins=$(( (total_secs % 3600) / 60 ))
  dur_icon=""
  [ "$use_icons" = "true" ] && dur_icon="◷ "

  if [ "$hours" -gt 0 ]; then
    output+="  ${CLR_INFO}${dur_icon}${hours}h${mins}m${CLR_RESET}"
  elif [ "$mins" -gt 0 ]; then
    output+="  ${CLR_INFO}${dur_icon}${mins}m${CLR_RESET}"
  elif [ "$auto_hide" != "true" ]; then
    output+="  ${CLR_INFO}${dur_icon}0m${CLR_RESET}"
  fi
fi

# Worktree indicator — only when in an isolated worktree
if [ "$show_worktree" = "true" ] && [ -n "$worktree" ]; then
  wt_icon=""
  [ "$use_icons" = "true" ] && wt_icon="⎇ "
  output+="  ${CLR_BRANCH}${wt_icon}${worktree}${CLR_RESET}"
fi

# Session cost in USD
if [ "$show_cost" = "true" ] && [ -n "$total_cost" ]; then
  # Hide $0 costs unless auto_hide is off
  cost_is_zero=false
  case "$total_cost" in 0|0.0|0.00|0.000) cost_is_zero=true ;; esac
  if [ "$auto_hide" != "true" ] || [ "$cost_is_zero" = "false" ]; then
    output+="  ${CLR_WARN}\$${total_cost}${CLR_RESET}"
  fi
fi

# Update notification — shown when a newer version is available
if [ -n "$update_available" ]; then
  update_icon=""
  [ "$use_icons" = "true" ] && update_icon="⬆ "
  output+="  ${CLR_WARN}${update_icon}update available${CLR_RESET}"
fi

# ── Print ─────────────────────────────────────────────────────
printf "%b" "$output"
