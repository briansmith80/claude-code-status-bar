# Claude Code Status Bar — Project Guide

## What this is

A configurable status bar for Claude Code. Pure bash, no dependencies, cross-platform (macOS, Linux, Windows/MSYS2).

## Architecture

```
VERSION                    # Single source of truth for version (bump ONLY this file for releases)
statusline-command.sh      # The runtime script — installed to ~/.claude/
install.sh                 # Installer/updater — downloads script + VERSION from GitHub
README.md                  # User-facing docs
```

### Installed files (at ~/.claude/)

| File | Purpose | Overwritten on update? |
|------|---------|----------------------|
| `statusline-command.sh` | The script Claude Code runs | Yes |
| `.statusline-version` | Local copy of VERSION | Yes |
| `statusline.conf` | User config overrides | **Never** |
| `.statusline-update-cache` | Update check cache (timestamp + version) | Cleared on update |
| `.statusline-usage-cache` | Usage API response cache (JSON) | Auto-refreshes every 10 min |

## Key design decisions

- **No jq** — Uses bash regex (`BASH_REMATCH`) for JSON parsing. Windows/MSYS2 users don't have jq.
- **Bash 3.2 minimum** — Must work on stock macOS. No associative arrays, no `readarray`, no `${var,,}`.
- **Background update check** — Fetches VERSION from GitHub every 6h in a background subshell. Never blocks the status bar.
- **External config** — User overrides go in `statusline.conf`, sourced after defaults. Survives updates.
- **Single version source** — Only `VERSION` file needs bumping. Installer downloads it; script reads it at runtime.
- **Sanitize untrusted strings** — Branch names, paths, and worktree names are stripped of ANSI escapes before output.
- **Colour themes via CLR_* variables** — All ANSI codes use theme variables set by `apply_theme()`. Seven built-in themes: default, nord, dracula, solarized, mono, tokyo-night, catppuccin. Supports NO_COLOR standard.
- **Model tier coloring** — Model name colour varies by tier (Haiku=green, Sonnet=yellow, Opus=orange) via a case statement. Respects NO_COLOR and mono theme.
- **Array-based segments** — Segments are built into `seg_vals[]`/`seg_pris[]`/`seg_groups[]` arrays for truncation and grouping support.
- **set -e safety** — Git commands that may fail (e.g., `rev-list` with no upstream) use `|| fallback` pattern to prevent script death.
- **Usage limits via OAuth API** — Fetches 5-hour and 7-day utilisation from `api.anthropic.com/api/oauth/usage` in a background subshell. Credentials from Keychain (macOS) or `~/.claude/.credentials.json` (Linux/Windows). Cached with embedded timestamp, refreshes every 10 min.
- **Pacing markers** — Progress bars support an optional `│` marker (CLR_PACE) showing where usage *should* be for even consumption across the window.
- **Token security** — OAuth tokens are passed to curl via `--config -` (stdin), not command-line args, so they're hidden from `ps`. wget uses `--max-redirect=0` to prevent token leakage on redirects. **Note:** the wget fallback still passes `--header` as a CLI argument (visible in `ps aux`). Curl is strongly preferred; wget is a last-resort fallback.
- **Shared helpers** — `http_get()` consolidates curl/wget fallback, `iso_to_epoch()` consolidates cross-platform date parsing. Avoids duplicated patterns.
- **`extract_block()` for nested JSON** — Extracts a JSON object block by key (content between `{ }`) to support nested structures like `vim`, `agent`, `workspace`, and `context_window`. Used by vim mode, agent name, token count, and workspace directory segments.
- **`umask 077`** — All cache/temp files are created with restrictive permissions (not world-readable).
- **`NOW_EPOCH` cached once** — A single `date +%s` call at startup is reused everywhere to minimise fork overhead.
- **`bar_width` config** — Progress bar width is configurable (default 10), used by `build_progress_bar()`.
- **`branch_max_length` config** — Long branch names are truncated with an ellipsis when set.

## Roadmap & Sprints

See [ROADMAP.md](ROADMAP.md) for the feature roadmap and competitive landscape.
See [SPRINTS.md](SPRINTS.md) for the validated sprint plan with dependency ordering and effort estimates.

Current milestone: **Sprint 3 (v1.6.0)** — Testing & CLI.

## How to release a new version

**IMPORTANT: Do not skip any of these steps.** Tags and GitHub releases have been missed before — always create them alongside the version bump.

1. Bump `VERSION` file (e.g., `1.5.0`)
2. Update `CHANGELOG.md` with a new `[1.5.0] - YYYY-MM-DD` section
3. Update all docs: README.md, CLAUDE.md (current milestone), ROADMAP.md, SPRINTS.md
4. Commit everything: `git add -A && git commit -m "release: v1.5.0" && git push`
5. Create annotated tag: `git tag -a v1.5.0 -m "v1.5.0" && git push origin v1.5.0`
6. Create GitHub release with notes from CHANGELOG: `gh release create v1.5.0 --title "v1.5.0" --notes "..."`
7. Copy script to local install: `cp statusline-command.sh ~/.claude/statusline-command.sh`

Users with the update check will see `⬆ update available` within 6 hours.

## Testing

Test the script locally with sample JSON:

```bash
echo '{"cwd":"/tmp","display_name":"Sonnet","used_percentage":60,"total_cost_usd":0.50}' | bash statusline-command.sh
```

Test with new v1.4.0 fields (vim mode, agent, workspace, tokens, 200k warning):

```bash
echo '{"cwd":"/tmp","display_name":"Sonnet","used_percentage":60,"total_cost_usd":0.50,"vim":{"mode":"NORMAL"},"agent":{"name":"my-agent"},"workspace":{"current_dir":"/home/user/project"},"context_window":{"total_input_tokens":45000,"total_output_tokens":12000},"exceeds_200k_tokens":true}' | bash statusline-command.sh
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
