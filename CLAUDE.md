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

## Key design decisions

- **No jq** — Uses bash regex (`BASH_REMATCH`) for JSON parsing. Windows/MSYS2 users don't have jq.
- **Bash 3.2 minimum** — Must work on stock macOS. No associative arrays, no `readarray`, no `${var,,}`.
- **Background update check** — Fetches VERSION from GitHub every 6h in a background subshell. Never blocks the status bar.
- **External config** — User overrides go in `statusline.conf`, sourced after defaults. Survives updates.
- **Single version source** — Only `VERSION` file needs bumping. Installer downloads it; script reads it at runtime.
- **Sanitize untrusted strings** — Branch names, paths, and worktree names are stripped of ANSI escapes before output.
- **Colour themes via CLR_* variables** — All ANSI codes use theme variables set by `apply_theme()`. Supports NO_COLOR standard.
- **Array-based segments** — Segments are built into `seg_vals[]`/`seg_pris[]`/`seg_groups[]` arrays for truncation and grouping support.
- **set -e safety** — Git commands that may fail (e.g., `rev-list` with no upstream) use `|| fallback` pattern to prevent script death.

## How to release a new version

1. Edit `VERSION` (e.g., `1.1.0`)
2. `git add VERSION && git commit -m "release: v1.1.0" && git push`
3. `git tag -a v1.1.0 -m "v1.1.0" && git push origin v1.1.0`
4. `gh release create v1.1.0 --title "v1.1.0" --notes "..."`

That's it. Users with the update check will see `⬆ update available` within 6 hours.

## Testing

Test the script locally with sample JSON:

```bash
echo '{"cwd":"/tmp","display_name":"Sonnet","used_percentage":60,"total_cost_usd":0.50}' | bash statusline-command.sh
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
- Default palette: cyan=dir, magenta=branch, blue=model, green=additions, red=removals, yellow=warnings/cost
- All git commands use `-c core.fsmonitor=false` to avoid filesystem monitoring overhead
- Fallback chains: curl > wget, node > python3 > python > manual instructions

## Common pitfalls

- **GitHub raw CDN caches aggressively** — After pushing VERSION, it can take 5+ minutes for `raw.githubusercontent.com` to serve the new content.
- **Local install gets stale** — After editing the repo's `statusline-command.sh`, remember to copy it to `~/.claude/` for your own status bar to update.
- **`set -e` in subshells** — Background update fetch runs in `( ) &`. If curl/wget fails inside, only the subshell dies (by design).
