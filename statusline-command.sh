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

# ── Configuration ─────────────────────────────────────────────
# Toggle each segment on/off (true/false).
# Edit these values directly to customise your statusline.

show_directory=true
show_branch=true
show_model=true
show_context_bar=true
show_lines_changed=true
show_dirty_count=true
show_duration=true
show_worktree=true
show_cost=true

# ── End Configuration ─────────────────────────────────────────

input=$(cat)

# ── JSON Parsing Helpers ──────────────────────────────────────
# These extract values from the JSON input using bash regex since
# jq is not available in MSYS2/Git Bash on Windows by default.

# Extract a string value by key, e.g. "key": "value"
extract() {
  local key="$1"
  if [[ $input =~ \"$key\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

# Extract a numeric value by key, e.g. "key": 42 or "key": 0.45
extract_num() {
  local key="$1"
  if [[ $input =~ \"$key\"[[:space:]]*:[[:space:]]*([0-9]+\.?[0-9]*) ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
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
if [[ $input =~ \"worktree\"[[:space:]]*:[[:space:]]*\{ ]]; then
  worktree="$worktree_name"
fi

# ── Working Directory ─────────────────────────────────────────
# Replace home directory prefix with ~ for a shorter display
home_dir="$HOME"
short_cwd="${cwd/#$home_dir/\~}"

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
    colour="\033[0;31m"   # red
  elif [ "$pct" -ge 50 ]; then
    colour="\033[0;33m"   # yellow
  else
    colour="\033[0;32m"   # green
  fi

  local bar="${colour}"
  for (( i=0; i<filled; i++ )); do bar+="█"; done
  for (( i=0; i<empty; i++ ));  do bar+="░"; done
  bar+="\033[0m"

  echo "$bar"
}

# ── Build Output Segments ─────────────────────────────────────
# Each segment is conditionally built based on config toggles.
# Segments that are disabled produce empty strings and are skipped.

output=""

# Directory
if [ "$show_directory" = "true" ]; then
  output+="\033[0;36m${short_cwd}\033[0m"
fi

# Branch
if [ "$show_branch" = "true" ] && [ -n "$branch" ]; then
  output+="\033[0;35m on ${branch}\033[0m"
fi

# Model
if [ "$show_model" = "true" ]; then
  output+="  \033[0;34m${model:-?}\033[0m"
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
  if [ "$added_int" -gt 0 ] || [ "$removed_int" -gt 0 ]; then
    output+="  \033[0;32m+${added_int}\033[0m \033[0;31m-${removed_int}\033[0m"
  fi
fi

# Dirty file count — yellow reminder to commit
if [ "$show_dirty_count" = "true" ] && [ -n "$dirty_count" ] && [ "$dirty_count" -gt 0 ] 2>/dev/null; then
  output+="  \033[0;33m${dirty_count} dirty\033[0m"
fi

# Session duration — converted from ms to Xh Ym or Ym
if [ "$show_duration" = "true" ] && [ -n "$duration_ms" ] && [ "$duration_ms" != "0" ]; then
  total_secs=$(( ${duration_ms%%.*} / 1000 ))
  hours=$(( total_secs / 3600 ))
  mins=$(( (total_secs % 3600) / 60 ))

  if [ "$hours" -gt 0 ]; then
    output+="  \033[0;36m${hours}h${mins}m\033[0m"
  elif [ "$mins" -gt 0 ]; then
    output+="  \033[0;36m${mins}m\033[0m"
  fi
fi

# Worktree indicator — only when in an isolated worktree
if [ "$show_worktree" = "true" ] && [ -n "$worktree" ]; then
  output+="  \033[0;35m⎇ ${worktree}\033[0m"
fi

# Session cost in USD
if [ "$show_cost" = "true" ] && [ -n "$total_cost" ] && [ "$total_cost" != "0" ]; then
  output+="  \033[0;33m\$${total_cost}\033[0m"
fi

# ── Print ─────────────────────────────────────────────────────
printf "%b" "$output"
