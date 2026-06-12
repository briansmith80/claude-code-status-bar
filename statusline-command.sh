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

# ${#s} and ${s:0:n} count characters per the locale; under a non-UTF-8
# locale (LANG unset, LC_ALL=C) they count bytes, which over-trims line 2
# and can slice a multibyte glyph. Probe and adopt a UTF-8 locale if needed.
sl_probe='█'
if [ "${#sl_probe}" -ne 1 ]; then
  sl_saved_lc="${LC_ALL-}"
  for sl_loc in C.UTF-8 en_US.UTF-8; do
    export LC_ALL="$sl_loc" 2>/dev/null
    [ "${#sl_probe}" -eq 1 ] && break
    if [ -n "$sl_saved_lc" ]; then export LC_ALL="$sl_saved_lc"; else unset LC_ALL; fi
  done
  unset sl_saved_lc sl_loc
fi
unset sl_probe

SCRIPT_DIR="${HOME}/.claude"
VERSION_FILE="${SCRIPT_DIR}/.statusline-version"
VERSION="unknown"
[ -f "$VERSION_FILE" ] && read -r VERSION < "$VERSION_FILE" 2>/dev/null || true
VERSION="${VERSION//[[:space:]]/}"

# Capture current epoch once — reused throughout to avoid repeated date forks
NOW_EPOCH=$(date +%s)

# ── Profiling (STATUSLINE_PROFILE=1) ──────────────────────────
# Per-phase wall-clock to stderr. Each checkpoint costs one date fork, so
# absolute numbers are inflated on Windows; the relative ranking is what
# matters. Zero overhead when unset (no-op function).
if [ -n "${STATUSLINE_PROFILE:-}" ]; then
  SL_PROF_LAST=$(date +%s%N 2>/dev/null || echo "")
  sl_profile() {
    local now
    now=$(date +%s%N 2>/dev/null || echo "")
    case "$now" in ''|*[!0-9]*) return 0 ;; esac
    case "$SL_PROF_LAST" in ''|*[!0-9]*) SL_PROF_LAST=$now; return 0 ;; esac
    printf 'profile: %-22s %5d ms\n' "$1" $(( (now - SL_PROF_LAST) / 1000000 )) >&2
    SL_PROF_LAST=$now
  }
else
  sl_profile() { :; }
fi

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

# Parse an ISO 8601 timestamp (or pass through a raw epoch) to epoch
# seconds in REPLY. Raw epochs short-circuit with zero forks — that is the
# stdin rate-limits path, the common case since Claude Code 2.1.
# Usage: iso_to_epoch "2026-03-10T13:59:59.654957+00:00"; epoch=$REPLY
iso_to_epoch() {
  local ts="$1"
  REPLY=""
  case "$ts" in
    '') return 1 ;;
    *[!0-9]*) ;;          # not a plain epoch — fall through to date parsing
    *) REPLY="$ts"; return 0 ;;
  esac
  # Strip fractional seconds and timezone offset
  local clean="${ts%%.*}"
  clean="${clean%%+*}"
  if [[ "${OSTYPE:-}" == darwin* ]]; then
    REPLY=$(date -juf "%Y-%m-%dT%H:%M:%S" "$clean" +%s 2>/dev/null) || { REPLY=""; return 1; }
  else
    # GNU date (Linux & MSYS2/Windows)
    REPLY=$(date -ud "${clean}" +%s 2>/dev/null) || { REPLY=""; return 1; }
  fi
  [ -n "$REPLY" ]
}

# ── CLI Flags ─────────────────────────────────────────────────
# Note: --dump-config and --uninstall are handled later, AFTER defaults
# and ~/.claude/statusline.conf have been loaded. The flags below exit
# early because they don't depend on resolved config values.
case "${1:-}" in
  --help|-h)
    echo "Usage: echo '<json>' | bash statusline-command.sh [FLAG]"
    echo ""
    echo "Reads Claude Code statusline JSON from stdin and outputs"
    echo "a formatted status bar for your terminal."
    echo ""
    echo "Flags:"
    echo "  --help           Show this help"
    echo "                     bash statusline-command.sh --help"
    echo "  --version        Print version and exit"
    echo "                     bash statusline-command.sh --version"
    echo "  --check-update   Force a synchronous update check"
    echo "                     bash statusline-command.sh --check-update"
    echo "  --dump-stdin     Pretty-print the raw JSON Claude Code sends (diagnostic)"
    echo "                     echo '<json>' | bash statusline-command.sh --dump-stdin"
    echo "  --dump-config    Print resolved config (defaults + statusline.conf)"
    echo "                     bash statusline-command.sh --dump-config"
    echo "  --uninstall      Interactively remove installed files (prompts before deleting)"
    echo "                     bash statusline-command.sh --uninstall"
    echo "  --benchmark [N]  Time N end-to-end runs (default 5) against a canned payload"
    echo "                     bash statusline-command.sh --benchmark"
    echo "                     STATUSLINE_PROFILE=1 adds a per-phase breakdown to any run"
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

# Skip the background update check for diagnostic / management flags
# (they would race with cache deletion or pollute --dump-config output).
case "${1:-}" in
  --dump-config|--uninstall|--benchmark) ;;
  *) check_for_update ;;
esac

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
usage_label="clock"
show_pr=true
pr_link=true
usage_cache_seconds=600
auto_hide=true
use_icons=true
context_warn_threshold=auto
enable_truncation=false
max_width=""
use_groups=false
group_open="["
group_close="]"
colour_theme="default"
show_vim_mode=true
show_agent=true
show_tokens=false
show_effort=true
show_fast_mode=true
bar_width=10
branch_max_length=""
show_activity=true
activity_ttl_seconds=120
activity_colour=true
activity_fresh_seconds=45
activity_pulse=false
activity_scanner=false
# Consumed by statusline-subagent.js (the subagent panel renderer); declared
# here so it appears in --dump-config alongside everything else
subagent_rows=true

# Load user overrides (if any).
# Note: this file has the same trust level as .bashrc — it can contain
# arbitrary bash code. Only modify it yourself or via trusted tools.
STATUSLINE_CONF="${SCRIPT_DIR}/statusline.conf"
# shellcheck disable=SC1090
[ -f "$STATUSLINE_CONF" ] && . "$STATUSLINE_CONF"

# Backwards compatibility: accept old name
[ "${show_usage_weekly:-}" = "true" ] && show_usage_7d=true
[ "${show_usage_weekly:-}" = "false" ] && show_usage_7d=false

# ── Post-config CLI Flags ─────────────────────────────────────
# These flags need the resolved config (defaults + statusline.conf),
# but must run BEFORE we read stdin, fetch caches, or hit the network.
case "${1:-}" in
  --dump-config)
    # Print resolved config as alphabetically-sorted key=value pairs.
    # Reflects defaults overridden by ~/.claude/statusline.conf.
    {
      printf 'auto_hide=%s\n'              "${auto_hide}"
      printf 'bar_width=%s\n'              "${bar_width}"
      printf 'branch_max_length=%s\n'      "${branch_max_length}"
      printf 'colour_theme=%s\n'           "${colour_theme}"
      printf 'context_warn_threshold=%s\n' "${context_warn_threshold}"
      printf 'enable_truncation=%s\n'      "${enable_truncation}"
      printf 'group_close=%s\n'            "${group_close}"
      printf 'group_open=%s\n'             "${group_open}"
      printf 'max_width=%s\n'              "${max_width}"
      printf 'activity_colour=%s\n'        "${activity_colour}"
      printf 'activity_fresh_seconds=%s\n' "${activity_fresh_seconds}"
      printf 'activity_pulse=%s\n'         "${activity_pulse}"
      printf 'activity_scanner=%s\n'       "${activity_scanner}"
      printf 'activity_ttl_seconds=%s\n'   "${activity_ttl_seconds}"
      printf 'show_activity=%s\n'          "${show_activity}"
      printf 'show_agent=%s\n'             "${show_agent}"
      printf 'show_ahead_behind=%s\n'      "${show_ahead_behind}"
      printf 'show_branch=%s\n'            "${show_branch}"
      printf 'show_context_bar=%s\n'       "${show_context_bar}"
      printf 'show_cost=%s\n'              "${show_cost}"
      printf 'show_cost_rate=%s\n'         "${show_cost_rate}"
      printf 'show_directory=%s\n'         "${show_directory}"
      printf 'show_dirty_count=%s\n'       "${show_dirty_count}"
      printf 'show_duration=%s\n'          "${show_duration}"
      printf 'show_effort=%s\n'            "${show_effort}"
      printf 'show_fast_mode=%s\n'         "${show_fast_mode}"
      printf 'show_lines_changed=%s\n'     "${show_lines_changed}"
      printf 'show_model=%s\n'             "${show_model}"
      printf 'pr_link=%s\n'                "${pr_link}"
      printf 'show_pr=%s\n'                "${show_pr}"
      printf 'show_stash=%s\n'             "${show_stash}"
      printf 'show_tokens=%s\n'            "${show_tokens}"
      printf 'show_usage_5h=%s\n'          "${show_usage_5h}"
      printf 'show_usage_7d=%s\n'          "${show_usage_7d}"
      printf 'show_vim_mode=%s\n'          "${show_vim_mode}"
      printf 'show_worktree=%s\n'          "${show_worktree}"
      printf 'subagent_rows=%s\n'          "${subagent_rows}"
      printf 'usage_cache_seconds=%s\n'    "${usage_cache_seconds}"
      printf 'usage_label=%s\n'            "${usage_label}"
      printf 'use_groups=%s\n'             "${use_groups}"
      printf 'use_icons=%s\n'              "${use_icons}"
    } | LC_ALL=C sort
    exit 0
    ;;
  --uninstall)
    # Interactive removal of all files installed under ~/.claude/.
    # Mirrors the README "Uninstall" file list. statusline.conf is
    # handled separately so the user can keep their config.
    UNINSTALL_FILES=(
      "${SCRIPT_DIR}/statusline-command.sh"
      "${SCRIPT_DIR}/statusline-helper.js"
      "${SCRIPT_DIR}/statusline-subagent.js"
      "${SCRIPT_DIR}/.statusline-version"
      "${SCRIPT_DIR}/.statusline-update-cache"
      "${SCRIPT_DIR}/.statusline-usage-cache"
      "${SCRIPT_DIR}/.statusline-usage-backoff"
      "${SCRIPT_DIR}/.statusline-activity-cache"
    )
    UNINSTALL_DIRS=(
      "${SCRIPT_DIR}/.statusline-transcript-cache"
    )
    echo "This will remove the following files:"
    for f in "${UNINSTALL_FILES[@]}"; do
      echo "  $f"
    done
    for d in "${UNINSTALL_DIRS[@]}"; do
      echo "  $d/ (directory)"
    done
    echo ""
    echo "Your config file (${SCRIPT_DIR}/statusline.conf) will be kept"
    echo "unless you confirm its removal in a follow-up prompt."
    echo ""
    response=""
    read -r -p "Continue? [y/N] " response || response=""
    case "$response" in
      y|Y)
        for f in "${UNINSTALL_FILES[@]}"; do
          rm -f "$f"
        done
        # Per-session activity caches (.statusline-activity-cache.<id>)
        rm -f "${SCRIPT_DIR}"/.statusline-activity-cache.* 2>/dev/null || true
        for d in "${UNINSTALL_DIRS[@]}"; do
          rm -rf "$d"
        done
        echo "Removed installed files."
        conf_response=""
        if [ -f "${SCRIPT_DIR}/statusline.conf" ]; then
          read -r -p "Also remove ${SCRIPT_DIR}/statusline.conf? [y/N] " conf_response || conf_response=""
          case "$conf_response" in
            y|Y)
              rm -f "${SCRIPT_DIR}/statusline.conf"
              echo "Removed ${SCRIPT_DIR}/statusline.conf."
              ;;
            *)
              echo "Kept ${SCRIPT_DIR}/statusline.conf."
              ;;
          esac
        fi
        echo ""
        echo "Now remove the \"statusLine\" block from ~/.claude/settings.json manually."
        exit 0
        ;;
      *)
        echo "Cancelled."
        exit 1
        ;;
    esac
    ;;
  --benchmark)
    # Time N end-to-end runs (default 5) against a realistic canned payload:
    # current directory as cwd (so git work is included when run in a repo),
    # stdin rate limits, and a tiny transcript so the activity path executes.
    # Usage: statusline-command.sh --benchmark [runs]
    # Set STATUSLINE_PROFILE=1 for a per-phase breakdown of a single run.
    bench_runs="${2:-5}"
    case "$bench_runs" in ''|*[!0-9]*|0) bench_runs=5 ;; esac
    bench_t0=$(date +%s%N 2>/dev/null) || bench_t0=""
    case "$bench_t0" in
      ''|*[!0-9]*)
        echo "--benchmark needs GNU date with %N (millisecond) support." >&2
        exit 1
        ;;
    esac
    # Fixed path (not $$) so repeat benchmarks reuse one transcript-cache entry
    bench_tr="${TMPDIR:-/tmp}/.statusline-bench.jsonl"
    printf '%s\n' '{"timestamp":"2026-01-01T00:00:00Z","message":{"content":[{"type":"tool_use","id":"b1","name":"Read","input":{"file_path":"/tmp/bench.ts"}}]}}' > "$bench_tr"
    bench_json="{\"cwd\":\"$PWD\",\"session_id\":\"benchmark00\",\"transcript_path\":\"$bench_tr\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":42,\"context_window_size\":200000,\"total_input_tokens\":84000},\"total_cost_usd\":1.23,\"rate_limits\":{\"five_hour\":{\"used_percentage\":42,\"resets_at\":$(( NOW_EPOCH + 7200 ))},\"seven_day\":{\"used_percentage\":71,\"resets_at\":$(( NOW_EPOCH + 86400 ))}}}"
    echo "Benchmarking ${bench_runs} runs (cwd: $PWD)..."
    bench_i=0 bench_total=0 bench_min="" bench_max=""
    while [ "$bench_i" -lt "$bench_runs" ]; do
      bench_t0=$(date +%s%N)
      printf '%s' "$bench_json" | bash "$0" > /dev/null 2>&1 || true
      bench_t1=$(date +%s%N)
      bench_ms=$(( (bench_t1 - bench_t0) / 1000000 ))
      echo "  run $(( bench_i + 1 )): ${bench_ms} ms"
      bench_total=$(( bench_total + bench_ms ))
      if [ -z "$bench_min" ] || [ "$bench_ms" -lt "$bench_min" ]; then bench_min=$bench_ms; fi
      if [ -z "$bench_max" ] || [ "$bench_ms" -gt "$bench_max" ]; then bench_max=$bench_ms; fi
      bench_i=$(( bench_i + 1 ))
    done
    echo "min ${bench_min} ms · avg $(( bench_total / bench_runs )) ms · max ${bench_max} ms"
    rm -f "$bench_tr" "${SCRIPT_DIR}/.statusline-activity-cache.benchmar" 2>/dev/null
    exit 0
    ;;
esac

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
      CLR_MODEL_FABLE="\033[38;5;139m" # aurora purple (Fable tier)
      CLR_ADD="\033[38;5;108m"     # aurora green
      CLR_DEL="\033[38;5;174m"     # aurora red
      CLR_WARN="\033[38;5;179m"    # aurora yellow
      CLR_INFO="\033[38;5;110m"    # frost cyan
      CLR_DIM="\033[38;5;60m"     # polar night dim
      CLR_BAR_OK="\033[38;5;108m"  # aurora green
      CLR_BAR_MED="\033[38;5;179m" # aurora yellow
      CLR_BAR_HIGH="\033[38;5;174m" # aurora red
      CLR_PACE="\033[38;5;199m"    # hot pink pacing marker
      CLR_RAMP0="\033[38;5;108m" CLR_RAMP1="\033[38;5;151m" # todo-bar gradient
      CLR_RAMP2="\033[38;5;179m" CLR_RAMP3="\033[38;5;174m" # green->red, aurora
      CLR_RESET="\033[0m"
      ;;
    dracula)
      CLR_DIR="\033[38;5;141m"     # purple
      CLR_BRANCH="\033[38;5;212m"  # pink
      CLR_MODEL="\033[38;5;117m"   # cyan
      CLR_MODEL_OPUS="\033[38;5;215m" # orange #ffb86c (Opus tier)
      CLR_MODEL_FABLE="\033[38;5;141m" # purple #bd93f9 (Fable tier)
      CLR_ADD="\033[38;5;84m"      # green
      CLR_DEL="\033[38;5;210m"     # red
      CLR_WARN="\033[38;5;228m"    # yellow
      CLR_INFO="\033[38;5;117m"    # cyan
      CLR_DIM="\033[38;5;61m"     # comment grey
      CLR_BAR_OK="\033[38;5;84m"   # green
      CLR_BAR_MED="\033[38;5;228m" # yellow
      CLR_BAR_HIGH="\033[38;5;210m" # red
      CLR_PACE="\033[38;5;212m"    # pink pacing marker
      CLR_RAMP0="\033[38;5;84m"  CLR_RAMP1="\033[38;5;120m" # todo-bar gradient
      CLR_RAMP2="\033[38;5;228m" CLR_RAMP3="\033[38;5;210m" # green->pink-red
      CLR_RESET="\033[0m"
      ;;
    solarized)
      CLR_DIR="\033[38;5;37m"     # cyan
      CLR_BRANCH="\033[38;5;61m"  # violet
      CLR_MODEL="\033[38;5;33m"   # blue
      CLR_MODEL_OPUS="\033[38;5;166m" # solarized orange (Opus tier)
      CLR_MODEL_FABLE="\033[38;5;61m" # solarized violet (Fable tier)
      CLR_ADD="\033[38;5;64m"     # green
      CLR_DEL="\033[38;5;160m"    # red
      CLR_WARN="\033[38;5;136m"   # yellow
      CLR_INFO="\033[38;5;37m"    # cyan
      CLR_DIM="\033[38;5;240m"   # base01 dim
      CLR_BAR_OK="\033[38;5;64m"  # green
      CLR_BAR_MED="\033[38;5;136m" # yellow
      CLR_BAR_HIGH="\033[38;5;160m" # red
      CLR_PACE="\033[38;5;125m"    # magenta pacing marker
      CLR_RAMP0="\033[38;5;64m"  CLR_RAMP1="\033[38;5;106m" # todo-bar gradient
      CLR_RAMP2="\033[38;5;136m" CLR_RAMP3="\033[38;5;166m" # green->orange
      CLR_RESET="\033[0m"
      ;;
    tokyo-night)
      CLR_DIR="\033[38;5;111m"    # blue #7aa2f7
      CLR_BRANCH="\033[38;5;141m" # purple #bb9af7
      CLR_MODEL="\033[38;5;117m"  # cyan #7dcfff
      CLR_MODEL_OPUS="\033[38;5;215m" # orange #ff9e64 (Opus tier)
      CLR_MODEL_FABLE="\033[38;5;141m" # purple #bb9af7 (Fable tier)
      CLR_ADD="\033[38;5;149m"    # green #9ece6a
      CLR_DEL="\033[38;5;204m"    # red #f7768e
      CLR_WARN="\033[38;5;179m"   # yellow #e0af68
      CLR_INFO="\033[38;5;117m"   # cyan #7dcfff
      CLR_DIM="\033[38;5;59m"    # comment #565f89
      CLR_BAR_OK="\033[38;5;149m" # green #9ece6a
      CLR_BAR_MED="\033[38;5;179m" # yellow #e0af68
      CLR_BAR_HIGH="\033[38;5;204m" # red #f7768e
      CLR_PACE="\033[38;5;198m"   # pink #ff007c
      CLR_RAMP0="\033[38;5;149m" CLR_RAMP1="\033[38;5;186m" # todo-bar gradient
      CLR_RAMP2="\033[38;5;179m" CLR_RAMP3="\033[38;5;204m" # green->red
      CLR_RESET="\033[0m"
      ;;
    catppuccin)
      CLR_DIR="\033[38;5;111m"    # blue #89b4fa
      CLR_BRANCH="\033[38;5;183m" # mauve #cba6f7
      CLR_MODEL="\033[38;5;116m"  # sapphire #74c7ec
      CLR_MODEL_OPUS="\033[38;5;216m" # peach #fab387 (Opus tier)
      CLR_MODEL_FABLE="\033[38;5;183m" # mauve #cba6f7 (Fable tier)
      CLR_ADD="\033[38;5;150m"    # green #a6e3a1
      CLR_DEL="\033[38;5;211m"    # red #f38ba8
      CLR_WARN="\033[38;5;223m"   # yellow #f9e2af
      CLR_INFO="\033[38;5;116m"   # sapphire #74c7ec
      CLR_DIM="\033[38;5;243m"   # overlay0 #6c7086
      CLR_BAR_OK="\033[38;5;150m" # green #a6e3a1
      CLR_BAR_MED="\033[38;5;223m" # yellow #f9e2af
      CLR_BAR_HIGH="\033[38;5;211m" # red #f38ba8
      CLR_PACE="\033[38;5;218m"   # pink #f5c2e7
      CLR_RAMP0="\033[38;5;150m" CLR_RAMP1="\033[38;5;151m" # todo-bar gradient
      CLR_RAMP2="\033[38;5;223m" CLR_RAMP3="\033[38;5;216m" # green->peach
      CLR_RESET="\033[0m"
      ;;
    mono)
      CLR_DIR="" CLR_BRANCH="" CLR_MODEL="" CLR_MODEL_OPUS="" CLR_MODEL_FABLE=""
      CLR_ADD="" CLR_DEL="" CLR_WARN="" CLR_INFO="" CLR_DIM=""
      CLR_BAR_OK="" CLR_BAR_MED="" CLR_BAR_HIGH="" CLR_PACE=""
      CLR_RAMP0="" CLR_RAMP1="" CLR_RAMP2="" CLR_RAMP3=""
      CLR_RESET=""
      ;;
    *) # default — original colours
      CLR_DIR="\033[0;36m"     # cyan
      CLR_BRANCH="\033[0;35m"  # magenta
      CLR_MODEL="\033[0;34m"   # blue
      CLR_MODEL_OPUS="\033[38;5;208m" # orange (Opus tier)
      CLR_MODEL_FABLE="\033[38;5;141m" # purple (Fable tier)
      CLR_ADD="\033[0;32m"     # green
      CLR_DEL="\033[0;31m"     # red
      CLR_WARN="\033[0;33m"    # yellow
      CLR_INFO="\033[0;36m"    # cyan
      CLR_DIM="\033[0;90m"    # dark grey
      CLR_BAR_OK="\033[0;32m"  # green
      CLR_BAR_MED="\033[0;33m" # yellow
      CLR_BAR_HIGH="\033[0;31m" # red
      CLR_PACE="\033[38;5;199m"  # hot pink pacing marker
      CLR_RAMP0="\033[38;5;46m"  CLR_RAMP1="\033[38;5;112m" # todo-bar gradient
      CLR_RAMP2="\033[38;5;178m" CLR_RAMP3="\033[38;5;208m" # green->orange
      CLR_RESET="\033[0m"
      ;;
  esac
}

apply_theme

# ── End Configuration ─────────────────────────────────────────

input=$(cat)
sl_profile "startup+config"

# ── JSON Parsing Helpers ──────────────────────────────────────
# These extract values from the JSON input using bash regex since
# jq is not available in MSYS2/Git Bash on Windows by default.
# All four variants share common regex logic. The _from variants
# accept an explicit JSON string; the plain variants use $input.
# Results return via the REPLY global: $(fn) command substitutions
# fork a subshell (15-25ms each under MSYS), and these run ~40x/render.

# Extract a string value by key from a JSON string
# Usage: extract_from "$json" "key"; value=$REPLY
extract_from() {
  local json="$1" key="$2"
  local pattern="\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  REPLY=""
  if [[ $json =~ $pattern ]]; then
    REPLY="${BASH_REMATCH[1]}"
  fi
}

# Extract a numeric value by key from a JSON string
# Usage: extract_num_from "$json" "key"; value=$REPLY
extract_num_from() {
  local json="$1" key="$2"
  local pattern="\"$key\"[[:space:]]*:[[:space:]]*([0-9]+\.?[0-9]*)"
  REPLY=""
  if [[ $json =~ $pattern ]]; then
    REPLY="${BASH_REMATCH[1]}"
  fi
}

# Extract a JSON object block by key, returning content between { }
# Handles one level of nested braces (e.g., inner objects within the block).
# Usage: extract_block "$json" "key"; value=$REPLY
extract_block() {
  local json="$1" key="$2"
  local pattern="\"$key\"[[:space:]]*:[[:space:]]*\{(([^{}]|\{[^}]*\})+)\}"
  REPLY=""
  if [[ $json =~ $pattern ]]; then
    REPLY="${BASH_REMATCH[1]}"
  fi
}

# Convenience wrappers that operate on the global $input
extract()     { extract_from "$input" "$1"; }
extract_num() { extract_num_from "$input" "$1"; }

# Real ESC/BEL bytes for patterns: BSD sed (stock macOS) does not interpret
# \x1b hex escapes, so the bytes are interpolated from bash instead.
ESC_CH=$'\x1b'
BEL_CH=$'\x07'

# Strip ANSI escape sequences and control characters from untrusted strings.
# Handles CSI (ESC[...), OSC terminated by BEL or ST (ESC\), and DCS/APC.
# Pure bash, result in REPLY: the old sed|tr pipeline cost ~4 forks per call
# and this runs up to 8 times per render.
sanitize() {
  local val="$1" pat
  # CSI sequences (ESC [ ... letter)
  pat="${ESC_CH}\[[0-9;]*[a-zA-Z]"
  while [[ $val =~ $pat ]]; do val="${val//"${BASH_REMATCH[0]}"/}"; done
  # OSC terminated by BEL (ESC ] ... BEL)
  pat="${ESC_CH}\][^${BEL_CH}]*${BEL_CH}"
  while [[ $val =~ $pat ]]; do val="${val//"${BASH_REMATCH[0]}"/}"; done
  # OSC terminated by ST (ESC ] ... ESC \)
  pat="${ESC_CH}\][^${ESC_CH}]*${ESC_CH}\\\\"
  while [[ $val =~ $pat ]]; do val="${val//"${BASH_REMATCH[0]}"/}"; done
  # DCS/SOS/PM/APC (ESC P/X/_/^ ... ESC \)
  pat="${ESC_CH}[PX_^][^${ESC_CH}]*${ESC_CH}\\\\"
  while [[ $val =~ $pat ]]; do val="${val//"${BASH_REMATCH[0]}"/}"; done
  # Remaining control characters (C0 + DEL), including stray ESC bytes
  val="${val//[[:cntrl:]]/}"
  REPLY="$val"
}

# Visible width of a segment for truncation (in REPLY). Segments carry
# theme colours as literal \033[..m text — and the PR segment may carry a
# literal OSC 8 hyperlink wrapper — so strip those patterns (plus any raw
# ESC SGR, defensively) in pure bash. The old printf|sed pipeline cost 3
# forks per segment.
visible_width() {
  local s="$1" pat='\\033\]8;[^\\]*\\033\\\\'
  while [[ $s =~ $pat ]]; do s="${s//"${BASH_REMATCH[0]}"/}"; done
  pat='\\033\[[0-9;]*[a-zA-Z]'
  while [[ $s =~ $pat ]]; do s="${s//"${BASH_REMATCH[0]}"/}"; done
  pat="${ESC_CH}\[[0-9;]*[a-zA-Z]"
  while [[ $s =~ $pat ]]; do s="${s//"${BASH_REMATCH[0]}"/}"; done
  REPLY=${#s}
}

# ── Extract Fields ────────────────────────────────────────────

# Working directory: prefer workspace.current_dir, fall back to top-level cwd
cwd=""
extract_block "$input" "workspace"; ws_block=$REPLY
if [ -n "$ws_block" ]; then extract_from "$ws_block" "current_dir"; cwd=$REPLY; fi
if [ -z "$cwd" ]; then extract "cwd"; cwd=$REPLY; fi

# Sanitize cwd before using it in git commands (defends against directory traversal)
sanitize "$cwd"; cwd=$REPLY

# Session ID: keys the activity cache so parallel sessions never clobber
# each other's line 2 (Claude Code sends a stable per-session UUID)
extract "session_id"; session_id=$REPLY
session_id="${session_id//[^a-zA-Z0-9-]/}"

# Model display name: prefer model.display_name (new schema), fall back to top-level
model=""
extract_block "$input" "model"; model_block=$REPLY
if [ -n "$model_block" ]; then extract_from "$model_block" "display_name"; model=$REPLY; fi
if [ -z "$model" ]; then extract "display_name"; model=$REPLY; fi

# Context window usage: prefer context_window.used_percentage (new schema), fall back.
# The fallback only runs when rate_limits is absent (old flat schema) to avoid
# matching rate_limits.five_hour.used_percentage by accident.
used=""
extract_block "$input" "context_window"; cw_block=$REPLY
if [ -n "$cw_block" ]; then extract_num_from "$cw_block" "used_percentage"; used=$REPLY; fi
if [ -z "$used" ]; then
  rl_check='"rate_limits"[[:space:]]*:'
  if [[ ! $input =~ $rl_check ]]; then extract_num "used_percentage"; used=$REPLY; fi
fi

# Context window total size in tokens
context_size=""
if [ -n "$cw_block" ]; then extract_num_from "$cw_block" "context_window_size"; context_size=$REPLY; fi
if [ -z "$context_size" ]; then extract_num "context_window_size"; context_size=$REPLY; fi

# Transcript path (for live activity — new in CC 2.1+)
extract "transcript_path"; transcript_path=$REPLY

# Cumulative session cost in USD
extract_num "total_cost_usd"; total_cost=$REPLY

# Lines changed during this session
extract_num "total_lines_added"; lines_added=$REPLY
extract_num "total_lines_removed"; lines_removed=$REPLY

# Session duration in milliseconds
extract_num "total_duration_ms"; duration_ms=$REPLY

# Worktree name — extract from worktree block to avoid collision with agent.name
worktree=""
extract_block "$input" "worktree"; wt_block=$REPLY
if [ -n "$wt_block" ]; then
  extract_from "$wt_block" "name"
  sanitize "$REPLY"; worktree=$REPLY
fi
# Fallback: workspace.git_worktree covers ANY linked git worktree (CC 2.1.145+),
# not just --worktree sessions
if [ -z "$worktree" ] && [ -n "$ws_block" ]; then
  extract_from "$ws_block" "git_worktree"
  sanitize "$REPLY"; worktree=$REPLY
fi

# ── Working Directory ─────────────────────────────────────────
# Replace home directory prefix with ~ for a shorter display
home_dir="$HOME"
short_cwd="${cwd/#$home_dir/\~}"
sanitize "$short_cwd"; short_cwd=$REPLY

sl_profile "stdin+fields"
# ── Git Info ──────────────────────────────────────────────────
# Detect branch, dirty count, ahead/behind, and stash count.
# Uses -c core.fsmonitor=false to skip filesystem monitoring overhead.
# Guard: cwd must be a real directory to avoid traversal via crafted JSON.
branch=""
dirty_count=""
ahead_count=""
behind_count=""
stash_count=""
# Repo gate doubles as git-dir discovery: --git-dir for the gate itself,
# --git-common-dir for the stash log (linked worktrees share the stash in
# the common dir). One fork for both.
git_dirs=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  git_dirs=$(git -C "$cwd" --no-optional-locks -c core.fsmonitor=false rev-parse --git-dir --git-common-dir 2>/dev/null) || git_dirs=""
fi
if [ -n "$git_dirs" ]; then
  git_common="${git_dirs##*$'\n'}"

  # One `status --porcelain=v2 --branch` call provides the branch name,
  # ahead/behind, and the dirty count — replacing three git forks plus
  # their wc/tr/cut pipelines. Header lines are parsed in pure bash; the
  # entry count comes from line arithmetic so huge dirty trees stay cheap.
  if [ "$show_branch" = "true" ] || [ "$show_dirty_count" = "true" ] || [ "$show_ahead_behind" = "true" ]; then
    git_status=$(git -C "$cwd" --no-optional-locks -c core.fsmonitor=false status --porcelain=v2 --branch 2>/dev/null) || git_status=""
    git_oid="" git_head="" git_headers=0 git_rest="$git_status"
    while [ -n "$git_rest" ]; do
      git_line="${git_rest%%$'\n'*}"
      case "$git_line" in
        "# branch.oid "*)  git_oid="${git_line#"# branch.oid "}" ;;
        "# branch.head "*) git_head="${git_line#"# branch.head "}" ;;
        "# branch.ab "*)
          if [ "$show_ahead_behind" = "true" ]; then
            git_ab="${git_line#"# branch.ab "}"        # "+A -B"
            ahead_count="${git_ab%% *}"; ahead_count="${ahead_count#+}"
            behind_count="${git_ab##* }"; behind_count="${behind_count#-}"
          fi
          ;;
        "#"*) ;;
        *) break ;;
      esac
      git_headers=$(( git_headers + 1 ))
      case "$git_rest" in
        *$'\n'*) git_rest="${git_rest#*$'\n'}" ;;
        *) git_rest="" ;;
      esac
    done
    if [ "$show_dirty_count" = "true" ] && [ -n "$git_status" ]; then
      git_nl="${git_status//[!$'\n']/}"
      dirty_count=$(( ${#git_nl} + 1 - git_headers ))
      [ "$dirty_count" -lt 0 ] && dirty_count=0
    fi
    if [ "$show_branch" = "true" ]; then
      if [ "$git_head" = "(detached)" ]; then
        branch="${git_oid:0:7}"
      else
        branch="$git_head"
      fi
      sanitize "$branch"; branch=$REPLY
      if [ -n "$branch_max_length" ] && [ "${#branch}" -gt "$branch_max_length" ] 2>/dev/null; then
        branch="${branch:0:$branch_max_length}…"
      fi
    fi
  fi

  # Stash count: the reflog at logs/refs/stash holds one line per stash,
  # so a pure-bash line count replaces `git stash list | wc -l`.
  if [ "$show_stash" = "true" ]; then
    stash_count=0
    case "$git_common" in
      /*|[A-Za-z]:*) stash_log="$git_common/logs/refs/stash" ;;
      *)             stash_log="$cwd/$git_common/logs/refs/stash" ;;
    esac
    if [ -f "$stash_log" ]; then
      while IFS= read -r stash_line || [ -n "$stash_line" ]; do
        stash_count=$(( stash_count + 1 ))
      done < "$stash_log"
    fi
  fi
fi

sl_profile "git"
# ── Live Activity (transcript parsing via Node.js helper) ────
# Reads Claude Code's JSONL transcript for tool/agent/todo activity.
# Runs in background; uses cached result from previous invocation.
ACTIVITY_CACHE_FILE="${SCRIPT_DIR}/.statusline-activity-cache"
# Key the cache by session so parallel sessions each get their own line 2
[ -n "$session_id" ] && ACTIVITY_CACHE_FILE="${SCRIPT_DIR}/.statusline-activity-cache.${session_id:0:8}"
HELPER_SCRIPT="${SCRIPT_DIR}/statusline-helper.js"
activity_line=""
activity_has_colour=false

# Map the helper's zero-width colour tokens to theme colours. Tokens are
# plain text, so they survive both sanitize layers; only fixed CLR_*
# constants are ever substituted in, never input. {d} re-asserts the
# line-wide dim instead of resetting, mirroring build_progress_bar. While
# the cache is older than activity_fresh_seconds the colours are dropped,
# so stale data reads as stale (the old all-dim look). {s} is a spinner
# slot: the frame comes from the clock, so it animates at whatever rate
# Claude Code re-runs the script (e.g. refreshInterval=1).
apply_activity_tokens() {
  case "$activity_line" in *"{"*"}"*) ;; *) return 0 ;; esac
  local stale=false spin="▶" flash="" t
  case "$activity_fresh_seconds" in ''|*[!0-9]*) activity_fresh_seconds=45 ;; esac
  [ $(( NOW_EPOCH - cached_act_ts )) -gt "$activity_fresh_seconds" ] && stale=true
  if [ "$activity_colour" = "true" ] && [ "$stale" = "false" ]; then
    case $(( NOW_EPOCH % 4 )) in
      0) spin="⠋" ;; 1) spin="⠙" ;; 2) spin="⠸" ;; *) spin="⠴" ;;
    esac
    # Substitute RAW escape bytes (not literal \033 text): line 2 is printed
    # with %s, so printf %b never runs over transcript-derived content and
    # cannot be tricked into decoding \n, \u, ... smuggled into the cache.
    # ${CLR_X//\\033/$ESC_CH} converts the theme constants without a fork.
    local W="${CLR_WARN//\\033/$ESC_CH}" A="${CLR_ADD//\\033/$ESC_CH}"
    local E="${CLR_DEL//\\033/$ESC_CH}" I="${CLR_INFO//\\033/$ESC_CH}"
    local DM="${CLR_DIM//\\033/$ESC_CH}"
    local H1="${CLR_BAR_OK//\\033/$ESC_CH}" H2="${CLR_BAR_MED//\\033/$ESC_CH}"
    local H3="${CLR_BAR_HIGH//\\033/$ESC_CH}"
    local R0="${CLR_RAMP0//\\033/$ESC_CH}" R1="${CLR_RAMP1//\\033/$ESC_CH}"
    local R2="${CLR_RAMP2//\\033/$ESC_CH}" R3="${CLR_RAMP3//\\033/$ESC_CH}"
    local need_22=false pulse_pfx="" scanner_due=false
    # Opt-in pulse: the running label breathes by alternating bold/faint on
    # epoch parity, one step per re-render (WCAG-safe at any refresh rate)
    if [ "${activity_pulse:-false}" = "true" ] && [ -n "$W" ]; then
      if [ $(( NOW_EPOCH % 2 )) -eq 0 ]; then pulse_pfx="${ESC_CH}[1m"; else pulse_pfx="${ESC_CH}[2m"; fi
      need_22=true
    fi
    # Opt-in scanner: queue a KITT bar while something has been running long
    # enough to earn a heat tier (the helper emits {h2}/{h3} past 30s)
    if [ "${activity_scanner:-false}" = "true" ]; then
      case "$activity_line" in *"{h2}"*|*"{h3}"*) scanner_due=true ;; esac
    fi
    if [ -n "$A" ]; then
      flash="${ESC_CH}[1m${A}"
      # Bold/faint on the line: make {d} also clear intensity (SGR 22), else
      # the {O} flash or pulse bleeds into the rest of line 2
      case "$activity_line" in *"{O}"*) need_22=true ;; esac
    fi
    [ "$need_22" = "true" ] && DM="${ESC_CH}[22m${DM}"
    activity_line="${activity_line//'{s}'/${W}${spin}${DM}}"
    activity_line="${activity_line//'{w}'/${pulse_pfx}$W}"
    activity_line="${activity_line//'{o}'/$A}"
    activity_line="${activity_line//'{e}'/$E}"
    activity_line="${activity_line//'{i}'/$I}"
    activity_line="${activity_line//'{O}'/$flash}"
    activity_line="${activity_line//'{h1}'/$H1}"
    activity_line="${activity_line//'{h2}'/$H2}"
    activity_line="${activity_line//'{h3}'/$H3}"
    activity_line="${activity_line//'{r0}'/$R0}"
    activity_line="${activity_line//'{r1}'/$R1}"
    activity_line="${activity_line//'{r2}'/$R2}"
    activity_line="${activity_line//'{r3}'/$R3}"
    activity_line="${activity_line//'{d}'/$DM}"
    # Scanner: an 8-cell track with a theme-accent cell sweeping left-right-
    # left, one step per re-render. Appended last so the width trim drops it
    # first on narrow terminals.
    if [ "$scanner_due" = "true" ]; then
      local P="${CLR_PACE//\\033/$ESC_CH}"
      local scan_pos=$(( NOW_EPOCH % 14 )) scan_i=0 scan_track=""
      [ "$scan_pos" -gt 7 ] && scan_pos=$(( 14 - scan_pos ))
      while [ "$scan_i" -lt 8 ]; do
        if [ "$scan_i" -eq "$scan_pos" ]; then
          scan_track+="${P}█${DM}"
        else
          scan_track+="─"
        fi
        scan_i=$(( scan_i + 1 ))
      done
      activity_line="${activity_line}  │  ${scan_track}"
    fi
    activity_has_colour=true
  else
    # Colour disabled or data stale: strip tokens for the plain dim look
    activity_line="${activity_line//'{s}'/▶}"
    for t in w o e i O h1 h2 h3 r0 r1 r2 r3 d; do
      activity_line="${activity_line//"{$t}"/}"
    done
  fi
}

if [ "$show_activity" = "true" ] && [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  if command -v node > /dev/null 2>&1 && [ -f "$HELPER_SCRIPT" ]; then
    # Spawn helper in background (non-blocking); the same subshell sweeps
    # per-session caches older than a day so they never accumulate
    # The stale-cache sweep runs on ~1 in 37 refreshes: it only needs to
    # happen occasionally, and skipping the find fork the rest of the time
    # keeps the helper subshell cheap
    ( if [ $(( NOW_EPOCH % 37 )) -eq 0 ]; then
        find "$SCRIPT_DIR" -maxdepth 1 -name '.statusline-activity-cache.*' -mmin +1440 -delete 2>/dev/null
      fi
      if [ "$activity_colour" = "true" ]; then
        node "$HELPER_SCRIPT" "$transcript_path" "$ACTIVITY_CACHE_FILE" --colour 2>/dev/null
      else
        node "$HELPER_SCRIPT" "$transcript_path" "$ACTIVITY_CACHE_FILE" 2>/dev/null
      fi ) &

    # Read cached activity from previous run
    if [ -f "$ACTIVITY_CACHE_FILE" ]; then
      cached_act_ts="" cached_act_json=""
      { read -r cached_act_ts cached_act_json; } < "$ACTIVITY_CACHE_FILE" 2>/dev/null || true
      # Reject non-digits and leading zeroes (bash arithmetic reads 0089 as
      # a bad octal and prints an error during expansion)
      case "$cached_act_ts" in *[!0-9]*|0[0-9]*) cached_act_ts=0 ;; esac
      # Expire after activity_ttl_seconds. The default (120) stays comfortably
      # above typical refreshInterval values so line 2 survives idle timer
      # refreshes while a long subagent or workflow is running.
      case "$activity_ttl_seconds" in ''|*[!0-9]*) activity_ttl_seconds=120 ;; esac
      if [ -n "$cached_act_ts" ] && [ $(( NOW_EPOCH - cached_act_ts )) -le "$activity_ttl_seconds" ] 2>/dev/null; then
        # Extract "activity" value from simple JSON {"activity":"..."},
        # tolerating JSON-escaped quotes and backslashes inside the value
        act_pattern='"activity"[[:space:]]*:[[:space:]]*"(([^"\]|\\.)*)"'
        if [[ ${cached_act_json:-} =~ $act_pattern ]]; then
          activity_line="${BASH_REMATCH[1]}"
          # Unescape the JSON encodings the helper can produce (\" and \\).
          # Anything else (\n, \u, ...) stays literal text: line 2 is
          # printed with %s, never %b, so it can't decode into controls
          activity_line="${activity_line//\\\"/\"}"
          activity_line="${activity_line//\\\\/\\}"
          sanitize "$activity_line"; activity_line=$REPLY
          apply_activity_tokens
        fi
      fi
    fi
  fi
fi

sl_profile "activity"
# ── Usage Limits (5-hour and 7-day) ─────────────────────────
# Preferred: read rate_limits from stdin (Claude Code >= 2.1).
# Fallback:  fetch from Anthropic OAuth API with background caching.

usage_5h="" usage_5h_resets="" usage_7d="" usage_7d_resets=""

# ── Phase 1: Try stdin rate_limits (zero-cost, real-time) ────
stdin_usage=false
rl_guard='"rate_limits"[[:space:]]*:[[:space:]]*\{'
if [[ $input =~ $rl_guard ]]; then
  # Scope extraction to the rate_limits block so a five_hour/seven_day object
  # elsewhere in the payload is never mistaken for rate-limit data. Falls back
  # to the whole input if the block itself cannot be captured.
  extract_block "$input" "rate_limits"; rl_block=$REPLY
  [ -z "$rl_block" ] && rl_block="$input"
  extract_block "$rl_block" "five_hour"; fh_stdin_block=$REPLY
  if [ -n "$fh_stdin_block" ]; then
    extract_num_from "$fh_stdin_block" "used_percentage"; stdin_5h=$REPLY
    extract_num_from "$fh_stdin_block" "resets_at"; stdin_5h_resets=$REPLY
    if [ -n "$stdin_5h" ]; then
      usage_5h="$stdin_5h"
      # resets_at from stdin is epoch seconds — keep it raw; iso_to_epoch
      # passes epochs through, so no date forks on this (the common) path
      if [ -n "$stdin_5h_resets" ]; then
        usage_5h_resets="${stdin_5h_resets%%.*}"
      else
        # Tolerate an ISO-8601 string resets_at (downstream handles ISO natively)
        extract_from "$fh_stdin_block" "resets_at"; usage_5h_resets=$REPLY
        usage_5h_resets="${usage_5h_resets/Z/+00:00}"
      fi
      stdin_usage=true
    fi
  fi
  extract_block "$rl_block" "seven_day"; sd_stdin_block=$REPLY
  if [ -n "$sd_stdin_block" ]; then
    extract_num_from "$sd_stdin_block" "used_percentage"; stdin_7d=$REPLY
    extract_num_from "$sd_stdin_block" "resets_at"; stdin_7d_resets=$REPLY
    if [ -n "$stdin_7d" ]; then
      usage_7d="$stdin_7d"
      if [ -n "$stdin_7d_resets" ]; then
        usage_7d_resets="${stdin_7d_resets%%.*}"
      else
        # Tolerate an ISO-8601 string resets_at (downstream handles ISO natively)
        extract_from "$sd_stdin_block" "resets_at"; usage_7d_resets=$REPLY
        usage_7d_resets="${usage_7d_resets/Z/+00:00}"
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
  extract_from "$creds" "accessToken"; token=$REPLY
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
        extract_num_from "$fh_block" "utilization"; usage_5h=$REPLY
        extract_from "$fh_block" "resets_at"; usage_5h_resets=$REPLY
      fi
      # Extract seven_day block
      sd_pattern='"seven_day"[[:space:]]*:[[:space:]]*\{([^}]+)\}'
      if [[ $usage_json =~ $sd_pattern ]]; then
        sd_block="${BASH_REMATCH[1]}"
        extract_num_from "$sd_block" "utilization"; usage_7d=$REPLY
        extract_from "$sd_block" "resets_at"; usage_7d_resets=$REPLY
      fi
    fi
  fi
fi

fi  # end OAuth fallback (stdin_usage=false)

# Calculate pacing targets — what percentage you *should* have used
# for even consumption across the rolling window. Result in REPLY.
calc_pacing_target() {
  local resets_at="$1" window_secs="$2"
  local reset_ts start_ts elapsed
  REPLY=""
  iso_to_epoch "$resets_at" || return 1
  reset_ts=$REPLY
  start_ts=$(( reset_ts - window_secs ))
  elapsed=$(( NOW_EPOCH - start_ts ))
  [ "$elapsed" -lt 0 ] && elapsed=0
  [ "$elapsed" -gt "$window_secs" ] && elapsed=$window_secs
  REPLY=$(( (elapsed * 100 + window_secs / 2) / window_secs ))
}

# Lowercase the fixed vocab date emits (day abbreviations, AM/PM) without
# tr forks. bash 3.2 has no ${var,,}, so map the known values directly.
lower_day() {
  case "$1" in
    Mon) REPLY=mon ;; Tue) REPLY=tue ;; Wed) REPLY=wed ;; Thu) REPLY=thu ;;
    Fri) REPLY=fri ;; Sat) REPLY=sat ;; Sun) REPLY=sun ;; *) REPLY="$1" ;;
  esac
}
lower_ampm() {
  case "$1" in
    *AM) REPLY="${1%AM}am" ;; *PM) REPLY="${1%PM}pm" ;; *) REPLY="$1" ;;
  esac
}

# Format a reset timestamp into a short human-readable label (in REPLY).
# countdown style is pure arithmetic (zero forks on the stdin epoch path);
# time/day styles cost one date fork (down from 3-6 date+tr forks).
format_reset_label() {
  local resets_at="$1" style="$2"
  local reset_ts out d h
  REPLY=""
  iso_to_epoch "$resets_at" || return 1
  reset_ts=$REPLY
  REPLY=""
  # Round to nearest hour for cleaner display
  local rounded_ts=$(( (reset_ts + 1800) / 3600 * 3600 ))
  if [ "$style" = "time" ]; then
    # Short time like "11pm" or "3am"
    if [[ "${OSTYPE:-}" == darwin* ]]; then
      out=$(date -r "$rounded_ts" '+%-l%p' 2>/dev/null) || return 1
    else
      out=$(date -d "@$rounded_ts" '+%-l%p' 2>/dev/null) || return 1
    fi
    lower_ampm "${out// /}"
  elif [ "$style" = "day" ]; then
    # Day + time like "thu,3pm" — both fields from one date call
    if [[ "${OSTYPE:-}" == darwin* ]]; then
      out=$(date -r "$rounded_ts" '+%a %-l%p' 2>/dev/null) || return 1
    else
      out=$(date -d "@$rounded_ts" '+%a %-l%p' 2>/dev/null) || return 1
    fi
    lower_day "${out%% *}"; d=$REPLY
    lower_ampm "${out##* }"; h=$REPLY
    REPLY="${d},${h}"
  elif [ "$style" = "countdown" ]; then
    # Time remaining until reset, like "2h20m", "3d4h", or "45m".
    # Uses the exact timestamp, not the hour-rounded one.
    local diff=$(( reset_ts - NOW_EPOCH ))
    [ "$diff" -lt 0 ] && diff=0
    local dd=$(( diff / 86400 ))
    local hh=$(( (diff % 86400) / 3600 ))
    local mm=$(( (diff % 3600) / 60 ))
    if [ "$dd" -gt 0 ]; then
      REPLY="${dd}d${hh}h"
    elif [ "$hh" -gt 0 ]; then
      REPLY="${hh}h${mm}m"
    else
      REPLY="${mm}m"
    fi
  fi
}

sl_profile "usage"
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

  # Results via globals — a $(fn) substitution would fork a subshell
  REPLY="$bar"
  REPLY_COLOUR="$colour"
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

# Session start placeholder — before first API response, fields are null/empty.
# Plain ${CLR_DIM}: apply_theme always sets it, and the mono/NO_COLOR theme
# sets it empty on purpose (a :-fallback here would leak \033[2m under NO_COLOR)
if [ -z "$model" ] && [ -z "$used" ]; then
  printf "%b" "${CLR_DIM}Starting...${CLR_RESET}"
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
  extract_block "$input" "vim"; vim_block=$REPLY
  if [ -n "$vim_block" ]; then
    extract_from "$vim_block" "mode"; vim_mode=$REPLY
    [ -n "$vim_mode" ] && add_seg "${CLR_INFO}${vim_mode}${CLR_RESET}" 3
  fi
fi

# Model (priority 3) — coloured by tier: Haiku=green, Sonnet=yellow, Opus=orange, Fable=purple
if [ "$show_model" = "true" ]; then
  model_icon=""
  [ "$use_icons" = "true" ] && model_icon="◆ "
  case "${model:-}" in
    *Haiku*)  model_clr="$CLR_ADD" ;;                # green (cheap)
    *Sonnet*) model_clr="$CLR_WARN" ;;               # yellow (mid)
    *Opus*)   model_clr="$CLR_MODEL_OPUS" ;;          # theme-aware orange (premium)
    *Fable*|*Mythos*) model_clr="$CLR_MODEL_FABLE" ;; # theme-aware purple (frontier)
    *)        model_clr="$CLR_MODEL" ;;               # default blue
  esac
  # Respect NO_COLOR / mono theme
  [ -z "$CLR_RESET" ] && model_clr=""
  add_seg "${model_clr}${model_icon}${model:-?}${CLR_RESET}" 3 "ctx"
fi

# Agent name (priority 3)
if [ "$show_agent" = "true" ]; then
  extract_block "$input" "agent"; agent_block=$REPLY
  if [ -n "$agent_block" ]; then
    extract_from "$agent_block" "name"; agent_name=$REPLY
    if [ -n "$agent_name" ]; then
      sanitize "$agent_name"; agent_name=$REPLY
      agent_icon=""
      [ "$use_icons" = "true" ] && agent_icon="▸ "
      add_seg "${CLR_MODEL}${agent_icon}${agent_name}${CLR_RESET}" 3
    fi
  fi
fi

# Effort level (priority 5) — sent by Claude Code when the model supports
# /effort. Shown as e.g. "eff:xhigh"; absent field hides the segment.
if [ "$show_effort" = "true" ]; then
  extract_block "$input" "effort"; effort_block=$REPLY
  if [ -n "$effort_block" ]; then
    extract_from "$effort_block" "level"; effort_level=$REPLY
    if [ -n "$effort_level" ]; then
      sanitize "$effort_level"; effort_level=$REPLY
      add_seg "${CLR_INFO}eff:${effort_level}${CLR_RESET}" 5
    fi
  fi
fi

# Fast mode indicator (priority 4) — only when stdin reports fast_mode true.
# Yellow because fast mode bills at a higher rate.
if [ "$show_fast_mode" = "true" ]; then
  fm_guard='"fast_mode"[[:space:]]*:[[:space:]]*true'
  if [[ $input =~ $fm_guard ]]; then
    fast_icon=""
    [ "$use_icons" = "true" ] && fast_icon="⚡ "
    add_seg "${CLR_WARN}${fast_icon}fast${CLR_RESET}" 4
  fi
fi

# Context bar (priority 2)
if [ "$show_context_bar" = "true" ]; then
  pct="${used:-0}"
  pct_int="${pct%%.*}"

  # ── Auto-compact awareness ─────────────────────────────────
  # Claude Code auto-compacts at (autocompact window - 33000) tokens and its
  # own UI warns 20000 tokens before that. Constants extracted from Claude
  # Code 2.1.170; display-only, so drift across CC versions is cosmetic.
  # The autocompact window follows CC's resolution order: env override,
  # then settings.json autoCompactWindow, then the model's full window.
  # DISABLE_AUTO_COMPACT / DISABLE_COMPACT turn the marker and auto-warning off.
  compact_pct="" compact_tokens="" ctx_window=""
  if [ -n "$context_size" ] && [ "$context_size" != "0" ]; then
    ctx_window="${context_size%%.*}"
  fi
  if [ -n "$ctx_window" ] && [ -z "${DISABLE_AUTO_COMPACT:-}" ] && [ -z "${DISABLE_COMPACT:-}" ]; then
    acw=""
    case "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}" in
      ''|*[!0-9]*) : ;;
      *)
        acw="$CLAUDE_CODE_AUTO_COMPACT_WINDOW"
        [ "$acw" -lt 100000 ] && acw=100000
        [ "$acw" -gt 1000000 ] && acw=1000000
        ;;
    esac
    if [ -z "$acw" ] && [ -f "${SCRIPT_DIR}/settings.json" ]; then
      acw_pattern='"autoCompactWindow"[[:space:]]*:[[:space:]]*([0-9]+)'
      # Fork-free file read (a $(cat ...) substitution costs a subshell)
      acw_settings=""
      while IFS= read -r acw_line || [ -n "$acw_line" ]; do
        acw_settings+="$acw_line"
      done < "${SCRIPT_DIR}/settings.json" 2>/dev/null || acw_settings=""
      if [[ $acw_settings =~ $acw_pattern ]]; then
        acw="${BASH_REMATCH[1]}"
      fi
    fi
    [ -z "$acw" ] && acw="$ctx_window"
    [ "$acw" -gt "$ctx_window" ] 2>/dev/null && acw="$ctx_window"
    if [ "$acw" -gt 33000 ] 2>/dev/null; then
      compact_tokens=$(( acw - 33000 ))
      compact_pct=$(( compact_tokens * 100 / ctx_window ))
      [ "$compact_pct" -ge 100 ] && compact_pct=99
    fi
  fi

  build_progress_bar "$pct_int" "$compact_pct"
  bar_clr="$REPLY_COLOUR"
  progress_bar="$REPLY"

  # Warning: "auto" (default) fires within 20000 tokens of the auto-compact
  # point, matching Claude Code's own context-low timing on any window size.
  # A numeric context_warn_threshold keeps the legacy raw-percentage rule.
  warn_prefix=""
  warn_now=false
  if [ "${context_warn_threshold:-auto}" = "auto" ]; then
    if [ -n "$compact_tokens" ]; then
      used_tokens=""
      if [ -n "$cw_block" ]; then extract_num_from "$cw_block" "total_input_tokens"; used_tokens=$REPLY; fi
      used_tokens="${used_tokens%%.*}"
      [ -z "$used_tokens" ] && used_tokens=$(( pct_int * ctx_window / 100 ))
      if [ "$used_tokens" -ge $(( compact_tokens - 20000 )) ] 2>/dev/null; then
        warn_now=true
      fi
    elif [ "$pct_int" -ge 80 ] 2>/dev/null; then
      # No window data (older Claude Code): fall back to the legacy 80% rule
      warn_now=true
    fi
  elif [ "$pct_int" -ge "${context_warn_threshold:-80}" ] 2>/dev/null; then
    warn_now=true
  fi
  if [ "$warn_now" = "true" ]; then
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

# Token counts (priority 5) — reuses $cw_block from context window extraction above
if [ "$show_tokens" = "true" ]; then
  if [ -n "$cw_block" ]; then
    extract_num_from "$cw_block" "total_input_tokens"; tok_in=$REPLY
    extract_num_from "$cw_block" "total_output_tokens"; tok_out=$REPLY
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
    calc_pacing_target "$usage_5h_resets" $((5 * 3600)) || true; u5_target=$REPLY
    u5_label_style="time"
    [ "$usage_label" = "countdown" ] && u5_label_style="countdown"
    format_reset_label "$usage_5h_resets" "$u5_label_style" || true; u5_reset_label=$REPLY
    [ -n "$u5_reset_label" ] && u5_label="(${u5_reset_label})"
  fi
  build_progress_bar "$u5_int" "$u5_target"; u5_bar_output="$REPLY_COLOUR"$'\n'"$REPLY"
  u5_bar_clr="${u5_bar_output%%$'\n'*}"
  u5_bar="${u5_bar_output#*$'\n'}"
  add_seg "5hr${u5_label:+ ${u5_label}} ${u5_bar} ${u5_bar_clr}${u5_int}%${CLR_RESET}${usage_stale_suffix}" 3 "usage"
fi

# Weekly usage limit (priority 3)
if [ "$show_usage_7d" = "true" ] && [ -n "$usage_7d" ]; then
  u7_int="${usage_7d%%.*}"
  u7_target=""
  u7_label=""
  if [ -n "$usage_7d_resets" ]; then
    calc_pacing_target "$usage_7d_resets" $((7 * 86400)) || true; u7_target=$REPLY
    u7_label_style="day"
    [ "$usage_label" = "countdown" ] && u7_label_style="countdown"
    format_reset_label "$usage_7d_resets" "$u7_label_style" || true; u7_reset_label=$REPLY
    [ -n "$u7_reset_label" ] && u7_label="(${u7_reset_label})"
  fi
  build_progress_bar "$u7_int" "$u7_target"; u7_bar_output="$REPLY_COLOUR"$'\n'"$REPLY"
  u7_bar_clr="${u7_bar_output%%$'\n'*}"
  u7_bar="${u7_bar_output#*$'\n'}"
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

# Pull request (priority 6) — from the stdin pr block (CC 2.1.145+), so no
# gh calls needed. Coloured by review state; vanishes when the PR closes.
# With pr_link=true (default) the segment is wrapped in an OSC 8 hyperlink
# to pr.url — Claude Code (verified against 2.1.170) converts OSC 8 into
# real clickable links and strips it where unsupported.
if [ "$show_pr" = "true" ]; then
  extract_block "$input" "pr"; pr_block=$REPLY
  if [ -n "$pr_block" ]; then
    extract_num_from "$pr_block" "number"; pr_number=$REPLY
    if [ -n "$pr_number" ]; then
      pr_number="${pr_number%%.*}"
      extract_from "$pr_block" "review_state"; pr_state=$REPLY
      case "$pr_state" in
        approved)          pr_clr="$CLR_ADD" ;;
        changes_requested) pr_clr="$CLR_DEL" ;;
        draft)             pr_clr="$CLR_DIM" ;;
        pending)           pr_clr="$CLR_WARN" ;;
        *)                 pr_clr="$CLR_INFO" ;;
      esac
      pr_text="PR #${pr_number}"
      if [ "$pr_link" = "true" ]; then
        extract_from "$pr_block" "url"; pr_url=$REPLY
        sanitize "$pr_url"; pr_url=$REPLY
        # Strict allowlist: https only, and none of the characters that
        # could break out of the OSC payload or confuse the width maths
        case "$pr_url" in
          *" "*|*'"'*|*"'"*|*\\*|*\;*|*\]*) pr_url="" ;;
          https://?*) ;;
          *) pr_url="" ;;
        esac
        if [ -n "$pr_url" ]; then
          pr_text="\033]8;;${pr_url}\033\\\\${pr_text}\033]8;;\033\\\\"
        fi
      fi
      add_seg "${pr_clr}${pr_text}${CLR_RESET}" 6 "git"
    fi
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
    # Claude Code >= 2.1.153 sets COLUMNS for statusline commands; prefer it
    # because tput cols is unreliable when output is captured (no tty).
    term_width="${COLUMNS:-}"
    [ -z "$term_width" ] && { term_width=$(tput cols 2>/dev/null) || true; }
    [ -z "$term_width" ] && term_width=120
  fi

  # Mark segments as active (1) or dropped (0)
  for (( i=0; i<seg_idx; i++ )); do seg_active[$i]=1; done

  # Pre-compute visible widths (avoids repeated subshell forks in the loop)
  for (( i=0; i<seg_idx; i++ )); do
    visible_width "${seg_vals[$i]}"; seg_widths[$i]=$REPLY
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

sl_profile "segments+render"
# ── Line 1: Status bar ───────────────────────────────────────
printf "%b" "$output"

# ── Line 2: Live activity (optional) ────────────────────────

# Visible width of the activity line (in REPLY): colour tokens were
# substituted with raw SGR escape bytes, so strip that pattern before
# counting. Pure bash, fork-free, bash 3.2 safe.
activity_visible_width() {
  local s="$1" pat="${ESC_CH}\[[0-9;]*m"
  while [[ $s =~ $pat ]]; do s="${s//"${BASH_REMATCH[0]}"/}"; done
  REPLY=${#s}
}

if [ -n "$activity_line" ]; then
  # Trim to the terminal width (Claude Code >= 2.1.153 sets COLUMNS) so a
  # long activity line never wraps and pushes line 1 out of view
  case "${COLUMNS:-}" in
    ''|*[!0-9]*) : ;;
    *)
      if [ "$COLUMNS" -gt 1 ]; then
        if [ "$activity_has_colour" = "true" ]; then
          # Colour-aware trim: drop whole '  │  ' parts from the end until
          # the line fits — never cuts inside an escape sequence. Once a
          # part has been dropped the budget shrinks by 2 so the ' …'
          # suffix appended below still fits inside COLUMNS.
          act_dropped=false
          act_limit="$COLUMNS"
          while :; do
            activity_visible_width "$activity_line"
            [ "$REPLY" -gt "$act_limit" ] || break
            case "$activity_line" in
              *"  │  "*)
                activity_line="${activity_line%"  │  "*}"
                act_dropped=true
                act_limit=$((COLUMNS - 2))
                ;;
              *) break ;;
            esac
          done
          if [ "$act_dropped" = "true" ]; then
            activity_line="${activity_line}${CLR_DIM//\\033/$ESC_CH} …"
          fi
          activity_visible_width "$activity_line"
          if [ "$REPLY" -gt "$COLUMNS" ]; then
            # Still too wide (a single overlong part): plain hard cut
            act_pat="${ESC_CH}\[[0-9;]*m"
            while [[ $activity_line =~ $act_pat ]]; do
              activity_line="${activity_line//"${BASH_REMATCH[0]}"/}"
            done
            activity_line="${activity_line:0:$((COLUMNS - 1))}…"
          fi
        elif [ "${#activity_line}" -gt "$COLUMNS" ]; then
          activity_line="${activity_line:0:$((COLUMNS - 1))}…"
        fi
      fi
      ;;
  esac
  printf '\n'
  # %s for the activity content: it may carry raw colour bytes from token
  # substitution but must never be %b-decoded (transcript-derived text).
  # The dim wrapper and reset are trusted theme constants, %b is fine there.
  printf "%b%s%b" "${CLR_DIM}" "${activity_line}" "${CLR_RESET}"
fi
