# Claude Code Status Bar — Project Guide

## What this is

A configurable status bar for Claude Code. Pure bash core with optional Node.js helper for live activity. Cross-platform (macOS, Linux, Windows/MSYS2).

## Architecture

```
VERSION                    # Single source of truth for version (bump ONLY this file for releases)
statusline-command.sh      # The runtime script — installed to ~/.claude/
statusline-helper.js       # Optional Node.js transcript parser — installed to ~/.claude/
statusline-subagent.js     # Optional Node.js subagent panel renderer — installed to ~/.claude/
install.sh                 # Installer/updater — downloads script + helpers + VERSION from GitHub
install.ps1                # Windows PowerShell installer/updater — native JSON settings merge
.claude-plugin/plugin.json # Plugin manifest for marketplace distribution
.claude-plugin/marketplace.json # Marketplace catalog (required by /plugin marketplace add)
commands/setup.md          # Slash command: /claude-code-status-bar:setup
commands/configure.md      # Slash command: /claude-code-status-bar:configure
docs/assets/               # README images (banner dark/light, terminal demo SVGs)
README.md                  # User-facing docs
```

### Installed files (at ~/.claude/)

| File | Purpose | Overwritten on update? |
|------|---------|----------------------|
| `statusline-command.sh` | The script Claude Code runs | Yes |
| `statusline-helper.js` | Node.js transcript parser (optional) | Yes |
| `statusline-subagent.js` | Node.js subagent panel renderer (optional) | Yes |
| `.statusline-version` | Local copy of VERSION | Yes |
| `statusline.conf` | User config overrides | **Never** |
| `.statusline-update-cache` | Update check cache (timestamp + version) | Cleared on update |
| `.statusline-usage-cache` | Usage API response cache (JSON) | Auto-refreshes every 10 min |
| `.statusline-activity-cache` | Transcript activity cache (JSON) | Auto-refreshes every call |
| `.statusline-transcript-cache/` | Parsed transcript cache (by SHA256) | Auto-invalidates on change |

## Key design decisions

- **No jq** — Uses bash regex (`BASH_REMATCH`) for JSON parsing. Windows/MSYS2 users don't have jq.
- **Bash 3.2 minimum** — Must work on stock macOS. No associative arrays, no `readarray`, no `${var,,}`.
- **Background update check** — Fetches VERSION from GitHub every 6h in a background subshell. Never blocks the status bar.
- **External config** — User overrides go in `statusline.conf`, sourced after defaults. Survives updates.
- **Single version source** — Only `VERSION` file needs bumping. Installer downloads it; script reads it at runtime.
- **Sanitize untrusted strings** — Branch names, paths, and worktree names are stripped of ANSI escapes before output.
- **Colour themes via CLR_* variables** — All ANSI codes use theme variables set by `apply_theme()`. Seven built-in themes: default, nord, dracula, solarized, mono, tokyo-night, catppuccin. Supports NO_COLOR standard.
- **Model tier coloring** — Model name colour varies by tier (Haiku=green, Sonnet=yellow, Opus=orange, Fable/Mythos=purple) via a case statement. Respects NO_COLOR and mono theme.
- **Auto-compact awareness** — Claude Code auto-compacts at (autocompact window - 33000) tokens and warns itself 20000 tokens earlier (constants extracted from CC 2.1.170; display-only, drift is cosmetic). The context bar carries a `│` marker at the compact point and `context_warn_threshold=auto` (default) fires `▲` within 20k tokens of it, using `total_input_tokens`. Resolution order mirrors CC: `CLAUDE_CODE_AUTO_COMPACT_WINDOW` env > settings.json `autoCompactWindow` > full window; `DISABLE_AUTO_COMPACT`/`DISABLE_COMPACT` remove the marker and fall back to a raw 80% rule. The `▲ 200k+` segment was retired in v2.6.0 (long-context premium pricing was abolished March 2026).
- **Array-based segments** — Segments are built into `seg_vals[]`/`seg_pris[]`/`seg_groups[]` arrays for truncation and grouping support.
- **set -e safety** — Git commands that may fail (e.g., `rev-list` with no upstream) use `|| fallback` pattern to prevent script death.
- **Usage limits: stdin-native + OAuth fallback** — Prefers `rate_limits.five_hour` and `rate_limits.seven_day` from stdin (CC >= 2.1, zero-cost, real-time). Falls back to OAuth API (`api.anthropic.com/api/oauth/usage`) for older CC versions. OAuth uses background subshell, Keychain/credentials.json, 10-min cache.
- **Live activity via transcript** — Optional Node.js helper (`statusline-helper.js`) parses Claude Code's JSONL transcript for tool calls, subagent status, and todo progress. Runs in background with a SHA256-keyed disk cache that stores the parse state plus a byte offset, so each run parses only newly appended lines (incremental). Completed/failed items age out of the display after 5 minutes; tool counts cover the whole session. Only activates when `transcript_path` is in stdin and Node.js is available.
- **Two-line layout** — Line 1 is the metrics bar. Line 2 shows live activity when available and only appears when there's data to show. Disable with `show_activity=false`.
- **Colourful activity line via tokens** — With `activity_colour=true` (default) the bash script passes `--colour` to the helper, which wraps segments in zero-width plain-text tokens (`{w}` warn, `{o}` ok, `{e}` err, `{i}` info, `{d}` back-to-dim, `{O}` completion flash, `{h1}`-`{h3}` elapsed heat, `{r0}`-`{r3}` todo gradient, `{s}` spinner slot). Tokens survive both sanitize layers; bash maps them to CLR_* theme constants AFTER sanitizing, substituting raw escape bytes, and prints line 2 with `%s` (never `%b`) so transcript-derived text can't decode into controls. The spinner frame comes from `NOW_EPOCH % 4` so it animates at the `refreshInterval` rate. Colours drop to all-dim when the cache is older than `activity_fresh_seconds` (45, stale-reads-as-stale) and under NO_COLOR/mono. The width trim is colour-aware: whole `  │  ` parts are dropped, never mid-escape cuts. Helper output without `--colour` stays byte-identical to pre-2.7 (version-skew safe both ways).
- **Per-session activity cache** — The activity cache is keyed by stdin `session_id` (`.statusline-activity-cache.<id8>`), so parallel sessions never clobber each other's line 2. Stale per-session caches are swept after 24h by the helper-spawn subshell; `--uninstall` removes them.
- **Subagent panel rows** — `statusline-subagent.js` implements Claude Code's `subagentStatusLine` protocol: stdin `{columns, tasks[]}` per ~5s tick, stdout one `{"id","content"}` JSON line per row. Renders status icon, elapsed, tokens, and a tok/s rate from `tokenSamples` (cumulative counts, one per tick, max 16). Errors exit silently so Claude Code keeps its default rows; `subagent_rows=false` in statusline.conf disables it. **Scope:** CC 2.1.170 only delegates Task-tool subagent rows (task type `local_agent`); workflow and background-task rows render through a separate panel path that ignores custom renderers, so they keep Claude Code's built-in style. Settings must carry quoted Windows-native paths (`node "C:/..."`): CC prefers Git Bash to spawn the command but falls back to PowerShell/cmd when it's missing, where node cannot resolve MSYS `/c/...` paths and fails silently. Both installers write that form and migrate their own older commands on re-run.
- **`usage_label` config** — Usage bar labels show the remaining time (`countdown`, default, e.g. `2h20m`) or the reset moment (`clock`). The default changed to `countdown` in v2.10.0. Countdown pairs well with the `refreshInterval` statusLine setting (CC re-runs the script on a timer) so the label stays fresh while idle.
- **Plugin marketplace** — `.claude-plugin/plugin.json` enables `/plugin install`. Slash commands for setup and configuration.
- **Pacing markers** — Progress bars support an optional `│` marker (CLR_PACE) showing where usage *should* be for even consumption across the window.
- **Token security** — OAuth tokens are passed to curl via `--config -` (stdin), not command-line args, so they're hidden from `ps`. wget uses `--max-redirect=0` to prevent token leakage on redirects. **Note:** the wget fallback still passes `--header` as a CLI argument (visible in `ps aux`). Curl is strongly preferred; wget is a last-resort fallback.
- **Shared helpers** — `http_get()` consolidates curl/wget fallback, `iso_to_epoch()` consolidates cross-platform date parsing. Avoids duplicated patterns.
- **`extract_block()` for nested JSON** — Extracts a JSON object block by key (content between `{ }`) to support nested structures like `vim`, `agent`, `workspace`, and `context_window`. Used by vim mode, agent name, token count, and workspace directory segments.
- **`umask 077`** — All cache/temp files are created with restrictive permissions (not world-readable).
- **`NOW_EPOCH` cached once** — A single `date +%s` call at startup is reused everywhere to minimise fork overhead.
- **REPLY return convention (hot path)** — Internal helpers (extract_*, sanitize, visible_width, build_progress_bar, format_reset_label, calc_pacing_target, iso_to_epoch) return via the `REPLY` global, never `$(fn)` command substitution: each substitution forks a subshell costing 15-25ms under MSYS, and ~50 ran per render before v2.8.0 (1286ms → 285ms on Windows). Keep new helpers on this convention. `REPLY` is safe because the script never uses bare `read`. `--benchmark` and `STATUSLINE_PROFILE=1` measure regressions.
- **Git via porcelain v2, two forks total** — One `rev-parse --git-dir --git-common-dir` (gate + stash-log location, worktree-correct) and one `status --porcelain=v2 --branch` (branch, ahead/behind, dirty count parsed in pure bash; entry count via line arithmetic). Stash count is a pure-bash line count of `logs/refs/stash`. Never add per-segment git calls.
- **`bar_width` config** — Progress bar width is configurable (default 10), used by `build_progress_bar()`.
- **`branch_max_length` config** — Long branch names are truncated with an ellipsis when set.

## Roadmap & Sprints

See [ROADMAP.md](ROADMAP.md) for the feature roadmap and competitive landscape.
See [SPRINTS.md](SPRINTS.md) for the validated sprint plan with dependency ordering and effort estimates.

Current milestone: **Sprint 4 (v2.1.0)** — Testing & CLI :white_check_mark: shipped. BATS scaffold (28 tests), three-platform CI matrix, and four new CLI flags (`--help`, `--version`, `--dump-config`, `--uninstall`) all landed. v2.1.1 followed with the README overhaul, the NO_COLOR/mono progress bar fix, and `.claude-plugin/marketplace.json`. v2.2.0 audited the bar against Claude Code 2.1.170 (Fable 5): Fable/Mythos purple tier colour, effort + fast-mode segments, rate-limit extraction scoped to the `rate_limits` block, ISO `resets_at` tolerance, and `$COLUMNS`-first width detection. v2.3.0 added countdown usage labels (`usage_label`), the PR segment, worktree fallback via `workspace.git_worktree`, and per-session activity caches. v2.4.0 overhauled the live activity line: incremental transcript parsing, 5-minute age-out of finished items, `✗` failure indicator, elapsed time on running tools, `activity_ttl_seconds`, and `$COLUMNS` trimming. v2.5.0 added the subagent panel renderer (`statusline-subagent.js`, wired via the `subagentStatusLine` setting). v2.6.0 rebuilt context warnings around Claude Code's real auto-compact maths (marker + `context_warn_threshold=auto`), retired `▲ 200k+` (premium pricing abolished March 2026), and added `install.ps1` for Windows. v2.6.1 hardened Windows installs (quoted Windows-native paths in settings.json, migration of older command formats on re-run) and corrected the subagent renderer docs to its real scope (Task-tool subagent rows only; Claude Code 2.1.170 draws workflow and background-task rows itself). v2.7.0 shipped the colourful activity line (token architecture, spinner, heat colours, completion flash, gradient todo bar, stale fade; 12 new BATS tests, suite now 81) plus ANSI-aware line-2 trimming and four long-standing portability/safety fixes. v2.8.0 (Sprint 5) was the Windows performance overhaul: REPLY return convention, porcelain-v2 git consolidation, pure-bash sanitize/width maths, fork-free countdown labels, `--benchmark` + `STATUSLINE_PROFILE`, and the first git-segment tests (suite 87); measured 1286ms → 285ms per render on Windows with byte-identical output. v2.9.0 (Sprint 6) added the clickable PR segment (OSC 8 hyperlink, strict https allowlist, `pr_link`), opt-in `activity_pulse`/`activity_scanner` effects (pure bash-side, no helper skew), and tag-driven release automation (`release.yml`: verify VERSION/plugin.json/CHANGELOG agree, publish from the changelog section); suite 93. v2.10.0 flipped the `usage_label` default from `clock` to `countdown` (the usage bars now show time-remaining out of the box; `usage_label=clock` opts back in), with the BATS default-case test updated and a new `clock` opt-out test. Next: re-evaluate against user feedback.

## How to release a new version

**IMPORTANT: Do not skip any of these steps.** Tags, GitHub releases, and the plugin manifest version have all been missed before — always update them alongside the version bump.

1. Bump `VERSION` file (e.g., `1.5.0`)
2. Update `CHANGELOG.md` with a new `[1.5.0] - YYYY-MM-DD` section
3. Bump `.claude-plugin/plugin.json` `"version"` to match `VERSION`
4. Update all docs: README.md, CLAUDE.md (current milestone), ROADMAP.md, SPRINTS.md
5. Commit everything: `git add -A && git commit -m "release: v1.5.0" && git push`
6. Create annotated tag: `git tag -a v1.5.0 -m "v1.5.0" && git push origin v1.5.0`
7. The tag push triggers `.github/workflows/release.yml` (since v2.9.0): it verifies VERSION, plugin.json, and CHANGELOG agree, extracts the CHANGELOG section, and publishes the GitHub release. Verify it succeeded with `gh run list --limit 1` and `gh release view v1.5.0`. (Manual fallback: `gh release create v1.5.0 --title "v1.5.0" --notes "..."`)
8. Copy files to local install: `cp statusline-command.sh ~/.claude/statusline-command.sh && cp statusline-helper.js ~/.claude/statusline-helper.js`

Users with the update check will see `↑ update available` within 6 hours.

## Testing

Test with old schema (backward compat):

```bash
echo '{"cwd":"/tmp","display_name":"Sonnet","used_percentage":60,"total_cost_usd":0.50}' | bash statusline-command.sh
```

Test with new nested schema (model, context_window):

```bash
echo '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":78,"context_window_size":200000},"total_cost_usd":2.50}' | bash statusline-command.sh
```

Test with stdin rate limits (no OAuth needed):

```bash
echo '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":65},"total_cost_usd":0.50,"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1743019200},"seven_day":{"used_percentage":71,"resets_at":1743278400}}}' | bash statusline-command.sh
```

Test with v1.4.0 fields (vim mode, agent, workspace, tokens):

```bash
echo '{"cwd":"/tmp","display_name":"Sonnet","used_percentage":60,"total_cost_usd":0.50,"vim":{"mode":"NORMAL"},"agent":{"name":"my-agent"},"workspace":{"current_dir":"/home/user/project"},"context_window":{"total_input_tokens":45000,"total_output_tokens":12000}}' | bash statusline-command.sh
```

Test compaction awareness (marker at 83% of a 200k window, ▲ within 20k tokens of the compact point):

```bash
echo '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":74,"context_window_size":200000,"total_input_tokens":148000}}' | bash statusline-command.sh
```

Test live activity (Node.js helper):

```bash
# Create a test transcript
cat > /tmp/test-transcript.jsonl << 'EOF'
{"timestamp":"2026-03-26T10:00:00Z","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/src/main.ts"}}]}}
{"timestamp":"2026-03-26T10:00:01Z","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}
{"timestamp":"2026-03-26T10:00:02Z","message":{"content":[{"type":"tool_use","id":"t2","name":"Edit","input":{"file_path":"/src/main.ts"}}]}}
EOF
# Pre-populate cache then test
node statusline-helper.js /tmp/test-transcript.jsonl ~/.claude/.statusline-activity-cache
echo '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":65},"total_cost_usd":0.50,"transcript_path":"/tmp/test-transcript.jsonl"}' | bash statusline-command.sh
```

Test update notification by writing a fake cache:

```bash
echo "$(date +%s) 9.9.9" > ~/.claude/.statusline-update-cache
```

Test config overrides:

```bash
echo "show_cost=false" > ~/.claude/statusline.conf
```

After testing, update your local install:

```bash
cp statusline-command.sh ~/.claude/statusline-command.sh
cp statusline-helper.js ~/.claude/statusline-helper.js
```

## Code conventions

- Bash with `set -e` — strict error handling
- Comments use `# ── Section ───` separator style
- Colour codes use `CLR_*` theme variables (not inline ANSI codes)
- Default palette: cyan=dir, magenta=branch, green/yellow/orange=model (tier-dependent), green=additions, red=removals, yellow=warnings/cost
- All git commands use `-c core.fsmonitor=false` to avoid filesystem monitoring overhead
- Fallback chains: curl > wget, node > python3 > python > manual instructions

## Common pitfalls

- **GitHub raw CDN caches aggressively** — After pushing VERSION, it can take 5+ minutes for `raw.githubusercontent.com` to serve the new content.
- **Local install gets stale** — After editing the repo's `statusline-command.sh`, remember to copy it to `~/.claude/` for your own status bar to update.
- **`set -e` in subshells** — Background update fetch runs in `( ) &`. If curl/wget fails inside, only the subshell dies (by design).
- **Usage API requires OAuth scopes** — The token must have `user:profile` scope. Tokens created via `claude setup-token` only have `user:inference` and won't work. Users need browser OAuth (quit all CC instances and restart).
- **`date` portability for pacing** — macOS uses `date -juf`, GNU/MSYS2 uses `date -ud`. The `format_reset_label()` and `calc_pacing_target()` functions handle both.
- **Do NOT use `read -r -d ''` to capture stdin** — It silently fails on MSYS2/Windows bash, producing an empty variable. Always use `input=$(cat)` instead. The fork cost is negligible compared to broken input on Windows.
- **`refreshInterval` below the script's runtime blanks the whole bar** — Claude Code aborts an in-flight statusLine run when the next one starts, and an aborted run clears `statusLineText`. Measure with `--benchmark`: since the v2.8.0 fork overhaul the script takes ~285ms on Windows (was 1.3-2.5s) and well under 100ms on macOS/Linux. Recommend `2`+ on Windows for load headroom, `1` elsewhere.
