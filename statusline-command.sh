#!/usr/bin/env bash
#
# Claude Code statusline script
#
# Displays a configurable status bar with two lines:
#   Line 1: Working directory, git branch, model, context bar, usage limits,
#           lines changed, dirty count, session cost, and more.
#   Line 2: Live activity — running tools, subagent status, todo progress
#           (optional, requires Node.js, reads Claude Code transcript).
#
# Usage limits are read from stdin (Claude Code >= 2.1) or fetched via OAuth API.
#
# This script receives JSON via stdin each time the statusline refreshes
# (after every assistant message, permission change, or vim mode toggle).
#
# Uses pure bash regex for JSON parsing — no jq dependency required.

set -e

# Restrict file permissions for cache/temp files (not world-readable)
umask 077

SCRIPT_DIR="${HOME}/.claude"
VERSION_FILE="${SCRIPT_DIR}/.statusline-version"
VERSION="unknown"
[ -f "$VERSION_FILE" ] && read -r VERSION < "$VERSION_FILE" 2>/dev/null || true
VERSION="${VERSION//[[:space:]]/}"

# Capture current epoch once — reused throughout to avoid repeated date forks
NOW_EPOCH=$(date +%s)

UPDATE_CHECK_INTERVAL=21600  # seconds between update checks (6 hours)
UPDATE_CACHE_FILE="${SCRIPT_DIR}/.statusline-update-cache"
REPO_RAW="https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main"

# ── Shared Helpers ──────────────────────────────────────────
# HTTP GET helper — returns body on stdout. Usage: http_get URL [TIMEOUT]
# Supports optional auth headers via $HTTP_AUTH_HEADER.
http_get() {
  local url="$1" timeout="${2:-3}"
  if command -v curl > /dev/null 2>&1; then
    if [ -n "${HTTP_AUTH_HEADER:-}" ]; then
      # Pass auth header via stdin to avoid exposing token in process list
      # -q suppresses .curlrc (e.g., Laragon's cainfo= causes warnings on MSYS2)
      # --fail-with-body returns exit code 22 on HTTP 4xx/5xx (e.g., 429 rate limit)
      curl -q -s --fail-with-body --max-time "$timeout" --config - "$url" 2>/dev/null <<EOF
header = "${HTTP_AUTH_HEADER}"
header = "anthropic-beta: oauth-2025-04-20"
header = "Content-Type: application/json"
EOF
    else
      curl -fsSL --max-time "$timeout" "$url" 2>/dev/null
    fi
  elif command -v wget > /dev/null 2>&1; then
    if [ -n "${HTTP_AUTH_HEADER:-}" ]; then
      wget -qO- --timeout="$timeout" --max-redirect=0 \
        --header="${HTTP_AUTH_HEADER}" \
        --header="anthropic-beta: oauth-2025-04-20" \
        --header="Content-Type: application/json" \
        "$url" 2>/dev/null
    else
      wget -qO- --timeout="$timeout" "$url" 2>/dev/null
    fi
  else
    return 1
  fi
}

# Parse an ISO 8601 timestamp to epoch seconds.
# Usage: iso_to_epoch "2026-03-10T13:59:59.654957+00:00"
iso_to_epoch() {
  local ts="$1"
  # Strip fractional seconds and timezone offset
  local clean="${ts%%.*}"
  clean="${clean%%+*}"
  if [[ "${OSTYPE:-}" == darwin* ]]; then
    date -juf "%Y-%m-%dT%H:%M:%S" "$clean" +%s 2>/dev/null
  else
    # GNU date (Linux & MSYS2/Windows)
    date -ud "${clean}" +%s 2>/dev/null
  fi
}

# ── CLI Flags ─────────────────────────────────────────────────
case "${1:-}" in
  --help|-h)
    echo "Usage: echo '<json>' | bash statusline-command.sh"
    echo ""
    echo "Reads Claude Code statusline JSON from stdin and outputs"
    echo "a formatted status bar for your terminal."
    echo ""
    echo "Flags:"
    echo "  --help           Show this help"
    echo "  --version        Print version"
    echo "  --check-update   Force update check"
    echo "  --dump-stdin     Show raw JSON from Claude Code (diagnostic)"
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
    remote_version=$(http_get "${REPO_RAW}/VERSION" 5 | tr -d '[:space:]') || remote_version=""
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
  --dump-stdin)
    # Diagnostic: show the raw JSON that Claude Code sends on stdin
    raw=$(cat)
    echo "$raw" | python3 -m json.tool 2>/dev/null || echo "$raw"
    echo ""
    echo "--- Fields detected ---"
    echo "$raw" | grep -qo '"rate_limits"' && echo "rate_limits: YES (stdin-native, real-time)" || echo "rate_limits: NO (using OAuth fallback)"
    echo "$raw" | grep -qo '"transcript_path"' && echo "transcript_path: YES (live activity available)" || echo "transcript_path: NO (no live activity)"
    echo "$raw" | grep -qo '"model"[[:space:]]*:' && echo "model (nested): YES (new schema)" || echo "model (nested): NO"
    echo "$raw" | grep -qo '"context_window"' && echo "context_window (nested): YES (new schema)" || echo "context_window (nested): NO"
    exit 0
    ;;
esac

# ── Update Check ─────────────────────────────────────────────
# Periodically fetches the remote VERSION file and caches the result.
# Runs in the background so it never slows down the statusline.
update_available=""

check_for_update() {
  # Read cache: "timestamp remote_version"
  if [ -f "$UPDATE_CACHE_FILE" ]; then
    local cached_time cached_version
    read -r cached_time cached_version < "$UPDATE_CACHE_FILE" 2>/dev/null || true
    # Guard: cached_time must be numeric (corrupted cache files may contain other data)
    case "$cached_time" in *[!0-9]*) cached_time="" ;; esac
    if [ -n "$cached_time" ] && [ $(( NOW_EPOCH - cached_time )) -lt $UPDATE_CHECK_INTERVAL ]; then
      # Cache is fresh — use cached result
      if [ -n "$cached_version" ] && [ "$cached_version" != "$VERSION" ]; then
        update_available="$cached_version"
      fi
      return
    fi
  fi

  # Cache is stale or missing — fetch in background and write cache
  (
    remote_version=$(http_get "${REPO_RAW}/VERSION" 3 | tr -d '[:space:]') || remote_version=""
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
#
# Segment priorities (used by truncation — lower = kept longer):
#   1=dir+branch  2=context  3=model,usage  4=cost  5=lines,dirty
#   6=ahead/behind,stash  7=duration  8=worktree  9=update

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
show_usage_5h=true
show_usage_7d=true
usage_cache_seconds=600
auto_hide=true
use_icons=true
context_warn_threshold=80
enable_truncation=false
max_width=""
use_groups=false
group_open="["
group_close="]"
colour_theme="default"
show_vim_mode=true
show_agent=true
show_tokens=false
bar_width=10
branch_max_length=""
show_activity=true

# Load user overrides (if any).
# Note: this file has the same trust level as .bashrc — it can contain
# arbitrary bash code. Only modify it yourself or via trusted tools.
STATUSLINE_CONF="${SCRIPT_DIR}/statusline.conf"
# shellcheck disable=SC1090
[ -f "$STATUSLINE_CONF" ] && . "$STATUSLINE_CONF"

# Backwards compatibility: accept old name
[ "${show_usage_weekly:-}" = "true" ] && show_usage_7d=true
[ "${show_usage_weekly:-}" = "false" ] && show_usage_7d=false

# ── Colour Themes ────────────────────────────────────────────
# Respect NO_COLOR standard (https://no-color.org/)
[ -n "${NO_COLOR:-}" ] && colour_theme="mono"

apply_theme() {
  case "${colour_theme:-default}" in
    nord)
      CLR_DIR="\033[38;5;81m"     # frost blue
      CLR_BRANCH="\033[38;5;139m"  # aurora purple
      CLR_MODEL="\033[38;5;111m"   # frost lighter blue
      CLR_MODEL_OPUS="\033[38;5;173m" # aurora orange (Opus tier)
      CLR_ADD="\033[38;5;108m"     # aurora green
      CLR_DEL="\033[38;5;174m"     # aurora red
      CLR_WARN="\033[38;5;179m"    # aurora yellow
      CLR_INFO="\033[38;5;110m"    # frost cyan
      CLR_DIM="\033[38;5;60m"     # polar night dim
      CLR_BAR_OK="\033[38;5;108m"  # aurora green
      CLR_BAR_MED="\033[38;5;179m" # aurora yellow
      CLR_BAR_HIGH="\033[38;5;174m" # aurora red
      CLR_PACE="\033[38;5;199m"    # hot pink pacing marker
      CLR_RESET="\033[0m"
      ;;
    dracula)
      CLR_DIR="\033[38;5;141m"     # purple
      CLR_BRANCH="\033[38;5;212m"  # pink
      CLR_MODEL="\033[38;5;117m"   # cyan
      CLR_MODEL_OPUS="\033[38;5;215m" # orange #ffb86c (Opus tier)
      CLR_ADD="\033[38;5;84m"      # green
      CLR_DEL="\033[38;5;210m"     # red
      CLR_WARN="\033[38;5;228m"    # yellow
      CLR_INFO="\033[38;5;117m"    # cyan
      CLR_DIM="\033[38;5;61m"     # comment grey
      CLR_BAR_OK="\033[38;5;84m"   # green
      CLR_BAR_MED="\033[38;5;228m" # yellow
      CLR_BAR_HIGH="\033[38;5;210m" # red
      CLR_PACE="\033[38;5;212m"    # pink pacing marker
      CLR_RESET="\033[0m"
      ;;
    solarized)
      CLR_DIR="\033[38;5;37m"     # cyan
      CLR_BRANCH="\033[38;5;61m"  # violet
      CLR_MODEL="\033[38;5;33m"   # blue
      CLR_MODEL_OPUS="\033[38;5;166m" # solarized orange (Opus tier)
      CLR_ADD="\033[38;5;64m"     # green
      CLR_DEL="\033[38;5;160m"    # red
      CLR_WARN="\033[38;5;136m"   # yellow
      CLR_INFO="\033[38;5;37m"    # cyan
      CLR_DIM="\033[38;5;240m"   # base01 dim
      CLR_BAR_OK="\033[38;5;64m"  # green
      CLR_BAR_MED="\033[38;5;136m" # yellow
      CLR_BAR_HIGH="\033[38;5;160m" # red
      CLR_PACE="\033[38;5;125m"    # magenta pacing marker
      CLR_RESET="\033[0m"
      ;;
    tokyo-night)
      CLR_DIR="\033[38;5;111m"    # blue #7aa2f7
      CLR_BRANCH="\033[38;5;141m" # purple #bb9af7
      CLR_MODEL="\033[38;5;117m"  # cyan #7dcfff
      CLR_MODEL_OPUS="\033[38;5;215m" # orange #ff9e64 (Opus tier)
      CLR_ADD="\033[38;5;149m"    # green #9ece6a
      CLR_DEL="\033[38;5;204m"    # red #f7768e
      CLR_WARN="\033[38;5;179m"   # yellow #e0af68
      CLR_INFO="\033[38;5;117m"   # cyan #7dcfff
      CLR_DIM="\033[38;5;59m"    # comment #565f89
      CLR_BAR_OK="\033[38;5;149m" # green #9ece6a
      CLR_BAR_MED="\033[38;5;179m" # yellow #e0af68
      CLR_BAR_HIGH="\033[38;5;204m" # red #f7768e
      CLR_PACE="\033[38;5;198m"   # pink #ff007c
      CLR_RESET="\033[0m"
      ;;
    catppuccin)
      CLR_DIR="\033[38;5;111m"    # blue #89b4fa
      CLR_BRANCH="\033[38;5;183m" # mauve #cba6f7
      CLR_MODEL="\033[38;5;116m"  # sapphire #74c7ec
      CLR_MODEL_OPUS="\033[38;5;216m" # peach #fab387 (Opus tier)
      CLR_ADD="\033[38;5;150m"    # green #a6e3a1
      CLR_DEL="\033[38;5;211m"    # red #f38ba8
      CLR_WARN="\033[38;5;223m"   # yellow #f9e2af
      CLR_INFO="\033[38;5;116m"   # sapphire #74c7ec
      CLR_DIM="\033[38;5;243m"   # overlay0 #6c7086
      CLR_BAR_OK="\033[38;5;150m" # green #a6e3a1
      CLR_BAR_MED="\033[38;5;223m" # yellow #f9e2af
      CLR_BAR_HIGH="\033[38;5;211m" # red #f38ba8
      CLR_PACE="\033[38;5;218m"   # pink #f5c2e7
      CLR_RESET="\033[0m"
      ;;
    mono)
      CLR_DIR="" CLR_BRANCH="" CLR_MODEL="" CLR_MODEL_OPUS=""
      CLR_ADD="" CLR_DEL="" CLR_WARN="" CLR_INFO="" CLR_DIM=""
      CLR_BAR_OK="" CLR_BAR_MED="" CLR_BAR_HIGH="" CLR_PACE=""
      CLR_RESET=""
      ;;
    *) # default — original colours
      CLR_DIR="\033[0;36m"     # cyan
      CLR_BRANCH="\033[0;35m"  # magenta
      CLR_MODEL="\033[0;34m"   # blue
      CLR_MODEL_OPUS="\033[38;5;208m" # orange (Opus tier)
      CLR_ADD="\033[0;32m"     # green
      CLR_DEL="\033[0;31m"     # red
      CLR_WARN="\033[0;33m"    # yellow
      CLR_INFO="\033[0;36m"    # cyan
      CLR_DIM="\033[0;90m"    # dark grey
      CLR_BAR_OK="\033[0;32m"  # green
      CLR_BAR_MED="\033[0;33m" # yellow
      CLR_BAR_HIGH="\033[0;31m" # red
      CLR_PACE="\033[38;5;199m"  # hot pink pacing marker
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
# All four variants share common regex logic. The _from variants
# accept an explicit JSON string; the plain variants use $input.

# Extract a string value by key from a JSON string
# Usage: extract_from "$json" "key"
extract_from() {
  local json="$1" key="$2"
  local pattern="\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  if [[ $json =~ $pattern ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

# Extract a numeric value by key from a JSON string
# Usage: extract_num_from "$json" "key"
extract_num_from() {
  local json="$1" key="$2"
  local pattern="\"$key\"[[:space:]]*:[[:space:]]*([0-9]+\.?[0-9]*)"
  if [[ $json =~ $pattern ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

# Extract a JSON object block by key, returning content between { }
# Handles one level of nested braces (e.g., inner objects within the block).
# Usage: extract_block "$json" "key"
extract_block() {
  local json="$1" key="$2"
  local pattern="\"$key\"[[:space:]]*:[[:space:]]*\{(([^{}]|\{[^}]*\})+)\}"
  if [[ $json =~ $pattern ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

# Convenience wrappers that operate on the global $input
extract()     { extract_from "$input" "$1"; }
extract_num() { extract_num_from "$input" "$1"; }

# Strip ANSI escape sequences and control characters from untrusted strings.
# Handles CSI (ESC[...), OSC terminated by BEL or ST (ESC\), and DCS/APC.
sanitize() {
  local val="$1"
  # Remove ANSI escape sequences (CSI, OSC with BEL, OSC with ST)
  val=$(printf '%s' "$val" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\][^\x07]*\x07//g; s/\x1b\][^\x1b]*\x1b\\//g; s/\x1b[PX_^][^\x1b]*\x1b\\//g')
  # Remove remaining control characters (except space)
  val=$(printf '%s' "$val" | tr -d '\000-\037\177')
  echo "$val"
}

# Strip ANSI escapes for width measurement (used by truncation)
strip_ansi() {
  printf '%b' "$1" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\][^\x07]*\x07//g; s/\x1b\][^\x1b]*\x1b\\//g'
}

visible_width() {
  local stripped
  stripped=$(strip_ansi "$1")
  echo ${#stripped}
}

# ── Extract Fields ────────────────────────────────────────────

# Working directory: prefer workspace.current_dir, fall back to top-level cwd
cwd=""
ws_block=$(extract_block "$input" "workspace")
[ -n "$ws_block" ] && cwd=$(extract_from "$ws_block" "current_dir")
[ -z "$cwd" ] && cwd=$(extract "cwd")

# Sanitize cwd before using it in git commands (defends against directory traversal)
cwd=$(sanitize "$cwd")

# Model display name: prefer model.display_name (new schema), fall back to top-level
model=""
model_block=$(extract_block "$input" "model")
[ -n "$model_block" ] && model=$(extract_from "$model_block" "display_name")
[ -z "$model" ] && model=$(extract "display_name")

# Context window usage: prefer context_window.used_percentage (new schema), fall back.
# The fallback only runs when rate_limits is absent (old flat schema) to avoid
# matching rate_limits.five_hour.used_percentage by accident.
used=""
cw_block=$(extract_block "$input" "context_window")
[ -n "$cw_block" ] && used=$(extract_num_from "$cw_block" "used_percentage")
if [ -z "$used" ]; then
  rl_check='"rate_limits"[[:space:]]*:'
  [[ ! $input =~ $rl_check ]] && used=$(extract_num "used_percentage")
fi

# Context window total size in tokens
context_size=""
[ -n "$cw_block" ] && context_size=$(extract_num_from "$cw_block" "context_window_size")
[ -z "$context_size" ] && context_size=$(extract_num "context_window_size")

# Transcript path (for live activity — new in CC 2.1+)
transcript_path=$(extract "transcript_path")

# Cumulative session cost in USD
total_cost=$(extract_num "total_cost_usd")

# Lines changed during this session
lines_added=$(extract_num "total_lines_added")
lines_removed=$(extract_num "total_lines_removed")

# Session duration in milliseconds
duration_ms=$(extract_num "total_duration_ms")

# Worktree name — extract from worktree block to avoid collision with agent.name
worktree=""
wt_block=$(extract_block "$input" "worktree")
if [ -n "$wt_block" ]; then
  worktree=$(sanitize "$(extract_from "$wt_block" "name")")
fi

# ── Working Directory ─────────────────────────────────────────
# Replace home directory prefix with ~ for a shorter display
home_dir="$HOME"
short_cwd="${cwd/#$home_dir/\~}"
short_cwd=$(sanitize "$short_cwd")

# ── Git Info ──────────────────────────────────────────────────
# Detect branch, dirty count, ahead/behind, and stash count.
# Uses -c core.fsmonitor=false to skip filesystem monitoring overhead.
# Guard: cwd must be a real directory to avoid traversal via crafted JSON.
branch=""
dirty_count=""
ahead_count=""
behind_count=""
stash_count=""
if [ -n "$cwd" ] && [ -d "$cwd" ] && git -C "$cwd" --no-optional-locks -c core.fsmonitor=false rev-parse --git-dir > /dev/null 2>&1; then
  if [ "$show_branch" = "true" ]; then
    branch=$(git -C "$cwd" --no-optional-locks -c core.fsmonitor=false symbolic-ref --short HEAD 2>/dev/null \
      || git -C "$cwd" --no-optional-locks -c core.fsmonitor=false rev-parse --short HEAD 2>/dev/null)
    branch=$(sanitize "$branch")
    if [ -n "$branch_max_length" ] && [ "${#branch}" -gt "$branch_max_length" ] 2>/dev/null; then
      branch="${branch:0:$branch_max_length}…"
    fi
  fi

  # Count uncommitted files (staged + unstaged + untracked).
  if [ "$show_dirty_count" = "true" ]; then
    dirty_count=$(git -C "$cwd" --no-optional-locks -c core.fsmonitor=false status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  fi

  # Ahead/behind remote — silently hidden when no upstream or detached HEAD.
  # The || ab_output="" is critical: without it, set -e kills the script.
  if [ "$show_ahead_behind" = "true" ]; then
    # shellcheck disable=SC1083
    ab_output=$(git -C "$cwd" --no-optional-locks -c core.fsmonitor=false rev-list --left-right --count HEAD...@{upstream} 2>/dev/null) || ab_output=""
    if [ -n "$ab_output" ]; then
      ahead_count=$(echo "$ab_output" | cut -f1)
      behind_count=$(echo "$ab_output" | cut -f2)
    fi
  fi

  # Stash count
  if [ "$show_stash" = "true" ]; then
    stash_count=$(git -C "$cwd" --no-optional-locks -c core.fsmonitor=false stash list 2>/dev/null | wc -l | tr -d ' ')
  fi
fi

# ── Live Activity (transcript parsing via Node.js helper) ────
# Reads Claude Code's JSONL transcript for tool/agent/todo activity.
# Runs in background; uses cached result from previous invocation.
ACTIVITY_CACHE_FILE="${SCRIPT_DIR}/.statusline-activity-cache"
HELPER_SCRIPT="${SCRIPT_DIR}/statusline-helper.js"
activity_line=""

if [ "$show_activity" = "true" ] && [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  if command -v node > /dev/null 2>&1 && [ -f "$HELPER_SCRIPT" ]; then
    # Spawn helper in background (non-blocking)
    ( node "$HELPER_SCRIPT" "$transcript_path" "$ACTIVITY_CACHE_FILE" 2>/dev/null ) &

    # Read cached activity from previous run
    if [ -f "$ACTIVITY_CACHE_FILE" ]; then
      cached_act_ts="" cached_act_json=""
      { read -r cached_act_ts cached_act_json; } < "$ACTIVITY_CACHE_FILE" 2>/dev/null || true
      case "$cached_act_ts" in *[!0-9]*) cached_act_ts=0 ;; esac
      # Expire after 30 seconds (activity becomes stale quickly)
      if [ -n "$cached_act_ts" ] && [ $(( NOW_EPOCH - cached_act_ts )) -le 30 ] 2>/dev/null; then
        # Extract "activity" value from simple JSON {"activity":"..."}
        act_pattern='"activity"[[:space:]]*:[[:space:]]*"([^"]*)"'
        if [[ ${cached_act_json:-} =~ $act_pattern ]]; then
          activity_line="${BASH_REMATCH[1]}"
          activity_line=$(sanitize "$activity_line")
        fi
      fi
    fi
  fi
fi

# ── Usage Limits (5-hour and 7-day) ─────────────────────────
# Preferred: read rate_limits from stdin (Claude Code >= 2.1).
# Fallback:  fetch from Anthropic OAuth API with background caching.

usage_5h="" usage_5h_resets="" usage_7d="" usage_7d_resets=""

# ── Phase 1: Try stdin rate_limits (zero-cost, real-time) ────
stdin_usage=false
rl_guard='"rate_limits"[[:space:]]*:[[:space:]]*\{'
if [[ $input =~ $rl_guard ]]; then
  fh_stdin_block=$(extract_block "$input" "five_hour")
  if [ -n "$fh_stdin_block" ]; then
    stdin_5h=$(extract_num_from "$fh_stdin_block" "used_percentage")
    stdin_5h_resets=$(extract_num_from "$fh_stdin_block" "resets_at")
    if [ -n "$stdin_5h" ]; then
      usage_5h="$stdin_5h"
      # resets_at from stdin is epoch seconds — convert to ISO for pacing compat
      if [ -n "$stdin_5h_resets" ]; then
        stdin_5h_resets_int="${stdin_5h_resets%%.*}"
        if [[ "${OSTYPE:-}" == darwin* ]]; then
          usage_5h_resets=$(date -r "$stdin_5h_resets_int" -u '+%Y-%m-%dT%H:%M:%S+00:00' 2>/dev/null) || usage_5h_resets=""
        else
          usage_5h_resets=$(date -ud "@$stdin_5h_resets_int" '+%Y-%m-%dT%H:%M:%S+00:00' 2>/dev/null) || usage_5h_resets=""
        fi
      fi
      stdin_usage=true
    fi
  fi
  sd_stdin_block=$(extract_block "$input" "seven_day")
  if [ -n "$sd_stdin_block" ]; then
    stdin_7d=$(extract_num_from "$sd_stdin_block" "used_percentage")
    stdin_7d_resets=$(extract_num_from "$sd_stdin_block" "resets_at")
    if [ -n "$stdin_7d" ]; then
      usage_7d="$stdin_7d"
      if [ -n "$stdin_7d_resets" ]; then
        stdin_7d_resets_int="${stdin_7d_resets%%.*}"
        if [[ "${OSTYPE:-}" == darwin* ]]; then
          usage_7d_resets=$(date -r "$stdin_7d_resets_int" -u '+%Y-%m-%dT%H:%M:%S+00:00' 2>/dev/null) || usage_7d_resets=""
        else
          usage_7d_resets=$(date -ud "@$stdin_7d_resets_int" '+%Y-%m-%dT%H:%M:%S+00:00' 2>/dev/null) || usage_7d_resets=""
        fi
      fi
      stdin_usage=true
    fi
  fi
fi

# ── Phase 2: OAuth API Fallback (older Claude Code versions) ─
# Only runs if stdin didn't provide rate limits.
if [ "$stdin_usage" = "false" ]; then

USAGE_CACHE_FILE="${SCRIPT_DIR}/.statusline-usage-cache"

fetch_usage_token() {
  local creds="" token=""
  if [[ "${OSTYPE:-}" == darwin* ]]; then
    # macOS: read from Keychain
    creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) || creds=""
  fi
  # Linux / Windows / macOS fallback: read from credentials file
  if [ -z "$creds" ] && [ -f "${SCRIPT_DIR}/.credentials.json" ]; then
    creds=$(cat "${SCRIPT_DIR}/.credentials.json" 2>/dev/null) || creds=""
  fi
  [ -z "$creds" ] && return 1
  token=$(extract_from "$creds" "accessToken")
  [ -z "$token" ] && return 1
  echo "$token"
}

USAGE_BACKOFF_FILE="${SCRIPT_DIR}/.statusline-usage-backoff"

usage_backoff_increase() {
  # Exponential backoff: double the wait each failure, cap at 30 min.
  local prev_backoff=0
  [ -f "$USAGE_BACKOFF_FILE" ] && read -r prev_backoff < "$USAGE_BACKOFF_FILE" 2>/dev/null
  case "$prev_backoff" in *[!0-9]*) prev_backoff=0 ;; esac
  local next_backoff=$(( prev_backoff > 0 ? prev_backoff * 2 : usage_cache_seconds * 2 ))
  [ "$next_backoff" -gt 1800 ] && next_backoff=1800
  printf '%s %s\n' "$next_backoff" "$NOW_EPOCH" > "$USAGE_BACKOFF_FILE"
}

fetch_usage_data() {
  local token response
  token=$(fetch_usage_token) || return 1
  HTTP_AUTH_HEADER="Authorization: Bearer $token"
  response=$(http_get "https://api.anthropic.com/api/oauth/usage" 3) || {
    HTTP_AUTH_HEADER=""
    usage_backoff_increase
    return 1
  }
  HTTP_AUTH_HEADER=""
  # Sanity check: response must contain "five_hour" or "seven_day"
  case "$response" in
    *five_hour*|*seven_day*) ;;
    *) usage_backoff_increase; return 1 ;;
  esac
  # Success — clear backoff and update cache
  rm -f "$USAGE_BACKOFF_FILE"
  echo "${NOW_EPOCH} ${response}" > "$USAGE_CACHE_FILE"
}

# Refresh cache if stale or missing (only when usage segments are enabled).
# Runs in a background subshell so it never blocks the statusline.
if [ "$show_usage_5h" = "true" ] || [ "$show_usage_7d" = "true" ]; then
  needs_fetch=false
  usage_stale=false
  if [ ! -f "$USAGE_CACHE_FILE" ]; then
    needs_fetch=true
  else
    # Read embedded timestamp from cache (format: "epoch json...")
    read -r cached_ts _ < "$USAGE_CACHE_FILE" 2>/dev/null || cached_ts=0
    # Guard: cached_ts must be numeric (old-format cache files lack the timestamp)
    case "$cached_ts" in *[!0-9]*) cached_ts=0 ;; esac
    cache_age=$(( NOW_EPOCH - cached_ts ))
    # Determine effective refresh interval (respects exponential backoff on 429)
    effective_interval="$usage_cache_seconds"
    if [ -f "$USAGE_BACKOFF_FILE" ]; then
      read -r backoff_secs backoff_ts < "$USAGE_BACKOFF_FILE" 2>/dev/null || backoff_secs=0
      case "$backoff_secs" in *[!0-9]*) backoff_secs=0 ;; esac
      case "$backoff_ts" in *[!0-9]*) backoff_ts=0 ;; esac
      # Expire backoff after 30 min so we don't stay stuck forever
      if [ "$backoff_ts" -gt 0 ] && [ $(( NOW_EPOCH - backoff_ts )) -gt 1800 ] 2>/dev/null; then
        rm -f "$USAGE_BACKOFF_FILE"
        backoff_secs=0
      fi
      [ "$backoff_secs" -gt "$effective_interval" ] && effective_interval="$backoff_secs"
    fi
    if [ "$cache_age" -gt "$effective_interval" ] 2>/dev/null; then
      needs_fetch=true
    fi
    # Mark stale if cache is older than twice the base interval
    if [ "$cache_age" -gt $(( usage_cache_seconds * 2 )) ] 2>/dev/null; then
      usage_stale=true
    fi
  fi
  if [ "$needs_fetch" = "true" ]; then
    ( fetch_usage_data 2>/dev/null ) &
  fi

  # Parse cached usage data (may be from previous run if fetch is in-flight)
  if [ -f "$USAGE_CACHE_FILE" ]; then
    # Skip the embedded timestamp, rest is JSON
    usage_json=""
    { read -r _ usage_json; } < "$USAGE_CACHE_FILE" 2>/dev/null || usage_json=""
    # Handle old-format cache (raw JSON without epoch prefix)
    case "$usage_json" in
      "{"*) ;; # already looks like JSON, good
      *) usage_json="" ;; # discard non-JSON (stale or corrupt cache)
    esac
    if [ -n "$usage_json" ]; then
      # Extract five_hour block
      fh_pattern='"five_hour"[[:space:]]*:[[:space:]]*\{([^}]+)\}'
      if [[ $usage_json =~ $fh_pattern ]]; then
        fh_block="${BASH_REMATCH[1]}"
        usage_5h=$(extract_num_from "$fh_block" "utilization")
        usage_5h_resets=$(extract_from "$fh_block" "resets_at")
      fi
      # Extract seven_day block
      sd_pattern='"seven_day"[[:space:]]*:[[:space:]]*\{([^}]+)\}'
      if [[ $usage_json =~ $sd_pattern ]]; then
        sd_block="${BASH_REMATCH[1]}"
        usage_7d=$(extract_num_from "$sd_block" "utilization")
        usage_7d_resets=$(extract_from "$sd_block" "resets_at")
      fi
    fi
  fi
fi

fi  # end OAuth fallback (stdin_usage=false)

# Calculate pacing targets — what percentage you *should* have used
# for even consumption across the rolling window.
calc_pacing_target() {
  local resets_at="$1" window_secs="$2"
  local reset_ts start_ts elapsed target
  reset_ts=$(iso_to_epoch "$resets_at") || return 1
  start_ts=$(( reset_ts - window_secs ))
  elapsed=$(( NOW_EPOCH - start_ts ))
  [ "$elapsed" -lt 0 ] && elapsed=0
  [ "$elapsed" -gt "$window_secs" ] && elapsed=$window_secs
  target=$(( (elapsed * 100 + window_secs / 2) / window_secs ))
  echo "$target"
}

# Format a reset timestamp into a short human-readable label
format_reset_label() {
  local resets_at="$1" style="$2"
  local reset_ts
  reset_ts=$(iso_to_epoch "$resets_at") || return 1
  # Round to nearest hour for cleaner display
  local rounded_ts=$(( (reset_ts + 1800) / 3600 * 3600 ))
  if [ "$style" = "time" ]; then
    # Short time like "11pm" or "3am"
    if [[ "${OSTYPE:-}" == darwin* ]]; then
      date -r "$rounded_ts" '+%-l%p' 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d ' '
    else
      date -d "@$rounded_ts" '+%-l%p' 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d ' '
    fi
  elif [ "$style" = "day" ]; then
    # Day + time like "Thu,3pm"
    local d h
    if [[ "${OSTYPE:-}" == darwin* ]]; then
      d=$(date -r "$rounded_ts" '+%a' 2>/dev/null | tr '[:upper:]' '[:lower:]')
      h=$(date -r "$rounded_ts" '+%-l%p' 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    else
      d=$(date -d "@$rounded_ts" '+%a' 2>/dev/null | tr '[:upper:]' '[:lower:]')
      h=$(date -d "@$rounded_ts" '+%-l%p' 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    fi
    echo "${d},${h}"
  fi
}

# ── Context Window Progress Bar ───────────────────────────────
# Visual bar showing how much of the context window has been consumed.
# Colour shifts from green → yellow → red as usage increases.
build_progress_bar() {
  local pct=${1:-0}
  local target_pct=${2:-}
  local width="${bar_width:-10}"
  local filled=$(( pct * width / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width

  # Calculate target marker position (-1 = no marker)
  local target_pos=-1
  if [ -n "$target_pct" ] && [ "$target_pct" -ge 0 ] 2>/dev/null && [ "$target_pct" -le 100 ]; then
    target_pos=$(( target_pct * width / 100 ))
    [ "$target_pos" -ge "$width" ] && target_pos=$(( width - 1 ))
  fi

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
  for (( i=0; i<width; i++ )); do
    if [ "$i" -eq "$target_pos" ]; then
      bar+="${CLR_PACE}│${colour}"
    elif [ "$i" -lt "$filled" ]; then
      bar+="█"
    else
      bar+="${CLR_DIM}░${colour}"
    fi
  done
  bar+="$CLR_RESET"

  # Output: bar\ncolour (caller can read second line for percentage colouring)
  printf '%s\n%s' "$bar" "$colour"
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

# Session start placeholder — before first API response, fields are null/empty
if [ -z "$model" ] && [ -z "$used" ]; then
  printf "%b" "${CLR_DIM:-\033[2m}Starting...${CLR_RESET}"
  exit 0
fi

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

# Vim mode indicator (priority 3)
if [ "$show_vim_mode" = "true" ]; then
  vim_block=$(extract_block "$input" "vim")
  if [ -n "$vim_block" ]; then
    vim_mode=$(extract_from "$vim_block" "mode")
    [ -n "$vim_mode" ] && add_seg "${CLR_INFO}${vim_mode}${CLR_RESET}" 3
  fi
fi

# Model (priority 3) — coloured by tier: Haiku=green, Sonnet=yellow, Opus=orange
if [ "$show_model" = "true" ]; then
  model_icon=""
  [ "$use_icons" = "true" ] && model_icon="◆ "
  case "${model:-}" in
    *Haiku*)  model_clr="$CLR_ADD" ;;                # green (cheap)
    *Sonnet*) model_clr="$CLR_WARN" ;;               # yellow (mid)
    *Opus*)   model_clr="$CLR_MODEL_OPUS" ;;          # theme-aware orange (premium)
    *)        model_clr="$CLR_MODEL" ;;               # default blue
  esac
  # Respect NO_COLOR / mono theme
  [ -z "$CLR_RESET" ] && model_clr=""
  add_seg "${model_clr}${model_icon}${model:-?}${CLR_RESET}" 3 "ctx"
fi

# Agent name (priority 3)
if [ "$show_agent" = "true" ]; then
  agent_block=$(extract_block "$input" "agent")
  if [ -n "$agent_block" ]; then
    agent_name=$(extract_from "$agent_block" "name")
    if [ -n "$agent_name" ]; then
      agent_name=$(sanitize "$agent_name")
      agent_icon=""
      [ "$use_icons" = "true" ] && agent_icon="▸ "
      add_seg "${CLR_MODEL}${agent_icon}${agent_name}${CLR_RESET}" 3
    fi
  fi
fi

# Context bar (priority 2)
if [ "$show_context_bar" = "true" ]; then
  pct="${used:-0}"
  pct_int="${pct%%.*}"
  bar_output=$(build_progress_bar "$pct_int")
  progress_bar="${bar_output%%$'\n'*}"
  bar_clr="${bar_output#*$'\n'}"
  warn_prefix=""
  if [ "$pct_int" -ge "${context_warn_threshold:-80}" ] 2>/dev/null; then
    [ "$use_icons" = "true" ] && warn_prefix="${CLR_WARN}▲${CLR_RESET} "
  fi
  ctx_suffix=""
  if [ -n "$context_size" ] && [ "$context_size" != "0" ]; then
    ctx_int=${context_size%%.*}
    if [ "$ctx_int" -ge 1000000 ] 2>/dev/null; then
      ctx_m=$(( ctx_int / 1000000 ))
      ctx_tenths=$(( (ctx_int % 1000000) / 100000 ))
      if [ "$ctx_tenths" -eq 0 ]; then
        ctx_suffix=" of ${ctx_m}M"
      else
        ctx_suffix=" of ${ctx_m}.${ctx_tenths}M"
      fi
    else
      ctx_suffix=" of $(( ctx_int / 1000 ))k"
    fi
  fi
  add_seg "${warn_prefix}${progress_bar} ${bar_clr}${pct_int}%${ctx_suffix}${CLR_RESET}" 2 "ctx"
fi

# 200k token warning (automatic — no config toggle)
exceed_pattern='"exceeds_200k_tokens"[[:space:]]*:[[:space:]]*true'
if [[ $input =~ $exceed_pattern ]]; then
  add_seg "${CLR_WARN}▲ 200k+${CLR_RESET}" 2 "ctx"
fi

# Token counts (priority 5) — reuses $cw_block from context window extraction above
if [ "$show_tokens" = "true" ]; then
  if [ -n "$cw_block" ]; then
    tok_in=$(extract_num_from "$cw_block" "total_input_tokens")
    tok_out=$(extract_num_from "$cw_block" "total_output_tokens")
    tok_in_k=$(( ${tok_in:-0} / 1000 ))
    tok_out_k=$(( ${tok_out:-0} / 1000 ))
    if [ "$auto_hide" != "true" ] || [ "$tok_in_k" -gt 0 ] || [ "$tok_out_k" -gt 0 ]; then
      add_seg "${CLR_INFO}${tok_in_k}k in ${tok_out_k}k out${CLR_RESET}" 5
    fi
  fi
fi

# Staleness suffix — appended to usage % when cache is > 3 min old
# (API rate-limiting can prevent refreshes, so stale data gets a ~ marker)
usage_stale_suffix=""
[ "${usage_stale:-false}" = "true" ] && usage_stale_suffix="~"

# 5-hour usage limit (priority 3)
if [ "$show_usage_5h" = "true" ] && [ -n "$usage_5h" ]; then
  u5_int="${usage_5h%%.*}"
  u5_target=""
  u5_label=""
  if [ -n "$usage_5h_resets" ]; then
    u5_target=$(calc_pacing_target "$usage_5h_resets" $((5 * 3600))) || u5_target=""
    u5_reset_label=$(format_reset_label "$usage_5h_resets" "time") || u5_reset_label=""
    [ -n "$u5_reset_label" ] && u5_label="(${u5_reset_label})"
  fi
  u5_bar_output=$(build_progress_bar "$u5_int" "$u5_target")
  u5_bar="${u5_bar_output%%$'\n'*}"
  u5_bar_clr="${u5_bar_output#*$'\n'}"
  add_seg "5hr${u5_label:+ ${u5_label}} ${u5_bar} ${u5_bar_clr}${u5_int}%${CLR_RESET}${usage_stale_suffix}" 3 "usage"
fi

# Weekly usage limit (priority 3)
if [ "$show_usage_7d" = "true" ] && [ -n "$usage_7d" ]; then
  u7_int="${usage_7d%%.*}"
  u7_target=""
  u7_label=""
  if [ -n "$usage_7d_resets" ]; then
    u7_target=$(calc_pacing_target "$usage_7d_resets" $((7 * 86400))) || u7_target=""
    u7_reset_label=$(format_reset_label "$usage_7d_resets" "day") || u7_reset_label=""
    [ -n "$u7_reset_label" ] && u7_label="(${u7_reset_label})"
  fi
  u7_bar_output=$(build_progress_bar "$u7_int" "$u7_target")
  u7_bar="${u7_bar_output%%$'\n'*}"
  u7_bar_clr="${u7_bar_output#*$'\n'}"
  add_seg "wk${u7_label:+ ${u7_label}} ${u7_bar} ${u7_bar_clr}${u7_int}%${CLR_RESET}${usage_stale_suffix}" 3 "usage"
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
  [ "$use_icons" = "true" ] && dur_icon=""

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
  [ "$use_icons" = "true" ] && wt_icon="⊞ "
  add_seg "${CLR_BRANCH}${wt_icon}${worktree}${CLR_RESET}" 8
fi

# Session cost (priority 4)
if [ "$show_cost" = "true" ] && [ -n "$total_cost" ]; then
  cost_is_zero=false
  case "$total_cost" in 0|0.0|0.00|0.000) cost_is_zero=true ;; esac
  if [ "$auto_hide" != "true" ] || [ "$cost_is_zero" = "false" ]; then
    cost_fmt=$(printf "%.2f" "$total_cost" 2>/dev/null) || cost_fmt="$total_cost"
    # Colour by cost: green < $1, yellow $1-$5, red $5+
    cost_cents=$(printf "%.0f" "$(awk -v c="$total_cost" 'BEGIN {print c * 100}' 2>/dev/null)" 2>/dev/null) || cost_cents=0
    if [ "${cost_cents:-0}" -ge 500 ] 2>/dev/null; then
      cost_clr="$CLR_BAR_HIGH"
    elif [ "${cost_cents:-0}" -ge 100 ] 2>/dev/null; then
      cost_clr="$CLR_WARN"
    else
      cost_clr="$CLR_ADD"
    fi
    add_seg "${cost_clr}\$${cost_fmt}${CLR_RESET}" 4 "session"
  fi
fi

# Cost rate (priority 4)
if [ "$show_cost_rate" = "true" ] && [ -n "$total_cost" ] && [ -n "$duration_ms" ]; then
  dur_int="${duration_ms%%.*}"
  if [ "$dur_int" -ge 60000 ] 2>/dev/null; then
    cost_rate=$(awk -v cost="$total_cost" -v dur="$dur_int" 'BEGIN {printf "%.2f", cost / (dur / 3600000)}' 2>/dev/null) || cost_rate=""
    if [ -n "$cost_rate" ]; then
      rate_is_zero=false
      case "$cost_rate" in 0.00) rate_is_zero=true ;; esac
      if [ "$auto_hide" != "true" ] || [ "$rate_is_zero" = "false" ]; then
        rate_cents=$(printf "%.0f" "$(awk -v c="$cost_rate" 'BEGIN {print c * 100}' 2>/dev/null)" 2>/dev/null) || rate_cents=0
        if [ "${rate_cents:-0}" -ge 500 ] 2>/dev/null; then
          rate_clr="$CLR_BAR_HIGH"
        elif [ "${rate_cents:-0}" -ge 100 ] 2>/dev/null; then
          rate_clr="$CLR_WARN"
        else
          rate_clr="$CLR_ADD"
        fi
        add_seg "${rate_clr}\$${cost_rate}/hr${CLR_RESET}" 4 "session"
      fi
    fi
  fi
fi

# Update notification (priority 9 — lowest)
if [ -n "$update_available" ]; then
  update_icon=""
  [ "$use_icons" = "true" ] && update_icon="↑ "
  add_seg "${CLR_ADD}${update_icon}update available${CLR_RESET}" 9
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

  # Pre-compute visible widths (avoids repeated subshell forks in the loop)
  for (( i=0; i<seg_idx; i++ )); do
    seg_widths[$i]=$(visible_width "${seg_vals[$i]}")
  done

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
      total=$((total + ${seg_widths[$i]}))
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

# ── Line 1: Status bar ───────────────────────────────────────
printf "%b" "$output"

# ── Line 2: Live activity (optional) ────────────────────────
if [ -n "$activity_line" ]; then
  printf '\n'
  printf "%b" "${CLR_DIM}${activity_line}${CLR_RESET}"
fi
