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
# Base raw URL for VERSION and the self-update download. Overridable via
# STATUSLINE_REPO_RAW (point at a fork, or a file:// path for testing).
# SECURITY (S2): capture the override from the *real* environment here, before
# statusline.conf is sourced. statusline.conf is sourced as bash, so a malicious
# line could otherwise repoint the (potentially unattended, auto_update) updater
# at an attacker's host — turning a one-time file write into ongoing RCE. REPO_RAW
# is re-pinned from this captured value AFTER the conf load, so the conf can never
# change the update source; only a genuine env var (fork/CI/file:// for tests) can.
_ENV_REPO_RAW="${STATUSLINE_REPO_RAW:-}"
REPO_RAW_DEFAULT="https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main"
REPO_RAW="${_ENV_REPO_RAW:-$REPO_RAW_DEFAULT}"

# ── Claude API status (status.claude.com) ────────────────────
# Optional, default-off early-warning segment. Polls the public Atlassian
# Statuspage status.json in a detached background subshell (like the update
# check) and caches the page's current overall indicator, so the render only
# ever reads a tiny cache: never blocks, never forks on the hot path. We trust
# the indicator (Statuspage derives it from CURRENT component health) and do
# NOT escalate on open incidents: a mitigated 'monitoring' incident or a
# long-lived feature suspension leaves the indicator at 'none', and surfacing
# it would cry wolf while requests still work. SECURITY (S2): capture the URL
# override from the *real* environment here, BEFORE statusline.conf is sourced;
# it is re-pinned AFTER the conf load, so a sourced conf line can never repoint
# the fetch. Only a genuine env var (a fork, or a file:// path for tests) can.
CLAUDE_STATUS_CACHE_FILE="${SCRIPT_DIR}/.statusline-claude-status-cache"
_ENV_CLAUDE_STATUS_URL="${STATUSLINE_CLAUDE_STATUS_URL:-}"
CLAUDE_STATUS_URL_DEFAULT="https://status.claude.com/api/v2/status.json"
CLAUDE_STATUS_URL="${_ENV_CLAUDE_STATUS_URL:-$CLAUDE_STATUS_URL_DEFAULT}"

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
      # SECURITY (S1): the OAuth bearer token must NOT go on argv — wget args are
      # visible in `ps aux` to any local user. Write the secret Authorization
      # header to a 0600 temp wgetrc and pass it via --config; the non-secret
      # headers can stay on the command line. If we can't create the temp file,
      # skip the authenticated fetch rather than leak the token (curl is the
      # strongly-preferred path; this is a last-resort fallback anyway).
      local wgetrc rc
      wgetrc="$(mktemp 2>/dev/null)" || return 1
      chmod 600 "$wgetrc" 2>/dev/null || true
      printf 'header = %s\n' "$HTTP_AUTH_HEADER" > "$wgetrc"
      wget -qO- --timeout="$timeout" --max-redirect=0 \
        --config="$wgetrc" \
        --header="anthropic-beta: oauth-2025-04-20" \
        --header="Content-Type: application/json" \
        "$url" 2>/dev/null
      rc=$?
      rm -f "$wgetrc"
      return "$rc"
    else
      wget -qO- --timeout="$timeout" "$url" 2>/dev/null
    fi
  else
    return 1
  fi
}

# Compute the SHA-256 of a file into REPLY (hash only, no filename). Tries
# sha256sum (Linux/MSYS2) then `shasum -a 256` (macOS). Returns non-zero if no
# tool is available or the file can't be read.
sha256_of() {
  REPLY=""
  if command -v sha256sum > /dev/null 2>&1; then
    REPLY="$(sha256sum "$1" 2>/dev/null)" || return 1
  elif command -v shasum > /dev/null 2>&1; then
    REPLY="$(shasum -a 256 "$1" 2>/dev/null)" || return 1
  else
    return 1
  fi
  REPLY="${REPLY%% *}"   # keep only the leading hash field
  [ -n "$REPLY" ]
}

# True when a SHA-256 tool is available for the integrity check.
have_sha256() {
  command -v sha256sum > /dev/null 2>&1 || command -v shasum > /dev/null 2>&1
}

# Self-update core (shared by --update and the opt-in auto-update). Downloads
# the latest script + helpers to staging files beside their targets, then
# renames them in only after EVERY download succeeds, so a failed or
# interrupted fetch changes nothing. statusline-command.sh moves first — it is
# the running file, so an in-use rename failure (Windows) aborts before any
# version mismatch, and rename is safe while running (the live shell keeps
# reading its original inode). Echoes one line per file; callers control
# verbosity by redirecting. Writes .statusline-version on success. Never
# touches statusline.conf or settings.json.
# Usage: perform_self_update REMOTE_VERSION   ->  0 ok / 1 failed
perform_self_update() {
  local new_ver="$1" f g failed="" sums_tmp actual expected h n
  local files="statusline-command.sh statusline-helper.js statusline-subagent.js"
  # Self-heal staging files left behind by a previously killed attempt.
  find "$SCRIPT_DIR" -maxdepth 1 -name '*.update.*' -mmin +60 -delete 2>/dev/null || true
  for f in $files; do
    if ! http_get "${REPO_RAW}/${f}" 20 > "${SCRIPT_DIR}/.${f}.update.$$" 2>/dev/null \
       || [ ! -s "${SCRIPT_DIR}/.${f}.update.$$" ]; then
      echo "  ✗ failed to download ${f}"
      for g in $files; do rm -f "${SCRIPT_DIR}/.${g}.update.$$"; done
      return 1
    fi
  done
  # ── Integrity verification (G1) ──────────────────────────────
  # The self-updater downloads and then runs bash; auto_update does so
  # unattended. Before swapping anything in, verify every staged file against the
  # release's SHA256SUMS manifest. A mismatch — or a truncated / tampered /
  # man-in-the-middled download — aborts the update with nothing changed. When
  # the manifest can't be fetched (older fork) OR no sha256 tool exists, skip the
  # check gracefully so those installs can still update: checksums harden the
  # canonical path, they don't gate every environment.
  sums_tmp="${SCRIPT_DIR}/.SHA256SUMS.update.$$"
  if have_sha256 && http_get "${REPO_RAW}/SHA256SUMS" 20 > "$sums_tmp" 2>/dev/null && [ -s "$sums_tmp" ]; then
    for f in $files; do
      actual=""
      if sha256_of "${SCRIPT_DIR}/.${f}.update.$$"; then actual="$REPLY"; fi
      expected=""
      while read -r h n _; do
        n="${n#\*}"      # drop the binary-mode marker some tools emit
        n="${n##*/}"     # compare basenames
        if [ "$n" = "$f" ]; then expected="$h"; break; fi
      done < "$sums_tmp"
      if [ -z "$actual" ] || [ -z "$expected" ] || [ "$actual" != "$expected" ]; then
        echo "  ✗ checksum verification failed for ${f} — aborting update"
        for g in $files; do rm -f "${SCRIPT_DIR}/.${g}.update.$$"; done
        rm -f "$sums_tmp"
        return 1
      fi
    done
  fi
  rm -f "$sums_tmp"
  for f in $files; do
    if mv "${SCRIPT_DIR}/.${f}.update.$$" "${SCRIPT_DIR}/${f}" 2>/dev/null; then
      echo "  ✓ ${f}"
    else
      failed="$f"
      for g in $files; do rm -f "${SCRIPT_DIR}/.${g}.update.$$"; done
      echo "  ✗ could not replace ${failed} (in use?)"
      return 1
    fi
  done
  chmod +x "${SCRIPT_DIR}/statusline-command.sh" 2>/dev/null || true
  printf '%s\n' "$new_ver" > "${SCRIPT_DIR}/.statusline-version"
  echo "  ✓ .statusline-version -> ${new_ver}"
  # Best-effort: refresh the commented config template, and seed statusline.conf
  # from it on first run ONLY — never overwrite an existing user config. Failure
  # here never affects the update (the script + helpers are already in place).
  local ex_tmp="${SCRIPT_DIR}/.statusline.conf.example.update.$$"
  if http_get "${REPO_RAW}/statusline.conf.example" 20 > "$ex_tmp" 2>/dev/null && [ -s "$ex_tmp" ]; then
    if mv -f "$ex_tmp" "${SCRIPT_DIR}/statusline.conf.example" 2>/dev/null; then
      echo "  ✓ statusline.conf.example"
      if [ ! -f "${SCRIPT_DIR}/statusline.conf" ] && cp "${SCRIPT_DIR}/statusline.conf.example" "${SCRIPT_DIR}/statusline.conf" 2>/dev/null; then
        echo "  ✓ statusline.conf (created — edit to customise)"
      fi
    fi
  fi
  rm -f "$ex_tmp" 2>/dev/null || true
  return 0
}

# Opt-in background auto-update driver. Serialises with a lock dir so parallel
# sessions don't all download at once, runs the self-update, then clears the
# update cache so the notice disappears on the next render. Silent by design;
# any failure leaves the install intact.
# Usage: run_auto_update REMOTE_VERSION
run_auto_update() {
  local lock="${SCRIPT_DIR}/.statusline-autoupdate.lock"
  # Clear a stale lock left by a killed process (a download never takes 10 min).
  if [ -d "$lock" ]; then
    find "$lock" -maxdepth 0 -type d -mmin +10 -exec rmdir {} + 2>/dev/null || true
  fi
  mkdir "$lock" 2>/dev/null || return 0   # another session is already updating
  umask 077
  if perform_self_update "$1"; then rm -f "$UPDATE_CACHE_FILE"; fi
  rmdir "$lock" 2>/dev/null || true
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
    echo "  --update         Download and install the latest version in place"
    echo "                     bash statusline-command.sh --update"
    echo "                     (keeps statusline.conf and settings.json)"
    echo "  --dump-stdin     Pretty-print the raw JSON Claude Code sends (diagnostic)"
    echo "                     echo '<json>' | bash statusline-command.sh --dump-stdin"
    echo "  --open-config    Open statusline.conf in your editor (creates it if absent)"
    echo "                     bash statusline-command.sh --open-config"
    echo "                     (prefers VS Code; override with \$STATUSLINE_EDITOR)"
    echo "  --dump-config    Print resolved config (defaults + statusline.conf)"
    echo "                     bash statusline-command.sh --dump-config"
    echo "  --uninstall      Interactively remove installed files (prompts before deleting)"
    echo "                     bash statusline-command.sh --uninstall"
    echo "  --benchmark [N]  Time N end-to-end runs (default 5) against a canned payload"
    echo "                     bash statusline-command.sh --benchmark"
    echo "                     STATUSLINE_PROFILE=1 adds a per-phase breakdown to any run"
    echo "  --demo [theme]   Preview a theme (or 'all', the default) with a canned payload"
    echo "                     bash statusline-command.sh --demo tokyo-night"
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
      echo "  bash ~/.claude/statusline-command.sh --update"
    fi
    exit 0
    ;;
  --update)
    # Manual self-update. The download/swap (and its safety properties) live
    # in perform_self_update, shared with the opt-in auto_update path.
    echo "Checking latest..."
    remote_version=$(http_get "${REPO_RAW}/VERSION" 5 | tr -d '[:space:]') || remote_version=""
    if [ -z "$remote_version" ]; then
      echo "  Could not reach the update source. Try again, or update manually:"
      echo "    curl -fsSL ${REPO_RAW}/install.sh | bash"
      exit 1
    fi
    if [ "$remote_version" = "$VERSION" ]; then
      echo "  Already up to date (${VERSION})."
      exit 0
    fi
    echo "  ${remote_version} available (you have ${VERSION})"
    umask 077
    if perform_self_update "$remote_version"; then
      rm -f "$UPDATE_CACHE_FILE"
      echo "statusline.conf and settings.json left untouched."
      echo "Done. New version active on next render."
      exit 0
    fi
    echo "  Update aborted; nothing was changed. Update manually:"
    echo "    curl -fsSL ${REPO_RAW}/install.sh | bash"
    exit 1
    ;;
  --open-config)
    # Open statusline.conf in an editor. Seeds it from the commented example
    # template first if it doesn't exist yet, so there's always something to
    # edit. Editor preference: $STATUSLINE_EDITOR override, then VS Code
    # (`code`), then $VISUAL/$EDITOR, then the platform's default opener.
    conf="${SCRIPT_DIR}/statusline.conf"
    example="${SCRIPT_DIR}/statusline.conf.example"
    if [ ! -f "$conf" ]; then
      if [ -f "$example" ] && cp "$example" "$conf" 2>/dev/null; then
        echo "Created ${conf} from the example template."
      elif : > "$conf" 2>/dev/null; then
        echo "Created empty ${conf} (no example template found)."
      fi
    fi
    if [ ! -f "$conf" ]; then
      echo "Could not create or find ${conf}." >&2
      exit 1
    fi
    echo "Opening ${conf}"
    if [ -n "${STATUSLINE_EDITOR:-}" ]; then
      $STATUSLINE_EDITOR "$conf"
    elif command -v code >/dev/null 2>&1; then
      code "$conf"
    elif [ -n "${VISUAL:-}" ]; then
      $VISUAL "$conf"
    elif [ -n "${EDITOR:-}" ]; then
      $EDITOR "$conf"
    elif command -v open >/dev/null 2>&1; then
      open "$conf"        # macOS
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$conf"    # Linux
    elif command -v cygstart >/dev/null 2>&1; then
      cygstart "$conf"    # MSYS2 / Cygwin
    elif command -v cmd >/dev/null 2>&1; then
      # Windows (Git Bash): cmd's `start` needs a native path, not MSYS /c/...
      win_conf="$conf"
      command -v cygpath >/dev/null 2>&1 && win_conf="$(cygpath -w "$conf")"
      cmd //c start "" "$win_conf"
    else
      echo "No editor found. Set \$EDITOR or open it manually:" >&2
      echo "  ${conf}" >&2
      exit 1
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

# version_gt A B -> exit 0 if dotted-numeric version A is strictly greater than
# B (missing / non-numeric fields count as 0). The update notice fires only for
# a genuinely NEWER remote version, never a stale or older cached one — e.g.
# raw.githubusercontent.com still serving the previous VERSION for minutes after
# a release, or a cache left over from a local update would otherwise show a
# phantom "↑ <older>" notice while you are already on the newer version.
version_gt() {
  local a="$1" b="$2" ai bi
  while [ -n "$a" ] || [ -n "$b" ]; do
    ai="${a%%.*}"; [ "$ai" = "$a" ] && a="" || a="${a#*.}"
    bi="${b%%.*}"; [ "$bi" = "$b" ] && b="" || b="${b#*.}"
    case "$ai" in ''|*[!0-9]*) ai=0 ;; esac
    case "$bi" in ''|*[!0-9]*) bi=0 ;; esac
    if [ "$ai" -gt "$bi" ]; then return 0; fi
    if [ "$ai" -lt "$bi" ]; then return 1; fi
  done
  return 1
}

check_for_update() {
  # Read cache: "timestamp remote_version"
  if [ -f "$UPDATE_CACHE_FILE" ]; then
    local cached_time cached_version
    read -r cached_time cached_version < "$UPDATE_CACHE_FILE" 2>/dev/null || true
    # Guard: cached_time must be numeric (corrupted cache files may contain other data)
    case "$cached_time" in *[!0-9]*) cached_time="" ;; esac
    if [ -n "$cached_time" ] && [ $(( NOW_EPOCH - cached_time )) -lt $UPDATE_CHECK_INTERVAL ]; then
      # Cache is fresh — surface the notice only if the cached remote version
      # is strictly newer than what we're running (not merely different).
      if [ -n "$cached_version" ] && version_gt "$cached_version" "$VERSION"; then
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
  ) >/dev/null 2>&1 </dev/null &   # fully detached: must not hold the render's stdout pipe open
}

# Map a Claude-status indicator to a numeric severity rank (higher = worse),
# returned in REPLY. maintenance ranks with minor so the default major-floor
# treats a planned window as non-alarming noise (shown only when min=minor).
claude_status_rank() {
  case "$1" in
    critical)          REPLY=3 ;;
    major)             REPLY=2 ;;
    minor|maintenance) REPLY=1 ;;
    *)                 REPLY=0 ;;
  esac
}

# Refresh the Claude-API-status cache (opt-in; see show_claude_status). Reads
# the last-known status into the cs_ts/cs_ind globals for THIS render, then,
# only if the cache is stale or missing, spawns a fully-detached background
# fetch (never blocks). Mirrors check_for_update; the cache line is "<epoch>
# <indicator>" = the status page's current overall indicator. We trust the
# indicator (Statuspage derives it from CURRENT component health) and do NOT
# escalate on open incidents: a mitigated 'monitoring' incident or a long-lived
# suspension leaves the indicator at 'none', and surfacing it would cry wolf
# while requests still work.
check_claude_status() {
  if [ -f "$CLAUDE_STATUS_CACHE_FILE" ]; then
    read -r cs_ts cs_ind < "$CLAUDE_STATUS_CACHE_FILE" 2>/dev/null || true
    case "$cs_ts" in *[!0-9]*) cs_ts="" ;; esac
    # Fresh enough: render uses cs_ind/cs_ts; do not touch the network.
    if [ -n "$cs_ts" ] && [ $(( NOW_EPOCH - cs_ts )) -lt "$claude_status_cache_seconds" ]; then
      return
    fi
  fi

  # Stale or missing: refresh in a detached background subshell. The render
  # still shows the last-known cs_ind (subject to the segment's staleness ceiling).
  (
    body=$(http_get "$CLAUDE_STATUS_URL" 3) || body=""
    # Write ONLY a well-formed body: a failed/garbage fetch (network blip, the
    # status page itself down, a proxied env that can't reach it) leaves the
    # previous cache untouched, so the bar never flashes a false "down".
    case "$body" in *'"indicator"'*) ;; *) body="" ;; esac
    if [ -n "$body" ]; then
      ind="none"
      [[ $body =~ \"indicator\"[[:space:]]*:[[:space:]]*\"([a-z]+)\" ]] && ind="${BASH_REMATCH[1]}"
      case "$ind" in none|minor|major|critical|maintenance) ;; *) ind="none" ;; esac
      echo "$(date +%s) $ind" > "$CLAUDE_STATUS_CACHE_FILE"
    fi
  ) >/dev/null 2>&1 </dev/null &   # fully detached: must not hold the render's stdout pipe open
}

# Skip the background update check for diagnostic / management flags
# (they would race with cache deletion or pollute --dump-config output).
case "${1:-}" in
  --dump-config|--uninstall|--benchmark|--demo) ;;
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
#   1=dir+branch  2=context  3=model,usage,claude-status  4=cost  5=lines,dirty
#   6=ahead/behind,stash  7=duration  8=worktree  9=update

show_directory=true
show_branch=true
show_model=true
show_context_bar=true
show_lines_changed=true
show_dirty_count=true
show_ahead_behind=true
show_stash=true
# git_untracked=false adds `--untracked-files=no` to the status call, skipping
# the working-tree scan for untracked files — the only part of `git status` that
# scales with repo size. Speeds up large / network-mounted repos; the trade-off
# is that untracked files no longer count toward the dirty total. Default true
# keeps the current behaviour (untracked counted).
git_untracked=true
# git_timeout=N wraps the two git calls in a best-effort `timeout N` (or macOS
# `gtimeout`) so a hung NFS/SMB mount can't stall the render. 0 disables it
# (default; no behaviour change). Where no timeout command exists (e.g. stock
# macOS without coreutils) the raw call is used regardless.
git_timeout=0
show_duration=true
show_worktree=true
show_cost=true
show_cost_rate=false
show_usage_5h=true
show_usage_7d=true
usage_label="countdown"
# Burn-rate forecast: when usage is on track to hit the limit BEFORE the window
# resets, the countdown label becomes a "▲time-to-limit" warning (e.g. ▲1h20m).
# Only appears when you're over an even pace, so it stays quiet otherwise.
usage_forecast=true
# Model-scoped weekly swap (on by default): some plans carry a per-model weekly
# limit ("Fable"/"Opus" rows on claude.ai) alongside the all-models one. When
# that scoped limit is HIGHER — i.e. it's the one that will throttle you first —
# the wk bar swaps to it ("wk:Fable (…) 36%"). The data only exists in the OAuth
# usage API (Claude Code doesn't forward it on stdin), so this keeps the
# background usage fetch alive even on stdin-native Claude Code — fail-silent,
# cached, never on the render hot path. false = plain all-models wk bar (and no
# OAuth fetch when stdin already covers the numbers).
usage_scoped=true
show_pr=true
pr_link=true
# Claude API status (status.claude.com). Opt-in early-warning segment: polls
# the public Statuspage in the background and shows a badge ONLY when Claude is
# degraded (nothing when healthy). Off by default — it adds an outbound host.
# claude_status_min is the floor: 'major' (default) shows only major/critical
# outages; 'minor' also surfaces minor degradation + maintenance windows.
# It's an early warning, not ground truth — it can lag a live incident.
# claude_status_cache_seconds is the background poll interval (also the link's
# OSC 8 hyperlink reuses the pr_link toggle).
show_claude_status=false
claude_status_min=major
claude_status_cache_seconds=300
usage_cache_seconds=600
# Opt-in: when an update is detected, download and install it in the
# background automatically (atomic; never touches statusline.conf/settings.json).
auto_update=false
auto_hide=true
use_icons=true
# Icon set: 'classic' (default — today's glyphs) or 'modern' (refreshed:
# directory ↱, branch ⑂, lines-changed ⇄, duration ⏱; model ◆ unchanged).
# use_icons=false drops all icons regardless of icon_set.
icon_set="classic"
context_warn_threshold=auto
# On by default: when the bar is wider than the terminal, drop low-priority
# segments (lowest first) until it fits, instead of wrapping. Pairs with
# dir_style=auto, which collapses the path first. Set false to never drop.
enable_truncation=true
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
# Progress-bar gradient (on by default). 'true' = the theme's own gradient
# ramp (the 'default' theme's is a green->red heat ramp); 'false' = a flat
# single colour; 'heat' = a fixed green->yellow->orange->red ramp on any
# theme. Pure-bash integer lerp (no measurable cost); no-op under mono/NO_COLOR.
bar_gradient=true
branch_max_length=""
# Directory display: 'auto' (default — full path when the line fits the
# terminal width, basename when it would overflow), 'full' (always the whole
# path), or 'basename' (always just the last folder). 'auto' needs a known
# width (COLUMNS, which Claude Code sets; or max_width/tput).
dir_style="auto"
# Multi-line layout. 'layout' selects a preset; line1/line2/line3 (left UNSET
# by default — do not declare them here) override it per line with a
# space-separated list of segment-name tokens. Presets: classic (default —
# all metrics on line 1, the live activity on line 2), three-line, stacked.
# An explicitly set line (even line2="") wins over the preset for that line.
# See statusline.conf.example for the full token vocabulary.
layout="classic"
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
# Capture the env theme override BEFORE sourcing the conf, so a (stray) conf
# line setting STATUSLINE_THEME can't clobber the real env value. This is the
# env-only knob --demo uses to preview a theme.
_env_theme="${STATUSLINE_THEME:-}"
STATUSLINE_CONF="${SCRIPT_DIR}/statusline.conf"
# shellcheck disable=SC1090
[ -f "$STATUSLINE_CONF" ] && . "$STATUSLINE_CONF"

# Apply the env override after the conf so it always wins. A STATUSLINE_THEME
# line in the conf is therefore a harmless no-op (it's an environment-only knob,
# not a config key — use colour_theme to set the theme in the conf).
[ -n "$_env_theme" ] && colour_theme="$_env_theme"

# SECURITY (S2): re-pin the update source from the value captured BEFORE the conf
# load. This neutralises a conf line that tries to set REPO_RAW (or export
# STATUSLINE_REPO_RAW) to repoint the self-updater — the update source can only
# come from a real environment variable, never from the sourced config file.
REPO_RAW="${_ENV_REPO_RAW:-$REPO_RAW_DEFAULT}"
# Same S2 re-pin for the Claude-status fetch source (captured near the top).
CLAUDE_STATUS_URL="${_ENV_CLAUDE_STATUS_URL:-$CLAUDE_STATUS_URL_DEFAULT}"

# Backwards compatibility: accept old name
[ "${show_usage_weekly:-}" = "true" ] && show_usage_7d=true
[ "${show_usage_weekly:-}" = "false" ] && show_usage_7d=false

# --demo preview mode: the --demo dispatch re-invokes this script per theme with
# STATUSLINE_DEMO=1 so the preview is clean and complete regardless of the user's
# terminal width or git state: never truncate, show just the folder basename, and
# drop the noisy git-state segments, so each theme's colours and gradient bars are
# what stand out. (The canonical scene is built in the --demo branch below;
# docs/assets/themes/generate-theme-demos.sh renders the same scene to SVG.)
if [ "${STATUSLINE_DEMO:-}" = "1" ]; then
  enable_truncation=false
  dir_style="basename"
  show_dirty_count=false
  show_ahead_behind=false
  show_stash=false
  # Keep the preview deterministic: the scoped-weekly swap reads the REAL
  # usage cache, which would vary the canned wk bar per machine/account.
  usage_scoped=false
fi

# ── Post-config CLI Flags ─────────────────────────────────────
# These flags need the resolved config (defaults + statusline.conf),
# but must run BEFORE we read stdin, fetch caches, or hit the network.
case "${1:-}" in
  --dump-config)
    # Print resolved config as alphabetically-sorted key=value pairs.
    # Reflects defaults overridden by ~/.claude/statusline.conf.
    {
      printf 'auto_hide=%s\n'              "${auto_hide}"
      printf 'auto_update=%s\n'            "${auto_update}"
      printf 'bar_gradient=%s\n'           "${bar_gradient}"
      printf 'bar_width=%s\n'              "${bar_width}"
      printf 'branch_max_length=%s\n'      "${branch_max_length}"
      printf 'claude_status_cache_seconds=%s\n' "${claude_status_cache_seconds}"
      printf 'claude_status_min=%s\n'      "${claude_status_min}"
      printf 'show_claude_status=%s\n'     "${show_claude_status}"
      printf 'dir_style=%s\n'              "${dir_style}"
      printf 'colour_theme=%s\n'           "${colour_theme}"
      printf 'context_warn_threshold=%s\n' "${context_warn_threshold}"
      printf 'enable_truncation=%s\n'      "${enable_truncation}"
      printf 'group_close=%s\n'            "${group_close}"
      printf 'group_open=%s\n'             "${group_open}"
      printf 'icon_set=%s\n'               "${icon_set}"
      printf 'layout=%s\n'                 "${layout}"
      printf 'line1=%s\n'                  "${line1:-}"
      printf 'line2=%s\n'                  "${line2:-}"
      printf 'line3=%s\n'                  "${line3:-}"
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
      printf 'usage_forecast=%s\n'         "${usage_forecast}"
      printf 'usage_scoped=%s\n'           "${usage_scoped}"
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
      "${SCRIPT_DIR}/.statusline-claude-status-cache"
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
  --demo)
    # Preview a theme (or all eight) with a realistic canned payload, without
    # touching the user's statusline.conf. Re-invokes this script per theme
    # with STATUSLINE_THEME set; the child renders normally (no recursion).
    # Usage: statusline-command.sh --demo [theme|all]
    demo_themes="default nord dracula solarized tokyo-night catppuccin matrix mono"
    case "${2:-all}" in
      all|'') : ;;
      *) demo_themes="$2" ;;
    esac
    # Canonical preview scene (also rendered to the README's per-theme SVGs by
    # docs/assets/themes/generate-theme-demos.sh): a 1M-context model name (which
    # exercises the " context" trim and matches the 1M window), varied bar fills
    # (low 5h, mid context, near-full weekly) so the whole green->red gradient
    # range shows, tokens kept below the auto-compact warning band, and both
    # usage windows kept UNDER pace (weekly resets soon, an end-of-week scene) so
    # the theme preview stays clean and deterministic with no ▲ forecast/warning.
    demo_json="{\"cwd\":\"$PWD\",\"model\":{\"display_name\":\"Opus 4.8 (1M context)\"},\"context_window\":{\"used_percentage\":78,\"context_window_size\":1000000,\"total_input_tokens\":780000},\"total_cost_usd\":0.45,\"rate_limits\":{\"five_hour\":{\"used_percentage\":37,\"resets_at\":$(( NOW_EPOCH + 8400 ))},\"seven_day\":{\"used_percentage\":98,\"resets_at\":$(( NOW_EPOCH + 3600 ))}}}"
    for demo_t in $demo_themes; do
      printf '%s\n' "── ${demo_t} ──"
      printf '%s' "$demo_json" | STATUSLINE_THEME="$demo_t" STATUSLINE_DEMO=1 bash "$0" 2>/dev/null || true
      printf '\n\n'
    done
    exit 0
    ;;
esac

# ── Claude API status refresh (opt-in, default off) ──────────
# Reaches here only on a normal render (every management flag above exits), so
# --dump-config/--benchmark/--demo/--uninstall never trigger a fetch. Detached,
# never blocks; sets cs_ind/cs_ts for the segment built later.
cs_ind="" cs_ts=""
[ "$show_claude_status" = "true" ] && check_claude_status

# ── Auto-update (opt-in) ─────────────────────────────────────
# With auto_update=true, once the background check has flagged a newer
# version (update_available, read from the cache by check_for_update),
# install it. Detached so it never holds the render's stdout open — the
# download is longer than the version probe. Only a clean version string
# is acted on. STATUSLINE_AUTOUPDATE_SYNC runs it inline (tests only).
if [ "$auto_update" = "true" ] && [ -n "$update_available" ]; then
  case "$update_available" in
    ''|*[!0-9.]*) ;;
    *)
      if [ -n "${STATUSLINE_AUTOUPDATE_SYNC:-}" ]; then
        run_auto_update "$update_available" > /dev/null 2>&1
      else
        run_auto_update "$update_available" > /dev/null 2>&1 < /dev/null &
      fi
      ;;
  esac
fi

# ── Colour Themes ────────────────────────────────────────────
# Respect NO_COLOR standard (https://no-color.org/)
[ -n "${NO_COLOR:-}" ] && colour_theme="mono"

# Truecolour (24-bit) support. The named themes carry exact hex palettes; with
# truecolour we emit them as-is (38;2;r;g;b), otherwise we fall back to the
# nearest xterm-256 colour (38;5;N) so Terminal.app and older terminals still
# get sensible colours. Explicit STATUSLINE_TRUECOLOR wins over the COLORTERM
# heuristic (and lets the tests pin a mode).
case "${STATUSLINE_TRUECOLOR:-}" in
  1|true)  TRUECOLOR=1 ;;
  0|false) TRUECOLOR=0 ;;
  *) case "${COLORTERM:-}" in *truecolor*|*24bit*) TRUECOLOR=1 ;; *) TRUECOLOR=0 ;; esac ;;
esac

# Map a channel value (0-255) to its nearest xterm-256 cube index (0-5).
# Cube levels are 0,95,135,175,215,255; the cutoffs below are the midpoints.
cube_index() {
  if   [ "$1" -lt 48 ];  then REPLY=0
  elif [ "$1" -lt 115 ]; then REPLY=1
  elif [ "$1" -lt 155 ]; then REPLY=2
  elif [ "$1" -lt 195 ]; then REPLY=3
  elif [ "$1" -lt 235 ]; then REPLY=4
  else                        REPLY=5
  fi
}

# Real ESC/BEL bytes, defined early so the colour helpers and themes below can
# emit GENUINE escape bytes (not the literal text "\033"). The line-1 metric is
# printed with %s (never %b — see line-1 render), so the script's own colours
# must already be real ESC, and an untrusted field carrying the printable text
# "\033" can never be decoded into a live control sequence. BSD sed (stock
# macOS) does not interpret \x1b, so the bytes are interpolated from bash.
ESC_CH=$'\x1b'
BEL_CH=$'\x07'

# Convert a 6-hex colour to an SGR fg escape, truecolour or nearest-256.
# Pure bash (no forks); returns real-ESC "<ESC>[...m" text via REPLY.
tc_clr() {
  local h="$1" r g b ri gi bi
  r=$(( 16#${h:0:2} )); g=$(( 16#${h:2:2} )); b=$(( 16#${h:4:2} ))
  if [ "$TRUECOLOR" = "1" ]; then
    REPLY="${ESC_CH}[38;2;${r};${g};${b}m"
    return
  fi
  cube_index "$r"; ri=$REPLY
  cube_index "$g"; gi=$REPLY
  cube_index "$b"; bi=$REPLY
  REPLY="${ESC_CH}[38;5;$(( 16 + 36*ri + 6*gi + bi ))m"
}

# Assign every CLR_* role from a positional hex list (truecolour-aware).
# Order: dir branch model opus fable add del warn info dim
#        bar_ok bar_med bar_high pace ramp0 ramp1 ramp2 ramp3
apply_palette() {
  tc_clr "$1";    CLR_DIR=$REPLY
  tc_clr "$2";    CLR_BRANCH=$REPLY
  tc_clr "$3";    CLR_MODEL=$REPLY
  tc_clr "$4";    CLR_MODEL_OPUS=$REPLY
  tc_clr "$5";    CLR_MODEL_FABLE=$REPLY
  tc_clr "$6";    CLR_ADD=$REPLY
  tc_clr "$7";    CLR_DEL=$REPLY
  tc_clr "$8";    CLR_WARN=$REPLY
  tc_clr "$9";    CLR_INFO=$REPLY
  tc_clr "${10}"; CLR_DIM=$REPLY
  tc_clr "${11}"; CLR_BAR_OK=$REPLY
  tc_clr "${12}"; CLR_BAR_MED=$REPLY
  tc_clr "${13}"; CLR_BAR_HIGH=$REPLY
  tc_clr "${14}"; CLR_PACE=$REPLY
  tc_clr "${15}"; CLR_RAMP0=$REPLY
  tc_clr "${16}"; CLR_RAMP1=$REPLY
  tc_clr "${17}"; CLR_RAMP2=$REPLY
  tc_clr "${18}"; CLR_RAMP3=$REPLY
  # Raw ramp hexes kept for the smooth per-cell gradient bar (bar_gradient).
  RAMP_HEX="${15} ${16} ${17} ${18}"
  CLR_RESET="${ESC_CH}[0m"
}

apply_theme() {
  case "${colour_theme:-default}" in
    # Named palettes are spread across a saturation/temperature ladder so no
    # two read alike, rendered in truecolour (256-colour fallback). Role order:
    # dir branch model opus fable add del warn info dim
    # bar_ok bar_med bar_high pace ramp0 ramp1 ramp2 ramp3.
    nord)        # MUTED — cool steel/slate (Nord)
      apply_palette 81a1c1 b48ead 88c0d0 d08770 b48ead a3be8c bf616a ebcb8b 8fbcbb 4c566a a3be8c ebcb8b bf616a 5e81ac a3be8c ebcb8b d08770 bf616a ;;
    dracula)     # NEON — electric, maximum saturation (Dracula)
      apply_palette bd93f9 ff79c6 8be9fd ffb86c bd93f9 50fa7b ff5555 f1fa8c 8be9fd 6272a4 50fa7b f1fa8c ff5555 ff79c6 50fa7b f1fa8c ffb86c ff5555 ;;
    solarized)   # EARTHY — vintage, desaturated, teal + amber (Solarized)
      apply_palette 2aa198 6c71c4 268bd2 cb4b16 6c71c4 859900 dc322f b58900 2aa198 586e75 859900 b58900 dc322f d33682 859900 b58900 cb4b16 dc322f ;;
    tokyo-night) # DEEP — midnight royal-blue + violet base, neon accents
      apply_palette 5a7bf0 9d7cd8 7dcfff ff9e64 9d7cd8 9ece6a f7768e e0af68 7dcfff 565f89 9ece6a e0af68 f7768e ff007c 9ece6a e0af68 ff9e64 f7768e ;;
    catppuccin)  # SOFT PASTEL — warm lavender/peach (Catppuccin Mocha)
      apply_palette b4befe cba6f7 89dceb fab387 cba6f7 a6e3a1 f38ba8 f9e2af 89dceb 6c7086 a6e3a1 f9e2af f38ba8 f5c2e7 a6e3a1 94e2d5 f9e2af fab387 ;;
    matrix)      # MONOCHROME — phosphor digital-rain green, separated by brightness
      apply_palette 00ff41 22ff88 00cc33 aaffaa 22ff88 00ff00 008f11 9eff5e 22ff88 005f00 008f11 00ff00 9eff5e d6ffd6 005f00 008f11 00cc33 00ff00 ;;
    mono)
      CLR_DIR="" CLR_BRANCH="" CLR_MODEL="" CLR_MODEL_OPUS="" CLR_MODEL_FABLE=""
      CLR_ADD="" CLR_DEL="" CLR_WARN="" CLR_INFO="" CLR_DIM=""
      CLR_BAR_OK="" CLR_BAR_MED="" CLR_BAR_HIGH="" CLR_PACE=""
      CLR_RAMP0="" CLR_RAMP1="" CLR_RAMP2="" CLR_RAMP3=""
      RAMP_HEX=""
      CLR_RESET=""
      ;;
    *) # default — original colours
      CLR_DIR="${ESC_CH}[0;36m"     # cyan
      CLR_BRANCH="${ESC_CH}[0;35m"  # magenta
      CLR_MODEL="${ESC_CH}[0;34m"   # blue
      CLR_MODEL_OPUS="${ESC_CH}[38;5;208m" # orange (Opus tier)
      CLR_MODEL_FABLE="${ESC_CH}[38;5;141m" # purple (Fable tier)
      CLR_ADD="${ESC_CH}[0;32m"     # green
      CLR_DEL="${ESC_CH}[0;31m"     # red
      CLR_WARN="${ESC_CH}[0;33m"    # yellow
      CLR_INFO="${ESC_CH}[0;36m"    # cyan
      CLR_DIM="${ESC_CH}[0;90m"    # dark grey
      CLR_BAR_OK="${ESC_CH}[0;32m"  # green
      CLR_BAR_MED="${ESC_CH}[0;33m" # yellow
      CLR_BAR_HIGH="${ESC_CH}[0;31m" # red
      CLR_PACE="${ESC_CH}[38;5;199m"  # hot pink pacing marker
      CLR_RAMP0="${ESC_CH}[38;5;40m"  CLR_RAMP1="${ESC_CH}[38;5;220m" # todo-bar gradient
      CLR_RAMP2="${ESC_CH}[38;5;208m" CLR_RAMP3="${ESC_CH}[38;5;196m" # green->yellow->orange->red (heat)
      # Hex stops for the smooth gradient bar — a green->red "heat" ramp.
      RAMP_HEX="2ecc40 ffdc00 ff851b ff4136"
      CLR_RESET="${ESC_CH}[0m"
      ;;
  esac
}

apply_theme

# Icon glyphs that DIFFER between the 'classic' (default) and 'modern' sets are
# exposed as ICON_* variables and consumed at their build sites. All other
# glyphs (model ◆, agent ▸, fast ⚡, dirty ●, stash ≡, worktree ⊞, ahead/behind
# ↑↓, update ↑, cost $, context-warn ▲) are identical in both sets and stay
# inline. use_icons=false zeroes every ICON_* (fork-free, pure assignment).
apply_icon_set() {
  ICON_DIR="" ICON_BRANCH="" ICON_LINES="" ICON_DURATION=""
  [ "$use_icons" = "true" ] || return 0
  case "${icon_set:-classic}" in
    modern)
      ICON_DIR="↱ " ICON_BRANCH="⑂ " ICON_LINES="⇄ " ICON_DURATION="⏱ " ;;
    *) # classic — byte-identical to the pre-2.19 icons
      ICON_BRANCH="↱ " ;;   # dir / lines / duration have no icon in classic
  esac
}
apply_icon_set

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
# Decode JSON string escapes (\\ \/ \" \n \t \r \b \f) in a value; result in
# REPLY. Single-pass, chunk-based, pure bash (no forks). The fast-path returns
# the value untouched when it has no backslash — the common case for every
# macOS/Linux path and model name. The motivating case is the Windows cwd,
# which JSON encodes with "\\" separators (otherwise rendered as doubled "\\").
# A naive global "\\"->"\" replace mis-decodes a "\\" adjacent to a real "\n"
# escape; scanning left-to-right one backslash at a time is correct. \uXXXX is
# left literal (rare in the fields we extract; bash 3.2 can't decode it cheaply).
json_unescape() {
  local s="$1"
  case $s in
    *\\*) ;;                     # has a backslash — decode below
    *) REPLY=$s; return ;;       # fast path: nothing to unescape
  esac
  local out="" chunk c
  while [ -n "$s" ]; do
    chunk=${s%%\\*}              # text before the next backslash
    if [ "$chunk" = "$s" ]; then # no further backslash
      out+=$s; break
    fi
    out+=$chunk
    c=${s:${#chunk}+1:1}        # the char escaped by that backslash
    case $c in
      n)  out+=$'\n' ;;
      t)  out+=$'\t' ;;
      r)  out+=$'\r' ;;
      b)  out+=$'\b' ;;
      f)  out+=$'\f' ;;
      /)  out+='/'   ;;
      \\) out+='\'   ;;
      \") out+='"'   ;;
      '') out+='\'   ;;          # trailing lone backslash
      *)  out+="\\$c" ;;         # unknown escape — keep both bytes verbatim
    esac
    s=${s:${#chunk}+2}          # past chunk + backslash + escaped char
  done
  REPLY=$out
}

extract_from() {
  local json="$1" key="$2"
  local pattern="\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  REPLY=""
  if [[ $json =~ $pattern ]]; then
    json_unescape "${BASH_REMATCH[1]}"
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

# ESC_CH / BEL_CH are defined near tc_clr (above) so the theme constants can
# carry real ESC bytes; they are reused here for sanitize/visible_width.

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
  local s="$1" pat
  # OSC 8 hyperlink wrappers — real ESC form (the colours/links now carry real
  # ESC bytes), then the legacy literal "\033" form defensively.
  pat="${ESC_CH}\]8;[^${ESC_CH}]*${ESC_CH}\\\\"
  while [[ $s =~ $pat ]]; do s="${s//"${BASH_REMATCH[0]}"/}"; done
  pat='\\033\]8;[^\\]*\\033\\\\'
  while [[ $s =~ $pat ]]; do s="${s//"${BASH_REMATCH[0]}"/}"; done
  # SGR sequences — real ESC, then legacy literal "\033".
  pat="${ESC_CH}\[[0-9;]*[a-zA-Z]"
  while [[ $s =~ $pat ]]; do s="${s//"${BASH_REMATCH[0]}"/}"; done
  pat='\\033\[[0-9;]*[a-zA-Z]'
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
# Drop the redundant " context" from window-size suffixes to save space:
# "Opus 4.8 (1M context)" -> "Opus 4.8 (1M)". Only touches that exact pattern.
model="${model/ context)/)}"
# Strip ANSI/control bytes like every other displayed field (defence in depth;
# the %s line-1 print already blocks decoded escape *text*, this blocks raw bytes).
sanitize "$model"; model=$REPLY

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
# Optional best-effort timeout prefix (git_timeout>0) so a hung network mount
# can't stall the render; resolved once, empty when disabled or no timeout cmd.
git_tmo=""
case "${git_timeout:-0}" in
  ''|*[!0-9]*|0) ;;
  *) if command -v timeout > /dev/null 2>&1; then git_tmo="timeout ${git_timeout}"
     elif command -v gtimeout > /dev/null 2>&1; then git_tmo="gtimeout ${git_timeout}"; fi ;;
esac
git_dirs=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  # shellcheck disable=SC2086  # $git_tmo is an intentional optional command prefix
  git_dirs=$($git_tmo git -C "$cwd" --no-optional-locks -c core.fsmonitor=false rev-parse --git-dir --git-common-dir 2>/dev/null) || git_dirs=""
fi
if [ -n "$git_dirs" ]; then
  git_common="${git_dirs##*$'\n'}"

  # One `status --porcelain=v2 --branch` call provides the branch name,
  # ahead/behind, and the dirty count — replacing three git forks plus
  # their wc/tr/cut pipelines. Header lines are parsed in pure bash; the
  # entry count comes from line arithmetic so huge dirty trees stay cheap.
  if [ "$show_branch" = "true" ] || [ "$show_dirty_count" = "true" ] || [ "$show_ahead_behind" = "true" ]; then
    # git_untracked=false skips the untracked-file scan (the only part of
    # `git status` that scales with working-tree size).
    git_uflag=""; [ "$git_untracked" = "false" ] && git_uflag="--untracked-files=no"
    # shellcheck disable=SC2086  # $git_tmo / $git_uflag are intentional optional args
    git_status=$($git_tmo git -C "$cwd" --no-optional-locks -c core.fsmonitor=false status --porcelain=v2 --branch $git_uflag 2>/dev/null) || git_status=""
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
    # Marker touched only when we actually spawn the helper, so a fork-free
    # `-nt` compare against the transcript detects new transcript content.
    ACTIVITY_SEEN_FILE="${ACTIVITY_CACHE_FILE}.seen"

    # Read the PREVIOUS run's cache first: its "next" hint decides whether the
    # helper even needs to run this render (the spawn gate below).
    cached_act_ts=0 cached_act_json="" cached_act_next=0
    if [ -f "$ACTIVITY_CACHE_FILE" ]; then
      { read -r cached_act_ts cached_act_json; } < "$ACTIVITY_CACHE_FILE" 2>/dev/null || true
      # Reject non-digits and leading zeroes (bash arithmetic reads 0089 as
      # a bad octal and prints an error during expansion)
      case "$cached_act_ts" in *[!0-9]*|0[0-9]*) cached_act_ts=0 ;; esac
      if [[ ${cached_act_json:-} =~ \"next\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
        cached_act_next="${BASH_REMATCH[1]}"
      fi
    fi

    # ── Spawn gate (P-B) ──────────────────────────────────────
    # Re-running the Node helper costs ~the same whether or not the transcript
    # changed (process startup dominates), so only run it when the line could
    # actually change: no cache yet, the transcript grew/changed since the last
    # run (fork-free `-nt` vs the marker), or the helper's "next" hint says a
    # time-based transition is due (elapsed tick, completion-flash expiry, recent
    # age-out). Otherwise the cached line is still correct.
    spawn_helper=false
    [ ! -f "$ACTIVITY_CACHE_FILE" ] && spawn_helper=true
    [ "$transcript_path" -nt "$ACTIVITY_SEEN_FILE" ] && spawn_helper=true
    if [ "$cached_act_next" -gt 0 ] 2>/dev/null && [ "$NOW_EPOCH" -ge "$cached_act_next" ]; then spawn_helper=true; fi

    if [ "$spawn_helper" = "true" ]; then
      # Spawn helper in background (non-blocking); the same subshell sweeps
      # per-session caches (and their .seen markers) older than a day so they
      # never accumulate. The sweep runs on ~1 in 37 refreshes, so the find fork
      # is rare and the helper subshell stays cheap.
      ( if [ $(( NOW_EPOCH % 37 )) -eq 0 ]; then
          find "$SCRIPT_DIR" -maxdepth 1 -name '.statusline-activity-cache.*' -mmin +1440 -delete 2>/dev/null
        fi
        if [ "$activity_colour" = "true" ]; then
          node "$HELPER_SCRIPT" "$transcript_path" "$ACTIVITY_CACHE_FILE" --colour 2>/dev/null
        else
          node "$HELPER_SCRIPT" "$transcript_path" "$ACTIVITY_CACHE_FILE" 2>/dev/null
        fi ) >/dev/null 2>&1 </dev/null &   # fully detached: must not hold the render's stdout pipe open
      : > "$ACTIVITY_SEEN_FILE" 2>/dev/null || true   # mark spawn time for the -nt gate
    elif [ -n "$cached_act_json" ]; then
      # Idle: nothing to recompute. Keep the cached line "fresh" by re-stamping
      # its timestamp WITHOUT a Node spawn (fork-free redirect), so the existing
      # staleness fade / TTL behave exactly as when the helper ran every render —
      # the visible line is identical, minus the cost.
      printf '%s %s\n' "$NOW_EPOCH" "$cached_act_json" > "$ACTIVITY_CACHE_FILE" 2>/dev/null || true
      cached_act_ts="$NOW_EPOCH"
    fi

    # ── Display the cached line (behaviour unchanged) ─────────
    # Expire after activity_ttl_seconds. The default (120) stays comfortably
    # above typical refreshInterval values so line 2 survives idle timer
    # refreshes while a long subagent or workflow is running.
    case "$activity_ttl_seconds" in ''|*[!0-9]*) activity_ttl_seconds=120 ;; esac
    if [ "$cached_act_ts" != 0 ] && [ $(( NOW_EPOCH - cached_act_ts )) -le "$activity_ttl_seconds" ] 2>/dev/null; then
      # Extract "activity" value from simple JSON {"activity":"...","next":N},
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

# ── Phase 2: OAuth usage API (fallback + scoped-limit source) ─
# Runs when stdin lacked rate limits (full fallback for the 5h/7d numbers,
# older Claude Code versions), OR when the model-scoped weekly swap needs the
# limits[] array that Claude Code does not forward on stdin (usage_scoped,
# default on). In the scoped-only case the stdin 5h/7d numbers are never
# overwritten — the cache is read solely for the weekly_scoped entry.
usage_wk_scoped="" usage_wk_scoped_resets="" usage_wk_scoped_model=""
scoped_stale=false
oauth_wanted=false
if [ "$stdin_usage" = "false" ]; then
  if [ "$show_usage_5h" = "true" ] || [ "$show_usage_7d" = "true" ]; then
    oauth_wanted=true
  fi
elif [ "$usage_scoped" = "true" ] && [ "$show_usage_7d" = "true" ]; then
  oauth_wanted=true
fi
if [ "$oauth_wanted" = "true" ]; then

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
  # No credentials also backs off (30-min cap) so a token-less machine isn't
  # re-spawning a doomed fetch subshell on every render.
  token=$(fetch_usage_token) || { usage_backoff_increase; return 1; }
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

# Refresh cache if stale or missing (segment gating already done above via
# oauth_wanted). Runs in a background subshell so it never blocks the statusline.
  needs_fetch=false
  usage_stale=false
  cache_age=0
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
    # Mark stale if cache is older than twice the base interval. The 5h/7d
    # suffix only applies when the numbers came from this cache (OAuth path);
    # stdin numbers are real-time and must never inherit cache staleness.
    if [ "$cache_age" -gt $(( usage_cache_seconds * 2 )) ] 2>/dev/null; then
      [ "$stdin_usage" = "false" ] && usage_stale=true
      scoped_stale=true
    fi
  fi
  if [ "$needs_fetch" = "true" ]; then
    ( fetch_usage_data 2>/dev/null ) >/dev/null 2>&1 </dev/null &   # fully detached: must not hold the render's stdout pipe open
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
      # 5h/7d numbers only on the fallback path — stdin values are real-time
      # and preferred, never overwritten from a (up to 10-min-old) cache.
      if [ "$stdin_usage" = "false" ]; then
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
      # Model-scoped weekly limit — the "Fable"/"Opus" row on claude.ai. Only
      # present in the OAuth payload's limits[] array as a weekly_scoped entry:
      #   {"kind":"weekly_scoped",…,"percent":36,"resets_at":"…",
      #    "scope":{"model":{"id":…,"display_name":"Fable"},…},…}
      # percent, resets_at AND the model display_name all sit before the first
      # close-brace (the inner model object's), so one [^}]* capture reaches
      # them; a reordered payload just misses fields and fails silent (no swap).
      # First weekly_scoped entry wins. A staleness ceiling (6× the refresh
      # interval, ≈1h default) keeps a dead cache from swapping the bar onto
      # ancient numbers — beyond it the plain all-models bar stands.
      if [ "$usage_scoped" = "true" ] && [ "$show_usage_7d" = "true" ] \
         && [ "$cache_age" -le $(( usage_cache_seconds * 6 )) ] 2>/dev/null; then
        ws_pattern='"kind"[[:space:]]*:[[:space:]]*"weekly_scoped"([^}]*)'
        if [[ $usage_json =~ $ws_pattern ]]; then
          ws_block="${BASH_REMATCH[1]}"
          extract_num_from "$ws_block" "percent"; usage_wk_scoped=$REPLY
          extract_from "$ws_block" "resets_at"; usage_wk_scoped_resets=$REPLY
          extract_from "$ws_block" "display_name"; usage_wk_scoped_model=$REPLY
        fi
      fi
    fi
  fi

fi  # end OAuth phase (fallback and/or scoped-limit source)

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

# Burn-rate forecast: project when the limit will be hit at the CURRENT rate.
# Returns a short "time to limit" duration in REPLY (e.g. "1h20m") only when
# usage is running ahead of an even pace — i.e. on track to reach 100% BEFORE
# the window resets; returns non-zero / empty otherwise (you'll reset first, so
# the plain countdown is the useful label). Pure integer arithmetic, no fork:
# it reuses the same window maths as the pacing marker (used% per elapsed-second
# extrapolated to 100%). The 2-minute elapsed floor avoids jumpy forecasts from
# a tiny early-window sample.
# Usage: calc_forecast "$resets_at" "$window_secs" "$used_pct"; label=$REPLY
calc_forecast() {
  local resets_at="$1" window_secs="$2" used_pct="$3"
  local reset_ts start_ts elapsed time_to_reset secs dd hh mm
  REPLY=""
  case "$used_pct" in ''|*[!0-9]*) return 1 ;; esac
  [ "$used_pct" -le 0 ] && return 1
  iso_to_epoch "$resets_at" || return 1
  reset_ts=$REPLY
  time_to_reset=$(( reset_ts - NOW_EPOCH ))
  [ "$time_to_reset" -le 0 ] && return 1
  start_ts=$(( reset_ts - window_secs ))
  elapsed=$(( NOW_EPOCH - start_ts ))
  [ "$elapsed" -lt 120 ] && return 1
  [ "$elapsed" -gt "$window_secs" ] && elapsed=$window_secs
  if [ "$used_pct" -ge 100 ]; then REPLY="now"; return 0; fi
  # Seconds to reach 100% at the current burn rate: (100-used)*elapsed/used.
  secs=$(( (100 - used_pct) * elapsed / used_pct ))
  # Only a forecast when you'd hit the limit before the window resets (over pace).
  [ "$secs" -ge "$time_to_reset" ] && return 1
  dd=$(( secs / 86400 )); hh=$(( (secs % 86400) / 3600 )); mm=$(( (secs % 3600) / 60 ))
  if   [ "$dd" -gt 0 ]; then REPLY="${dd}d${hh}h"
  elif [ "$hh" -gt 0 ]; then REPLY="${hh}h${mm}m"
  elif [ "$mm" -gt 0 ]; then REPLY="${mm}m"
  else REPLY="<1m"; fi
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

  # Opt-in gradient: interpolate a distinct colour per filled cell across four
  # colour stops, so a wide bar shows a smooth ramp instead of bands. Truecolour
  # per cell; nearest-256 in fallback. `bar_gradient=true` uses the theme's ramp
  # (RAMP_HEX); `bar_gradient=heat` uses a fixed green->yellow->orange->red ramp
  # regardless of theme. No-op (plain █) under mono/NO_COLOR (CLR_RESET empty).
  local grad=false stops="" r0 g0 b0 r1 g1 b1 r2 g2 b2 r3 g3 b3
  case "${bar_gradient:-false}" in
    heat) [ -n "$CLR_RESET" ] && stops="2ecc40 ffdc00 ff851b ff4136" ;;
    true) stops="${RAMP_HEX:-}" ;;
  esac
  if [ -n "$stops" ]; then
    grad=true
    local h0 h1 h2 h3 _rest
    h0="${stops%% *}"; _rest="${stops#* }"
    h1="${_rest%% *}"; _rest="${_rest#* }"
    h2="${_rest%% *}"; h3="${_rest##* }"
    r0=$((16#${h0:0:2})) g0=$((16#${h0:2:2})) b0=$((16#${h0:4:2}))
    r1=$((16#${h1:0:2})) g1=$((16#${h1:2:2})) b1=$((16#${h1:4:2}))
    r2=$((16#${h2:0:2})) g2=$((16#${h2:2:2})) b2=$((16#${h2:4:2}))
    r3=$((16#${h3:0:2})) g3=$((16#${h3:2:2})) b3=$((16#${h3:4:2}))
  fi

  local bar="${colour}" i pos seg frac cr cg cb ri gi bi cell
  for (( i=0; i<width; i++ )); do
    if [ "$i" -eq "$target_pos" ]; then
      bar+="${CLR_PACE}│${colour}"
    elif [ "$i" -lt "$filled" ]; then
      if [ "$grad" = "true" ]; then
        # Position along the 4 stops (0..3000), then lerp the bracketing pair.
        if [ "$width" -le 1 ]; then pos=0; else pos=$(( i * 3000 / (width - 1) )); fi
        seg=$(( pos / 1000 )); frac=$(( pos % 1000 ))
        case "$seg" in
          0) cr=$(( r0 + (r1-r0)*frac/1000 )) cg=$(( g0 + (g1-g0)*frac/1000 )) cb=$(( b0 + (b1-b0)*frac/1000 )) ;;
          1) cr=$(( r1 + (r2-r1)*frac/1000 )) cg=$(( g1 + (g2-g1)*frac/1000 )) cb=$(( b1 + (b2-b1)*frac/1000 )) ;;
          2) cr=$(( r2 + (r3-r2)*frac/1000 )) cg=$(( g2 + (g3-g2)*frac/1000 )) cb=$(( b2 + (b3-b2)*frac/1000 )) ;;
          *) cr=$r3 cg=$g3 cb=$b3 ;;
        esac
        if [ "$TRUECOLOR" = "1" ]; then
          cell="${ESC_CH}[38;2;${cr};${cg};${cb}m"
        else
          cube_index "$cr"; ri=$REPLY; cube_index "$cg"; gi=$REPLY; cube_index "$cb"; bi=$REPLY
          cell="${ESC_CH}[38;5;$(( 16 + 36*ri + 6*gi + bi ))m"
        fi
        bar+="${cell}█"
      else
        bar+="█"
      fi
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

# Helper: add a segment with priority, optional group, and optional layout name
# Usage: add_seg "content" priority ["group_name"] ["seg_name"]
# seg_name is the stable token the layout config addresses the segment by.
add_seg() {
  seg_vals[$seg_idx]="$1"
  seg_pris[$seg_idx]="$2"
  seg_groups[$seg_idx]="${3:-}"
  seg_names[$seg_idx]="${4:-}"
  seg_idx=$((seg_idx + 1))
}

# REPLY = index of the added segment named $1, or -1 if absent (i.e. its
# show_* flag is false, so it was never added). Fork-free linear scan over the
# ~20 segments. This is how a layout token resolves to a built segment, and it
# makes "render iff enabled AND placed" fall out for free.
seg_index_by_name() {
  local n="$1" i=0
  while [ "$i" -lt "$seg_idx" ]; do
    [ "${seg_names[$i]}" = "$n" ] && { REPLY=$i; return 0; }
    i=$((i + 1))
  done
  REPLY=-1
}

# Session start placeholder — before first API response, fields are null/empty.
# Plain ${CLR_DIM}: apply_theme always sets it, and the mono/NO_COLOR theme
# sets it empty on purpose (a :-fallback here would leak \033[2m under NO_COLOR)
if [ -z "$model" ] && [ -z "$used" ]; then
  printf '%s' "${CLR_DIM}Starting...${CLR_RESET}"
  exit 0
fi

# Directory and Branch — two separately-addressable segments (both priority 1).
# When the layout places them adjacent (the default), the assembler joins them
# with the " on " connector and NO separator, reproducing the pre-2.19 combined
# "path on <icon>branch" exactly. dir has a full + basename form (the latter
# used by dir_style=basename, and by dir_style=auto when the line overflows).
# branch has an attached form (" on <icon>branch", emitted right after dir) and
# a standalone form (emitted when branch is placed alone or away from dir).
dir_seg_full="" dir_seg_base=""
if [ "$show_directory" = "true" ]; then
  dir_seg_full="${CLR_DIR}${ICON_DIR}${short_cwd}${CLR_RESET}"
  # Last path component, handling both / and \ separators (Windows cwd).
  dir_base="${short_cwd##*/}"; dir_base="${dir_base##*\\}"
  [ -z "$dir_base" ] && dir_base="$short_cwd"
  dir_seg_base="${CLR_DIR}${ICON_DIR}${dir_base}${CLR_RESET}"
fi
branch_seg_alone="" branch_seg_attached="" branch_attached_w=0
if [ "$show_branch" = "true" ] && [ -n "$branch" ]; then
  branch_seg_attached="${CLR_BRANCH} on ${ICON_BRANCH}${branch}${CLR_RESET}"
  branch_seg_alone="${CLR_BRANCH}${ICON_BRANCH}${branch}${CLR_RESET}"
  visible_width "$branch_seg_attached"; branch_attached_w=$REPLY
fi
if [ -n "$dir_seg_full" ]; then
  add_seg "$dir_seg_full" 1 "" "dir"; dir_seg_idx=$(( seg_idx - 1 ))
fi
if [ -n "$branch_seg_alone" ]; then
  add_seg "$branch_seg_alone" 1 "" "branch"; branch_seg_idx=$(( seg_idx - 1 ))
fi

# Vim mode indicator (priority 3)
if [ "$show_vim_mode" = "true" ]; then
  extract_block "$input" "vim"; vim_block=$REPLY
  if [ -n "$vim_block" ]; then
    extract_from "$vim_block" "mode"; vim_mode=$REPLY
    sanitize "$vim_mode"; vim_mode=$REPLY
    [ -n "$vim_mode" ] && add_seg "${CLR_INFO}${vim_mode}${CLR_RESET}" 3 "" "vim"
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
  add_seg "${model_clr}${model_icon}${model:-?}${CLR_RESET}" 3 "ctx" "model"
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
      add_seg "${CLR_MODEL}${agent_icon}${agent_name}${CLR_RESET}" 3 "" "agent"
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
      add_seg "${CLR_INFO}eff:${effort_level}${CLR_RESET}" 5 "" "effort"
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
    add_seg "${CLR_WARN}${fast_icon}fast${CLR_RESET}" 4 "" "fast_mode"
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
  add_seg "${warn_prefix}${progress_bar} ${bar_clr}${pct_int}%${ctx_suffix}${CLR_RESET}" 2 "ctx" "context"
fi

# Token counts (priority 5) — reuses $cw_block from context window extraction above
if [ "$show_tokens" = "true" ]; then
  if [ -n "$cw_block" ]; then
    extract_num_from "$cw_block" "total_input_tokens"; tok_in=$REPLY
    extract_num_from "$cw_block" "total_output_tokens"; tok_out=$REPLY
    tok_in_k=$(( ${tok_in:-0} / 1000 ))
    tok_out_k=$(( ${tok_out:-0} / 1000 ))
    if [ "$auto_hide" != "true" ] || [ "$tok_in_k" -gt 0 ] || [ "$tok_out_k" -gt 0 ]; then
      add_seg "${CLR_INFO}${tok_in_k}k in ${tok_out_k}k out${CLR_RESET}" 5 "" "tokens"
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
    # Burn-rate forecast: when on track to hit the limit before reset, swap the
    # countdown for a "▲ time-to-limit" warning (the more actionable number).
    if [ "${usage_forecast:-true}" = "true" ] && calc_forecast "$usage_5h_resets" $((5 * 3600)) "$u5_int" && [ -n "$REPLY" ]; then
      u5_label="(▲${REPLY})"
    fi
  fi
  build_progress_bar "$u5_int" "$u5_target"; u5_bar_output="$REPLY_COLOUR"$'\n'"$REPLY"
  u5_bar_clr="${u5_bar_output%%$'\n'*}"
  u5_bar="${u5_bar_output#*$'\n'}"
  add_seg "5hr${u5_label:+ ${u5_label}} ${u5_bar} ${u5_bar_clr}${u5_int}%${CLR_RESET}${usage_stale_suffix}" 3 "usage" "usage_5h"
fi

# Weekly usage limit (priority 3)
if [ "$show_usage_7d" = "true" ] && [ -n "$usage_7d" ]; then
  u7_int="${usage_7d%%.*}"
  u7_resets="$usage_7d_resets"
  u7_prefix="wk"
  u7_suffix="$usage_stale_suffix"
  # Model-scoped weekly swap (usage_scoped, default on): when a per-model
  # weekly limit is running HIGHER than the all-models one, it is the limit
  # that will actually throttle you — show it instead, with the model named in
  # the prefix ("wk:Fable"). Everything downstream (pacing marker, countdown,
  # burn-rate forecast) computes on the swapped numbers. Same segment name and
  # slot, so layouts/truncation are unaffected. Equal or lower scoped usage
  # keeps the plain all-models bar.
  if [ -n "$usage_wk_scoped" ]; then
    ws_int="${usage_wk_scoped%%.*}"
    if [ "$ws_int" -gt "$u7_int" ] 2>/dev/null; then
      u7_int="$ws_int"
      u7_resets="$usage_wk_scoped_resets"
      if [ -n "$usage_wk_scoped_model" ]; then
        sanitize "$usage_wk_scoped_model"; ws_name="${REPLY:0:12}"
        [ -n "$ws_name" ] && u7_prefix="wk:${ws_name}"
      fi
      # Scoped data always comes from the cache; mark it when it's aged even
      # if the (stdin-fed) 5h bar is real-time.
      [ "$scoped_stale" = "true" ] && u7_suffix="~"
    fi
  fi
  u7_target=""
  u7_label=""
  if [ -n "$u7_resets" ]; then
    calc_pacing_target "$u7_resets" $((7 * 86400)) || true; u7_target=$REPLY
    u7_label_style="day"
    [ "$usage_label" = "countdown" ] && u7_label_style="countdown"
    format_reset_label "$u7_resets" "$u7_label_style" || true; u7_reset_label=$REPLY
    [ -n "$u7_reset_label" ] && u7_label="(${u7_reset_label})"
    if [ "${usage_forecast:-true}" = "true" ] && calc_forecast "$u7_resets" $((7 * 86400)) "$u7_int" && [ -n "$REPLY" ]; then
      u7_label="(▲${REPLY})"
    fi
  fi
  build_progress_bar "$u7_int" "$u7_target"; u7_bar_output="$REPLY_COLOUR"$'\n'"$REPLY"
  u7_bar_clr="${u7_bar_output%%$'\n'*}"
  u7_bar="${u7_bar_output#*$'\n'}"
  add_seg "${u7_prefix}${u7_label:+ ${u7_label}} ${u7_bar} ${u7_bar_clr}${u7_int}%${CLR_RESET}${u7_suffix}" 3 "usage" "usage_7d"
fi

# Lines changed (priority 5)
if [ "$show_lines_changed" = "true" ]; then
  added="${lines_added:-0}"
  removed="${lines_removed:-0}"
  added_int="${added%%.*}"
  removed_int="${removed%%.*}"
  if [ "$auto_hide" != "true" ] || [ "$added_int" -gt 0 ] || [ "$removed_int" -gt 0 ]; then
    add_seg "${ICON_LINES}${CLR_ADD}+${added_int}${CLR_RESET} ${CLR_DEL}-${removed_int}${CLR_RESET}" 5 "git" "lines_changed"
  fi
fi

# Dirty file count (priority 5)
if [ "$show_dirty_count" = "true" ] && [ -n "$dirty_count" ]; then
  if [ "$auto_hide" != "true" ] || [ "$dirty_count" -gt 0 ] 2>/dev/null; then
    dirty_icon=""
    [ "$use_icons" = "true" ] && dirty_icon="● "
    add_seg "${CLR_WARN}${dirty_icon}${dirty_count} dirty${CLR_RESET}" 5 "git" "dirty"
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
    [ -n "$ab_text" ] && add_seg "${CLR_INFO}${ab_text}${CLR_RESET}" 6 "git" "ahead_behind"
  fi
fi

# Stash count (priority 6)
if [ "$show_stash" = "true" ]; then
  sc="${stash_count:-0}"
  if [ "$auto_hide" != "true" ] || [ "$sc" -gt 0 ] 2>/dev/null; then
    stash_icon=""
    [ "$use_icons" = "true" ] && stash_icon="≡ "
    add_seg "${CLR_WARN}${stash_icon}stash:${sc}${CLR_RESET}" 6 "git" "stash"
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
          pr_text="${ESC_CH}]8;;${pr_url}${ESC_CH}\\${pr_text}${ESC_CH}]8;;${ESC_CH}\\"
        fi
      fi
      add_seg "${pr_clr}${pr_text}${CLR_RESET}" 6 "git" "pr"
    fi
  fi
fi

# Claude API status (priority 3) — shows ONLY when degraded. cs_ind/cs_ts were
# set by check_claude_status from the background-refreshed cache. The staleness
# ceiling (cache_seconds * 6 ≈ 30 min) drops a phantom outage after a long sleep
# or a sustained fetch failure; the tier floor (claude_status_min) suppresses
# the noisier minor/maintenance states out of the box.
if [ "$show_claude_status" = "true" ] && [ -n "$cs_ind" ] && [ "$cs_ind" != "none" ]; then
  case "$cs_ts" in ''|*[!0-9]*) cs_ts=0 ;; esac
  if [ "$cs_ts" -gt 0 ] && [ $(( NOW_EPOCH - cs_ts )) -le $(( claude_status_cache_seconds * 6 )) ]; then
    claude_status_rank "$cs_ind"; cs_rk=$REPLY
    case "$claude_status_min" in
      minor|maintenance) cs_floor=1 ;;
      critical)          cs_floor=3 ;;
      *)                 cs_floor=2 ;;   # 'major' (default)
    esac
    if [ "$cs_rk" -ge "$cs_floor" ]; then
      case "$cs_ind" in
        critical)    cs_clr="$CLR_DEL";  cs_g="●"; cs_t="Claude: critical outage" ;;
        major)       cs_clr="$CLR_DEL";  cs_g="●"; cs_t="Claude: major outage" ;;
        minor)       cs_clr="$CLR_WARN"; cs_g="▲"; cs_t="Claude: degraded" ;;
        maintenance) cs_clr="$CLR_INFO"; cs_g="◷"; cs_t="Claude: maintenance" ;;
      esac
      cs_seg_text="$cs_t"
      [ "$use_icons" = "true" ] && cs_seg_text="${cs_g} ${cs_t}"
      # Fixed, trusted literal URL — trivially satisfies the PR segment's
      # OSC 8 allowlist; reuse the same hyperlink form, gated on pr_link.
      if [ "$pr_link" = "true" ]; then
        cs_seg_text="${ESC_CH}]8;;https://status.claude.com${ESC_CH}\\${cs_seg_text}${ESC_CH}]8;;${ESC_CH}\\"
      fi
      add_seg "${cs_clr}${cs_seg_text}${CLR_RESET}" 3 "" "claude_status"
    fi
  fi
fi

# Session duration (priority 7)
if [ "$show_duration" = "true" ] && [ -n "$duration_ms" ] && [ "$duration_ms" != "0" ]; then
  total_secs=$(( ${duration_ms%%.*} / 1000 ))
  hours=$(( total_secs / 3600 ))
  mins=$(( (total_secs % 3600) / 60 ))
  dur_icon="$ICON_DURATION"

  dur_text=""
  if [ "$hours" -gt 0 ]; then
    dur_text="${CLR_INFO}${dur_icon}${hours}h${mins}m${CLR_RESET}"
  elif [ "$mins" -gt 0 ]; then
    dur_text="${CLR_INFO}${dur_icon}${mins}m${CLR_RESET}"
  elif [ "$auto_hide" != "true" ]; then
    dur_text="${CLR_INFO}${dur_icon}0m${CLR_RESET}"
  fi
  [ -n "$dur_text" ] && add_seg "$dur_text" 7 "session" "duration"
fi

# Worktree indicator (priority 8)
if [ "$show_worktree" = "true" ] && [ -n "$worktree" ]; then
  wt_icon=""
  [ "$use_icons" = "true" ] && wt_icon="⊞ "
  add_seg "${CLR_BRANCH}${wt_icon}${worktree}${CLR_RESET}" 8 "" "worktree"
fi

# Round a non-negative plain decimal to integer cents — pure bash, NO fork.
# Uses `printf -v` (a bash builtin since 3.1, so it forks nothing) for the same
# rounding the old `awk … c*100 | printf %.0f` did, then derives the integer
# from the "D.DD" form by splitting on '.'. total_cost/cost_rate come from
# extract_num and are valid decimals. Result in REPLY.
to_cents() {
  local v="$1" fmt
  printf -v fmt '%.2f' "$v" 2>/dev/null || { REPLY=0; return; }
  REPLY=$(( 10#${fmt%.*} * 100 + 10#${fmt#*.} ))
}

# Session cost (priority 4)
if [ "$show_cost" = "true" ] && [ -n "$total_cost" ]; then
  cost_is_zero=false
  case "$total_cost" in 0|0.0|0.00|0.000) cost_is_zero=true ;; esac
  if [ "$auto_hide" != "true" ] || [ "$cost_is_zero" = "false" ]; then
    printf -v cost_fmt '%.2f' "$total_cost" 2>/dev/null || cost_fmt="$total_cost"
    # Colour by cost: green < $1, yellow $1-$5, red $5+. Integer cents in pure
    # bash (no awk/printf-subshell forks on the render hot path).
    to_cents "$total_cost"; cost_cents=$REPLY
    if [ "${cost_cents:-0}" -ge 500 ] 2>/dev/null; then
      cost_clr="$CLR_BAR_HIGH"
    elif [ "${cost_cents:-0}" -ge 100 ] 2>/dev/null; then
      cost_clr="$CLR_WARN"
    else
      cost_clr="$CLR_ADD"
    fi
    add_seg "${cost_clr}\$${cost_fmt}${CLR_RESET}" 4 "session" "cost"
  fi
fi

# Cost rate (priority 4)
if [ "$show_cost_rate" = "true" ] && [ -n "$total_cost" ] && [ -n "$duration_ms" ]; then
  dur_int="${duration_ms%%.*}"
  if [ "$dur_int" -ge 60000 ] 2>/dev/null; then
    # $/hr = total_cost * 3600000 / dur_ms, computed in integer cents (no fork):
    # rate_cents = round(cost_cents * 3600000 / dur_int); dur_int >= 60000 here.
    to_cents "$total_cost"; tcents=$REPLY
    rate_cents=$(( (tcents * 3600000 + dur_int / 2) / dur_int ))
    rate_dollars=$(( rate_cents / 100 )); rate_part=$(( rate_cents % 100 ))
    if [ "$rate_part" -lt 10 ]; then cost_rate="${rate_dollars}.0${rate_part}"; else cost_rate="${rate_dollars}.${rate_part}"; fi
    if [ -n "$cost_rate" ]; then
      rate_is_zero=false
      case "$cost_rate" in 0.00) rate_is_zero=true ;; esac
      if [ "$auto_hide" != "true" ] || [ "$rate_is_zero" = "false" ]; then
        if [ "${rate_cents:-0}" -ge 500 ] 2>/dev/null; then
          rate_clr="$CLR_BAR_HIGH"
        elif [ "${rate_cents:-0}" -ge 100 ] 2>/dev/null; then
          rate_clr="$CLR_WARN"
        else
          rate_clr="$CLR_ADD"
        fi
        add_seg "${rate_clr}\$${cost_rate}/hr${CLR_RESET}" 4 "session" "cost_rate"
      fi
    fi
  fi
fi

# Update notification (priority 9 — lowest). Shows the new version and, when
# it is a clean version string, wraps it in an OSC 8 hyperlink to that
# release's notes (same mechanism as the PR segment; honours pr_link).
if [ -n "$update_available" ]; then
  case "$update_available" in
    ''|*[!0-9.]*) update_ver="" ;;   # not a clean version — show generic text
    *)            update_ver="$update_available" ;;
  esac
  if [ -n "$update_ver" ]; then
    if [ "$use_icons" = "true" ]; then update_text="↑ ${update_ver}"; else update_text="update ${update_ver}"; fi
    if [ "$pr_link" = "true" ]; then
      update_url="https://github.com/briansmith80/claude-code-status-bar/releases/tag/v${update_ver}"
      update_text="${ESC_CH}]8;;${update_url}${ESC_CH}\\${update_text}${ESC_CH}]8;;${ESC_CH}\\"
    fi
  elif [ "$use_icons" = "true" ]; then
    update_text="↑ update available"
  else
    update_text="update available"
  fi
  add_seg "${CLR_ADD}${update_text}${CLR_RESET}" 9 "" "update"
fi

# ── Terminal width + responsive directory ────────────────────
# Detect the usable width once (shared by dir_style=auto and truncation), then
# collapse the directory to its basename for dir_style=basename, or for
# dir_style=auto when the full line would overflow that width.
term_width=""
if [ "$dir_style" = "auto" ] || [ "$enable_truncation" = "true" ]; then
  if [ -n "$max_width" ]; then
    term_width="$max_width"
  else
    # Claude Code >= 2.1.153 sets COLUMNS for statusline commands; prefer it
    # because tput cols is unreliable when output is captured (no tty).
    term_width="${COLUMNS:-}"
    [ -z "$term_width" ] && { term_width=$(tput cols 2>/dev/null) || true; }
    [ -z "$term_width" ] && term_width=120
  fi
fi
if [ -n "${dir_seg_idx:-}" ] && [ "$dir_style" = "basename" ]; then
  seg_vals[$dir_seg_idx]="$dir_seg_base"
fi

# Pre-compute every segment's visible width once (reused by the per-line
# auto-collapse and truncation below). Only needed in a width-aware mode.
if [ "$dir_style" = "auto" ] || [ "$enable_truncation" = "true" ]; then
  for (( i=0; i<seg_idx; i++ )); do
    visible_width "${seg_vals[$i]}"; seg_widths[$i]=$REPLY
  done
fi

# ── Per-line assembly ────────────────────────────────────────
# Assemble one line from a plan (space-separated segment indices) into REPLY.
# Scoped to THIS line, it applies: the dir auto-collapse (to basename on
# overflow), priority truncation (drop the highest priority-NUMBER segment
# until it fits term_width), use_groups bracketing (closed at end-of-line), the
# "  " separator, and the dir->branch connector — branch right after dir uses
# the attached " on <icon>branch" form with no separator, reproducing the
# pre-2.19 combined segment exactly. The connector's extra width is accounted
# for in both width passes via branch_attached_w (replaces the old forking
# calc_total_width — totals are summed inline, REPLY-convention friendly).
assemble_line() {
  local plan="$1"
  set -- $plan
  local cnt=$# idxs ix k prev_idx total f
  [ "$cnt" -eq 0 ] && { REPLY=""; return 0; }
  idxs=( "$@" )

  # (1) dir auto-collapse, decided against THIS line's width.
  if [ "$dir_style" = "auto" ] && [ -n "${dir_seg_idx:-}" ]; then
    local has_dir=0
    total=0; f=1; prev_idx=-1
    for ix in "${idxs[@]}"; do
      [ "$ix" = "$dir_seg_idx" ] && has_dir=1
      if [ "$ix" = "${branch_seg_idx:-_}" ] && [ "$prev_idx" = "$dir_seg_idx" ]; then
        total=$(( total + branch_attached_w ))
      else
        [ "$f" = "1" ] && f=0 || total=$(( total + 2 ))
        total=$(( total + ${seg_widths[$ix]:-0} ))
      fi
      prev_idx="$ix"
    done
    if [ "$has_dir" = "1" ] && [ -n "$term_width" ] && [ "$total" -gt "$term_width" ] 2>/dev/null; then
      seg_vals[$dir_seg_idx]="$dir_seg_base"
      visible_width "$dir_seg_base"; seg_widths[$dir_seg_idx]=$REPLY
    fi
  fi

  # (2) priority truncation, scoped to THIS line.
  local af=()
  for (( k=0; k<cnt; k++ )); do af[$k]=1; done
  if [ "$enable_truncation" = "true" ]; then
    while :; do
      total=0; f=1; prev_idx=-1
      for (( k=0; k<cnt; k++ )); do
        [ "${af[$k]}" = "0" ] && continue
        ix="${idxs[$k]}"
        if [ "$ix" = "${branch_seg_idx:-_}" ] && [ "$prev_idx" = "$dir_seg_idx" ]; then
          total=$(( total + branch_attached_w ))
        else
          [ "$f" = "1" ] && f=0 || total=$(( total + 2 ))
          total=$(( total + ${seg_widths[$ix]:-0} ))
        fi
        prev_idx="$ix"
      done
      [ "$total" -le "$term_width" ] 2>/dev/null && break
      local worst=-1 worstp=0
      for (( k=0; k<cnt; k++ )); do
        [ "${af[$k]}" = "0" ] && continue
        if [ "${seg_pris[${idxs[$k]}]}" -gt "$worstp" ] 2>/dev/null; then
          worstp="${seg_pris[${idxs[$k]}]}"; worst=$k
        fi
      done
      [ "$worst" = "-1" ] && break
      af[$worst]=0
    done
  fi

  # (3) assemble: separators, optional group brackets, dir->branch connector.
  local out="" first_seg=1 current_group="" group_has_content=false prev_name=""
  local seg_sep="  " nm val this_group
  for (( k=0; k<cnt; k++ )); do
    [ "$enable_truncation" = "true" ] && [ "${af[$k]}" = "0" ] && { prev_name=""; continue; }
    ix="${idxs[$k]}"
    nm="${seg_names[$ix]}"
    val="${seg_vals[$ix]}"
    if [ "$nm" = "branch" ] && [ "$prev_name" = "dir" ]; then
      out="${out}${branch_seg_attached}"; prev_name="branch"; continue
    fi
    this_group="${seg_groups[$ix]:-}"
    if [ "$use_groups" = "true" ] && [ -n "$this_group" ]; then
      if [ "$this_group" != "$current_group" ]; then
        [ -n "$current_group" ] && [ "$group_has_content" = "true" ] && out="${out}${group_close}"
        [ "$first_seg" != "1" ] && out="${out}${seg_sep}"
        first_seg=0
        out="${out}${group_open}"
        current_group="$this_group"; group_has_content=true
      else
        out="${out} "
      fi
    else
      if [ "$use_groups" = "true" ] && [ -n "$current_group" ] && [ "$group_has_content" = "true" ]; then
        out="${out}${group_close}"; current_group=""; group_has_content=false
      fi
      if [ "$first_seg" = "1" ]; then first_seg=0; else out="${out}${seg_sep}"; fi
    fi
    out="${out}${val}"; prev_name="$nm"
  done
  [ "$use_groups" = "true" ] && [ -n "$current_group" ] && [ "$group_has_content" = "true" ] && out="${out}${group_close}"
  REPLY="$out"
}

# ── Layout resolution ────────────────────────────────────────
# A preset expands to default per-line token strings; an explicitly set
# line1/line2/line3 (even empty) overrides the preset for that line. Tokens are
# individual segment names; 'activity' is the live line. classic line 1 is the
# sentinel __ALL__ (every segment in add order) so it tracks new segments and
# stays byte-identical to the pre-2.19 single bar.
resolve_layout_preset() {
  case "${1:-classic}" in
    three-line)
      lp1="vim model agent effort fast_mode context usage_5h usage_7d tokens duration claude_status cost cost_rate update"
      lp2="dir branch lines_changed dirty ahead_behind stash pr worktree"
      lp3="activity" ;;
    stacked)
      lp1="dir branch model context usage_5h usage_7d claude_status cost"
      lp2="lines_changed dirty ahead_behind stash pr duration worktree update"
      lp3="activity" ;;
    classic|*)
      lp1="__ALL__"; lp2="activity"; lp3="" ;;
  esac
}
resolve_layout_preset "${layout:-classic}"
# ${lineN+s}: distinguishes a user-set (even empty) line from an unset one.
if [ -n "${line1+s}" ]; then L1="$line1"; else L1="$lp1"; fi
if [ -n "${line2+s}" ]; then L2="$line2"; else L2="$lp2"; fi
if [ -n "${line3+s}" ]; then L3="$line3"; else L3="$lp3"; fi

# Parse one line's token string into REPLY (space-separated segment indices)
# and REPLY_ACT (1 if the activity token is present). De-dups across all lines
# via seg_placed[] / activity_placed (first occurrence wins). __ALL__ expands
# to every added segment in add order. Unknown/disabled tokens are skipped, so
# a typo is ignored and a show_*=false segment never appears.
parse_line() {
  local spec="$1" tok idx plan=""
  REPLY_ACT=0
  if [ "$spec" = "__ALL__" ]; then
    idx=0
    while [ "$idx" -lt "$seg_idx" ]; do
      if [ -z "${seg_placed[$idx]:-}" ]; then
        seg_placed[$idx]=1; plan="${plan}${plan:+ }${idx}"
      fi
      idx=$((idx + 1))
    done
    REPLY="$plan"; return 0
  fi
  for tok in $spec; do
    if [ "$tok" = "activity" ]; then
      [ "${activity_placed:-0}" = "1" ] && continue
      activity_placed=1; REPLY_ACT=1; continue
    fi
    seg_index_by_name "$tok"; idx=$REPLY
    [ "$idx" = "-1" ] && continue
    [ -n "${seg_placed[$idx]:-}" ] && continue
    seg_placed[$idx]=1; plan="${plan}${plan:+ }${idx}"
  done
  REPLY="$plan"
}
activity_placed=0
parse_line "$L1"; line1_plan="$REPLY"; line1_act="$REPLY_ACT"
parse_line "$L2"; line2_plan="$REPLY"; line2_act="$REPLY_ACT"
parse_line "$L3"; line3_plan="$REPLY"; line3_act="$REPLY_ACT"

# Never silently lose the update notice: if an update is available but the
# 'update' token wasn't placed, append it to the last line with metric content.
if [ -n "$update_available" ]; then
  seg_index_by_name "update"; upd_idx=$REPLY
  if [ "$upd_idx" != "-1" ] && [ -z "${seg_placed[$upd_idx]:-}" ]; then
    if   [ -n "$line3_plan" ]; then line3_plan="${line3_plan} ${upd_idx}"
    elif [ -n "$line2_plan" ]; then line2_plan="${line2_plan} ${upd_idx}"
    else line1_plan="${line1_plan}${line1_plan:+ }${upd_idx}"; fi
    seg_placed[$upd_idx]=1
  fi
fi

# ── Activity-line trimming ───────────────────────────────────
# Visible width of an activity string (in REPLY): colour tokens were
# substituted with raw SGR escape bytes, so strip that pattern before
# counting. Pure bash, fork-free, bash 3.2 safe.
activity_visible_width() {
  local s="$1" pat="${ESC_CH}\[[0-9;]*m"
  while [[ $s =~ $pat ]]; do s="${s//"${BASH_REMATCH[0]}"/}"; done
  REPLY=${#s}
}

# Trim $activity_line to a column budget ($1), returning the trimmed copy in
# REPLY (the original is left intact). Colour-aware: drop whole '  │  ' parts
# from the end until it fits — never cutting inside an escape sequence — then,
# once a part has been dropped, leave room for a dim ' …' marker; finally hard-
# cut if a single part is still too wide. A non-numeric or <=1 budget returns
# the line unchanged. With budget=COLUMNS this is byte-identical to the
# pre-2.19 line-2 trim.
trim_activity() {
  local limit="$1" line="${activity_line:-}"
  case "$limit" in
    ''|*[!0-9]*) REPLY="$line"; return 0 ;;
  esac
  if [ "$limit" -gt 1 ]; then
    if [ "${activity_has_colour:-false}" = "true" ]; then
      local act_dropped=false act_limit="$limit"
      while :; do
        activity_visible_width "$line"
        [ "$REPLY" -gt "$act_limit" ] || break
        case "$line" in
          *"  │  "*)
            line="${line%"  │  "*}"
            act_dropped=true
            act_limit=$(( limit - 2 ))
            ;;
          *) break ;;
        esac
      done
      [ "$act_dropped" = "true" ] && line="${line}${CLR_DIM//\\033/$ESC_CH} …"
      activity_visible_width "$line"
      if [ "$REPLY" -gt "$limit" ]; then
        local act_pat="${ESC_CH}\[[0-9;]*m"
        while [[ $line =~ $act_pat ]]; do line="${line//"${BASH_REMATCH[0]}"/}"; done
        line="${line:0:$(( limit - 1 ))}…"
      fi
    elif [ "${#line}" -gt "$limit" ]; then
      line="${line:0:$(( limit - 1 ))}…"
    fi
  fi
  REPLY="$line"
}

sl_profile "segments+render"

# ── Render ───────────────────────────────────────────────────
# Print each non-empty line; a newline separates printed lines (never trailing,
# never a blank row for an empty line — preserving the pre-2.19 "line 2 only
# when there's data" behaviour). Metric content prints with %b; the activity
# tail is untrusted transcript text and always prints with %s.
emitted=0
for ln in 1 2 3; do
  case "$ln" in
    1) line_plan="$line1_plan"; line_act="$line1_act" ;;
    2) line_plan="$line2_plan"; line_act="$line2_act" ;;
    3) line_plan="$line3_plan"; line_act="$line3_act" ;;
  esac

  metric=""
  [ -n "$line_plan" ] && { assemble_line "$line_plan"; metric="$REPLY"; }

  act_str=""
  if [ "$line_act" = "1" ] && [ -n "${activity_line:-}" ]; then
    if [ -z "$metric" ]; then
      # Activity alone on this line: trim to the full terminal width.
      trim_activity "${COLUMNS:-}"; act_str="$REPLY"
    else
      # Activity sharing a line with metrics: trim to the leftover budget.
      case "${COLUMNS:-}" in
        ''|*[!0-9]*) act_str="$activity_line" ;;
        *) visible_width "$metric"; budget=$(( COLUMNS - REPLY - 2 ))
           [ "$budget" -lt 1 ] && budget=1
           trim_activity "$budget"; act_str="$REPLY" ;;
      esac
    fi
  fi

  [ -z "$metric" ] && [ -z "$act_str" ] && continue
  [ "$emitted" -gt 0 ] && printf '\n'
  emitted=$(( emitted + 1 ))
  # Print with %s, NEVER %b: the script's own colours / OSC 8 links already
  # carry real ESC bytes (set at their source), so an untrusted field holding
  # the printable text "\033" (or "\e", "\x1b", ...) can never be decoded into
  # a live control sequence here. sanitize() strips any raw ESC bytes upstream.
  [ -n "$metric" ] && printf '%s' "$metric"
  if [ -n "$act_str" ]; then
    [ -n "$metric" ] && printf '%s' "  "
    printf '%s%s%s' "${CLR_DIM}" "${act_str}" "${CLR_RESET}"
  fi
done
