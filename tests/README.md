# Tests

BATS test suite for `statusline-command.sh`. Each test sandboxes `HOME` to a
fresh temp directory so the developer's real `~/.claude/statusline.conf` and
credentials never leak into a run.

## Install BATS

| Platform | Command |
|----------|---------|
| macOS | `brew install bats-core` |
| Debian / Ubuntu | `sudo apt-get install -y bats` |
| Windows (Git Bash / MSYS2) | `git clone --depth 1 https://github.com/bats-core/bats-core.git ~/bats-core`, then run `~/bats-core/bin/bats` (the MSYS2 pacman repo no longer ships a bats package) |
| Other Linux | see <https://github.com/bats-core/bats-core> |

## Run

From the repo root:

```bash
bats tests/
```

Run a single file:

```bash
bats tests/basic.bats
```

## Layout

- `test_helper.bash` — shared helpers (`run_statusline`, `strip_ansi`, sandbox).
- `basic.bats` — schema parsing (old flat, new nested, stdin `rate_limits`).
- `segments.bats` — directory, model, cost, vim mode, agent segments.
- `themes.bats` — all seven themes plus `NO_COLOR` behaviour.
- `config.bats` — `~/.claude/statusline.conf` overrides.
- `context_window.bats` — `of 200k` / `of 1M` formatting, bar fill, and auto-compact marker/warning.
- `cc21.bats` — Claude Code 2.1.x schema: nested `cost`, `current_usage`, Fable tier colour, effort/fast-mode segments, rate-limit scoping, countdown labels, PR segment, worktree fallback.
- `activity.bats` — live activity helper: age-out, failure indicator, elapsed time, incremental parsing, `activity_ttl_seconds`, width trim.
- `subagent.bats` — subagent panel renderer: icons, rates, width fitting, toggles.
