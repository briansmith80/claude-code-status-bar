# Tests

BATS test suite for `statusline-command.sh`. Each test sandboxes `HOME` to a
fresh temp directory so the developer's real `~/.claude/statusline.conf` and
credentials never leak into a run.

## Install BATS

| Platform | Command |
|----------|---------|
| macOS | `brew install bats-core` |
| Debian / Ubuntu | `sudo apt-get install -y bats` |
| Windows / MSYS2 | `pacman -S --noconfirm bats` |
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
- `segments.bats` — directory, model, cost, vim mode, agent, 200k warning.
- `themes.bats` — all seven themes plus `NO_COLOR` behaviour.
- `config.bats` — `~/.claude/statusline.conf` overrides.
- `context_window.bats` — `of 200k` / `of 1M` / `of 1.5M` formatting and bar fill.
