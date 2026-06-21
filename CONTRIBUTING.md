# Contributing to claude-code-status-bar

Thanks for your interest. This is a small, focused project with strong design
constraints, so a quick read here will help your contribution land smoothly.

## Project shape

| File | Purpose |
|------|---------|
| `statusline-command.sh` | The bash runtime (the status bar). Installed to `~/.claude/`. |
| `statusline-helper.js` | Optional Node.js transcript parser for the live activity line. |
| `statusline-subagent.js` | Optional Node.js subagent-panel renderer. |
| `tests/*.bats` | The BATS test suite (runs on macOS, Linux, and Windows/MSYS2 in CI). |
| `VERSION` | Single source of truth for the version. |
| `CLAUDE.md` | Full architecture and design rationale. Read this before a non-trivial change. |

## Design principles (please don't break these)

- **Pure bash core, no jq.** JSON is parsed with bash regex so Windows/MSYS2
  users need nothing extra. **Bash 3.2 minimum** (stock macOS): no associative
  arrays, no `readarray`, no `${var,,}`.
- **Never block the render.** Anything slow (network, transcript parsing) runs
  in a fully detached background subshell; the bar renders from caches.
- **REPLY return convention on the hot path.** Internal helpers return via the
  `$REPLY` global, not `$(...)` command substitution (each subshell fork costs
  ~15-25 ms on MSYS, and many run per render).
- **`set -e` safety.** Guard fallible commands with `|| fallback`.
- **Sanitize untrusted input**, and print both render lines with `printf '%s'`
  (never `%b`) so field text can't decode into terminal control sequences.

## Dev setup and tests

```bash
# Run the suite (install bats-core first)
bats tests/

# Quick manual render
echo '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":60}}' | bash statusline-command.sh

# Preview themes / measure performance
bash statusline-command.sh --demo
bash statusline-command.sh --benchmark      # add STATUSLINE_PROFILE=1 for a per-phase breakdown
```

CI runs ShellCheck on every push, so please keep `statusline-command.sh` clean.

## Adding a segment

Segments are built with `add_seg "<content>" <priority> "<group>" "<name>"`:

- **priority** (1 = highest) controls what's dropped first on a narrow terminal.
- **group** brackets related segments when `use_groups=true`.
- **name** is the stable token the layout engine uses (`line1`/`line2`/`line3`).

Gate the segment behind a `show_<thing>` config default, keep it fork-free
(REPLY convention), and add a BATS test.

## Pull requests

1. Keep tests green (`bats tests/`) and ShellCheck clean; add tests for new behaviour.
2. If you changed `statusline-command.sh`, `statusline-helper.js`, or
   `statusline-subagent.js`, regenerate the checksum manifest with
   `scripts/update-sha256sums.sh` (CI fails on drift).
3. Update docs (README, `CLAUDE.md`, `statusline.conf.example`) for any new config.
4. Don't bump `VERSION`/`CHANGELOG.md` in feature PRs — releases are batched by the maintainer.
5. Open the PR against `main` with a clear description of the change and why.

## Reporting bugs and ideas

Please use the issue templates (Bug report / Feature request). For security
issues, follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

By contributing, you agree that your work is licensed under the project's
[MIT License](LICENSE).
