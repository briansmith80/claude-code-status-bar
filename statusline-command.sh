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
show_ahead_behind=true
show_stash=true
show_duration=true
show_worktree=true
show_cost=true
show_cost_rate=false
auto_hide=true
use_icons=true
context_warn_threshold=80
enable_truncation=false
max_width=""
use_groups=false
group_open="["
group_close="]"
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

# Strip ANSI escapes for width measurement (used by truncation)
strip_ansi() {
  printf '%b' "$1" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\][^\x07]*\x07//g'
}

visible_width() {
  local stripped
  stripped=$(strip_ansi "$1")
  echo ${#stripped}
}

# ── Extract Fields ────────────────────────────────────────────

# Working directory: prefer workspace.current_dir, fall back to top-level cwd
cwd=$(extract "current_dir")
[ -z "$cwd" ] && cwd=$(extract "cwd")

# Model display name, e.g. "Opus", "Sonnet", "Haiku"
model=$(extract "display_name")

# Context window usage as a percentage (0-100)
used=$(extract_num "used_percentage")

# Context window total size in tokens
context_size=$(extract_num "context_window_size")

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

# ── Git Info ──────────────────────────────────────────────────
# Detect branch, dirty count, ahead/behind, and stash count.
# Uses -c core.fsmonitor=false to skip filesystem monitoring overhead.
branch=""
dirty_count=""
ahead_count=""
behind_count=""
stash_count=""
if [ -n "$cwd" ] && git -C "$cwd" -c core.fsmonitor=false rev-parse --git-dir > /dev/null 2>&1; then
  if [ "$show_branch" = "true" ]; then
    branch=$(git -C "$cwd" -c core.fsmonitor=false symbolic-ref --short HEAD 2>/dev/null \
      || git -C "$cwd" -c core.fsmonitor=false rev-parse --short HEAD 2>/dev/null)
    branch=$(sanitize "$branch")
  fi

  # Count uncommitted files (staged + unstaged + untracked).
  if [ "$show_dirty_count" = "true" ]; then
    dirty_count=$(git -C "$cwd" -c core.fsmonitor=false status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  fi

  # Ahead/behind remote — silently hidden when no upstream or detached HEAD.
  # The || ab_output="" is critical: without it, set -e kills the script.
  if [ "$show_ahead_behind" = "true" ]; then
    # shellcheck disable=SC1083
    ab_output=$(git -C "$cwd" -c core.fsmonitor=false rev-list --left-right --count HEAD...@{upstream} 2>/dev/null) || ab_output=""
    if [ -n "$ab_output" ]; then
      ahead_count=$(echo "$ab_output" | cut -f1)
      behind_count=$(echo "$ab_output" | cut -f2)
    fi
  fi

  # Stash count
  if [ "$show_stash" = "true" ]; then
    stash_count=$(git -C "$cwd" -c core.fsmonitor=false stash list 2>/dev/null | wc -l | tr -d ' ')
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
# Each segment is built into parallel arrays for optional truncation.
# seg_vals[N] = segment content, seg_pris[N] = priority (1=highest).
# Directory+Branch are combined into one segment (priority 1).

seg_idx=0

# Helper: add a segment with priority and optional group
# Usage: add_seg "content" priority ["group_name"]
add_seg() {
  seg_vals[$seg_idx]="$1"
  seg_pris[$seg_idx]="$2"
  seg_groups[$seg_idx]="${3:-}"
  seg_idx=$((seg_idx + 1))
}

# Directory + Branch (combined, priority 1)
dir_branch=""
if [ "$show_directory" = "true" ]; then
  dir_branch+="${CLR_DIR}${short_cwd}${CLR_RESET}"
fi
if [ "$show_branch" = "true" ] && [ -n "$branch" ]; then
  branch_icon=""
  [ "$use_icons" = "true" ] && branch_icon="↱ "
  dir_branch+="${CLR_BRANCH} on ${branch_icon}${branch}${CLR_RESET}"
fi
[ -n "$dir_branch" ] && add_seg "$dir_branch" 1

# Model (priority 3)
if [ "$show_model" = "true" ]; then
  model_icon=""
  [ "$use_icons" = "true" ] && model_icon="⚙ "
  add_seg "${CLR_MODEL}${model_icon}${model:-?}${CLR_RESET}" 3 "ctx"
fi

# Context bar (priority 2)
if [ "$show_context_bar" = "true" ]; then
  pct="${used:-0}"
  pct_int="${pct%%.*}"
  progress_bar=$(build_progress_bar "$pct_int")
  warn_prefix=""
  if [ "$pct_int" -ge "${context_warn_threshold:-80}" ] 2>/dev/null; then
    [ "$use_icons" = "true" ] && warn_prefix="⚠ "
  fi
  ctx_suffix=""
  if [ -n "$context_size" ] && [ "$context_size" != "0" ]; then
    ctx_k=$(( ${context_size%%.*} / 1000 ))
    ctx_suffix=" of ${ctx_k}k"
  fi
  add_seg "${warn_prefix}${progress_bar} ${pct_int}%${ctx_suffix}" 2 "ctx"
fi

# Lines changed (priority 5)
if [ "$show_lines_changed" = "true" ]; then
  added="${lines_added:-0}"
  removed="${lines_removed:-0}"
  added_int="${added%%.*}"
  removed_int="${removed%%.*}"
  if [ "$auto_hide" != "true" ] || [ "$added_int" -gt 0 ] || [ "$removed_int" -gt 0 ]; then
    add_seg "${CLR_ADD}+${added_int}${CLR_RESET} ${CLR_DEL}-${removed_int}${CLR_RESET}" 5 "git"
  fi
fi

# Dirty file count (priority 5)
if [ "$show_dirty_count" = "true" ] && [ -n "$dirty_count" ]; then
  if [ "$auto_hide" != "true" ] || [ "$dirty_count" -gt 0 ] 2>/dev/null; then
    dirty_icon=""
    [ "$use_icons" = "true" ] && dirty_icon="● "
    add_seg "${CLR_WARN}${dirty_icon}${dirty_count} dirty${CLR_RESET}" 5 "git"
  fi
fi

# Ahead/behind remote (priority 6)
if [ "$show_ahead_behind" = "true" ]; then
  ab_behind="${behind_count:-0}"
  ab_ahead="${ahead_count:-0}"
  if [ "$auto_hide" != "true" ] || [ "$ab_behind" -gt 0 ] || [ "$ab_ahead" -gt 0 ] 2>/dev/null; then
    ab_text=""
    [ "$ab_behind" -gt 0 ] 2>/dev/null && ab_text+="↓${ab_behind}"
    [ "$ab_ahead" -gt 0 ] 2>/dev/null && { [ -n "$ab_text" ] && ab_text+=" "; ab_text+="↑${ab_ahead}"; }
    [ -n "$ab_text" ] && add_seg "${CLR_INFO}${ab_text}${CLR_RESET}" 6 "git"
  fi
fi

# Stash count (priority 6)
if [ "$show_stash" = "true" ]; then
  sc="${stash_count:-0}"
  if [ "$auto_hide" != "true" ] || [ "$sc" -gt 0 ] 2>/dev/null; then
    stash_icon=""
    [ "$use_icons" = "true" ] && stash_icon="≡ "
    add_seg "${CLR_WARN}${stash_icon}stash:${sc}${CLR_RESET}" 6 "git"
  fi
fi

# Session duration (priority 7)
if [ "$show_duration" = "true" ] && [ -n "$duration_ms" ] && [ "$duration_ms" != "0" ]; then
  total_secs=$(( ${duration_ms%%.*} / 1000 ))
  hours=$(( total_secs / 3600 ))
  mins=$(( (total_secs % 3600) / 60 ))
  dur_icon=""
  [ "$use_icons" = "true" ] && dur_icon="◷ "

  dur_text=""
  if [ "$hours" -gt 0 ]; then
    dur_text="${CLR_INFO}${dur_icon}${hours}h${mins}m${CLR_RESET}"
  elif [ "$mins" -gt 0 ]; then
    dur_text="${CLR_INFO}${dur_icon}${mins}m${CLR_RESET}"
  elif [ "$auto_hide" != "true" ]; then
    dur_text="${CLR_INFO}${dur_icon}0m${CLR_RESET}"
  fi
  [ -n "$dur_text" ] && add_seg "$dur_text" 7 "session"
fi

# Worktree indicator (priority 8)
if [ "$show_worktree" = "true" ] && [ -n "$worktree" ]; then
  wt_icon=""
  [ "$use_icons" = "true" ] && wt_icon="⎇ "
  add_seg "${CLR_BRANCH}${wt_icon}${worktree}${CLR_RESET}" 8
fi

# Session cost (priority 4)
if [ "$show_cost" = "true" ] && [ -n "$total_cost" ]; then
  cost_is_zero=false
  case "$total_cost" in 0|0.0|0.00|0.000) cost_is_zero=true ;; esac
  if [ "$auto_hide" != "true" ] || [ "$cost_is_zero" = "false" ]; then
    cost_fmt=$(awk "BEGIN {printf \"%.2f\", $total_cost}" 2>/dev/null) || cost_fmt="$total_cost"
    add_seg "${CLR_WARN}\$${cost_fmt}${CLR_RESET}" 4 "session"
  fi
fi

# Cost rate (priority 4)
if [ "$show_cost_rate" = "true" ] && [ -n "$total_cost" ] && [ -n "$duration_ms" ]; then
  dur_int="${duration_ms%%.*}"
  if [ "$dur_int" -ge 60000 ] 2>/dev/null; then
    cost_rate=$(awk "BEGIN {printf \"%.2f\", $total_cost / ($dur_int / 3600000)}" 2>/dev/null) || cost_rate=""
    if [ -n "$cost_rate" ]; then
      rate_is_zero=false
      case "$cost_rate" in 0.00) rate_is_zero=true ;; esac
      if [ "$auto_hide" != "true" ] || [ "$rate_is_zero" = "false" ]; then
        add_seg "${CLR_WARN}\$${cost_rate}/hr${CLR_RESET}" 4 "session"
      fi
    fi
  fi
fi

# Update notification (priority 9 — lowest)
if [ -n "$update_available" ]; then
  update_icon=""
  [ "$use_icons" = "true" ] && update_icon="⬆ "
  add_seg "${CLR_WARN}${update_icon}update available${CLR_RESET}" 9
fi

# ── Truncation ───────────────────────────────────────────────
# When enabled, drop lowest-priority segments until output fits.
if [ "$enable_truncation" = "true" ] && [ "$seg_idx" -gt 0 ]; then
  # Detect terminal width
  term_width=""
  if [ -n "$max_width" ]; then
    term_width="$max_width"
  else
    term_width=$(tput cols 2>/dev/null) || true
    [ -z "$term_width" ] && term_width="${COLUMNS:-120}"
  fi

  # Mark segments as active (1) or dropped (0)
  for (( i=0; i<seg_idx; i++ )); do seg_active[$i]=1; done

  # Calculate total visible width (segments + separators)
  calc_total_width() {
    local total=0 first=1
    for (( i=0; i<seg_idx; i++ )); do
      [ "${seg_active[$i]}" = "0" ] && continue
      if [ "$first" = "1" ]; then
        first=0
      else
        total=$((total + 2))  # "  " separator
      fi
      total=$((total + $(visible_width "${seg_vals[$i]}")))
    done
    echo "$total"
  }

  # Drop lowest-priority segments until we fit
  while true; do
    total_w=$(calc_total_width)
    [ "$total_w" -le "$term_width" ] 2>/dev/null && break

    # Find the active segment with the highest priority number (lowest priority)
    worst_idx=-1
    worst_pri=0
    for (( i=0; i<seg_idx; i++ )); do
      [ "${seg_active[$i]}" = "0" ] && continue
      if [ "${seg_pris[$i]}" -gt "$worst_pri" ] 2>/dev/null; then
        worst_pri="${seg_pris[$i]}"
        worst_idx=$i
      fi
    done

    # Nothing left to drop
    [ "$worst_idx" = "-1" ] && break
    seg_active[$worst_idx]=0
  done
fi

# ── Assemble & Print ─────────────────────────────────────────
# When use_groups=true, segments with the same group are wrapped in brackets
# and separated by single space. Groups are separated by double space.
output=""
first_seg=1
current_group=""
group_has_content=false

for (( i=0; i<seg_idx; i++ )); do
  if [ "$enable_truncation" = "true" ] && [ "${seg_active[$i]:-1}" = "0" ]; then
    continue
  fi

  this_group="${seg_groups[$i]:-}"

  if [ "$use_groups" = "true" ] && [ -n "$this_group" ]; then
    if [ "$this_group" != "$current_group" ]; then
      # Close previous group if open
      if [ -n "$current_group" ] && [ "$group_has_content" = "true" ]; then
        output+="${group_close}"
      fi
      # Separator between segments/groups
      [ "$first_seg" != "1" ] && output+="  "
      first_seg=0
      # Open new group
      output+="${group_open}"
      current_group="$this_group"
      group_has_content=true
    else
      # Same group — single space separator within group
      output+=" "
    fi
  else
    # Close previous group if open
    if [ "$use_groups" = "true" ] && [ -n "$current_group" ] && [ "$group_has_content" = "true" ]; then
      output+="${group_close}"
      current_group=""
      group_has_content=false
    fi
    # Separator between segments
    if [ "$first_seg" = "1" ]; then
      first_seg=0
    else
      output+="  "
    fi
  fi

  output+="${seg_vals[$i]}"
done

# Close final group if still open
if [ "$use_groups" = "true" ] && [ -n "$current_group" ] && [ "$group_has_content" = "true" ]; then
  output+="${group_close}"
fi

printf "%b" "$output"
