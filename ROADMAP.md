# Roadmap

Feature roadmap for claude-code-status-bar. Focused on high-value additions that keep the project simple and maintainable.

## Competitive Landscape

| Project | Language | Key Differentiator |
|---------|----------|--------------------|
| **claude-code-status-bar (ours)** | Bash | Pure bash, no deps, cross-platform, usage pacing markers |
| [ccstatusline](https://github.com/sirmalloc/ccstatusline) | Node.js | Powerline styling, interactive TUI config, 30+ widgets |
| [claude-powerline](https://github.com/Owloops/claude-powerline) | Bash | Vim-style powerline, 10+ bar styles, 6 themes |
| [claude_monitor_statusline](https://github.com/gabriel-dehan/claude_monitor_statusline) | Ruby | Plan-specific limits, message count |
| [claude-code-usage-bar](https://github.com/leeguooooo/claude-code-usage-bar) | Python | Cost depletion estimate, P90 budget tracking |
| [CCometixLine](https://github.com/Haleclipse/CCometixLine) | Rust | High-performance, TUI config |
| [rz1989s/claude-code-statusline](https://github.com/rz1989s/claude-code-statusline) | Bash | 4-line layout, 28 themes, 77 tests |

### Our Unique Strengths

- **Pure bash, zero dependencies** — no jq, no node, no python, no rust
- **Pacing markers** on usage progress bars (unique to us)
- **One-line installer** with background update checks
- **External config file** that survives updates
- **Priority-based truncation** for narrow terminals
- **Security hardening** — umask 077, stdin token passing, ANSI sanitization

---

## v1.4.0 — New Segments :white_check_mark:

Consume API fields we're already receiving but ignoring. Pure additive — no refactoring.

**Status**: Complete.

| Item | Type | Description |
|------|------|-------------|
| ~~`extract_block()` helper — #1~~ | infra | Nested JSON extraction for new API schema |
| ~~Vim mode segment — #2~~ | feature | Show NORMAL/INSERT when vim mode enabled |
| ~~Agent name segment — #3~~ | feature | Show agent name when running with `--agent` |
| ~~Token count segment — #4~~ | feature | Cumulative in/out token counts |
| ~~200k token warning — #6~~ | feature | Automatic warning when tokens exceed 200k |
| ~~Use `workspace.current_dir` — #8~~ | enhancement | Prefer new API field with `cwd` fallback |
| ~~`bar_width` config — #9~~ | config | Configurable progress bar width (default 10) |
| ~~`branch_max_length` config — #10~~ | config | Truncate long branch names |

---

## v1.5.0 — Visual Polish :white_check_mark:

Improve visual appearance without changing architecture.

**Status**: Complete.

| Item | Type | Description |
|------|------|-------------|
| ~~Model tier coloring — #13~~ | feature | Haiku=green, Sonnet=yellow, Opus=orange |
| ~~New themes — #16~~ | feature | tokyo-night and catppuccin |

---

## v1.6.0 — Testing & CLI

Protect what we've built and add practical CLI features.

| Item | Type | Description |
|------|------|-------------|
| BATS test scaffold — #25 | testing | Core tests for JSON parsing, progress bars, sanitization |
| CI matrix — #26 | ci | Add macOS and Windows (MSYS2) to GitHub Actions |
| `--dump-config` — #32 | cli | Print merged config (defaults + overrides) for debugging |
| `--uninstall` — #37 | cli | Clean removal of all installed files |

---

## After v1.6.0

Re-evaluate based on actual user feedback. The following ideas are parked — not planned, not promised. If users ask for them, we'll prioritize:

| Idea | Source Issue |
|------|-------------|
| Fish-style directory truncation | #12 |
| API wait time segment | #5 |
| Cache hit ratio segment | #7 |
| Separator config/styles | #11, #20 |
| Compact countdown (tokens before auto-compact) | #58 |
| Time-to-limit estimate for usage bars | #59 |
| ~~CLR_DIM modifier for secondary info~~ | ~~#14~~ (shipped in v1.5.1) |
| Display workspace.project_dir | #15 |
| Per-segment icon overrides | #17 |
| Overflow indicator | #18 |
| Progress bar styles (dots, line, ascii) | #19 |
| Two-line layout (confirmed working) | #21 |
| Right-aligned segments | #22 |
| Progressive truncation cascade | #23 |
| Segment reordering | #24 |
| Token speed | #27 |
| Session budget bar | #28 |
| Cost velocity indicator | #29 |
| Alert-only usage mode | #30 |
| Rate limit countdown | #31 |
| --preview CLI flag | #33 |
| Session history / --stats | #34, #36 |
| Today's totals | #35 |
| --test CLI flag | #38 |
| Plan-aware limits | #39 |
| OSC 8 clickable links | #40 |
| Install script CI | #41 |
| Modular segment architecture | #42-#44 |
| Performance optimizations | #45-#48 |
| --benchmark CLI flag | #49 |
| Comprehensive BATS coverage | #50 |
| CONTRIBUTING.md / JSON schema docs | #51 |
| Automated release workflow | #52 |
| Compact buffer zone | #61 |
| Three-tier context severity | #62 |
| Compact detection indicator | #65 |

---

## Known Claude Code Issues Affecting Statusline

Open issues in [anthropics/claude-code](https://github.com/anthropics/claude-code/issues):

| Issue | Impact |
|-------|--------|
| [#31415](https://github.com/anthropics/claude-code/issues/31415) Effort level not in JSON | Can't show thinking effort level |
| [#30189](https://github.com/anthropics/claude-code/issues/30189) Expose plan_mode/sandbox | Can't show plan mode or sandbox status |
| [#30266](https://github.com/anthropics/claude-code/issues/30266) Invoke on session start | Status bar blank until first response |
| [#27929](https://github.com/anthropics/claude-code/issues/27929) Disable built-in content | "Context low" compresses custom statuslines |
| [#29411](https://github.com/anthropics/claude-code/issues/29411) Not rendered on resume | Status bar missing on resumed sessions |
| [#32406](https://github.com/anthropics/claude-code/issues/32406) Expand hook data | Missing model, effort, context in hooks |

---

## Principles

1. **Stay pure bash** — no jq, no node, no python, no compiled binaries
2. **Never block the status bar** — network/slow ops in background subshells with caching
3. **Config survives updates** — `statusline.conf` is never overwritten
4. **Cross-platform first** — macOS, Linux, and Windows/MSYS2
5. **Security by default** — sanitize untrusted input, hide tokens, restrictive permissions
6. **Keep it simple** — resist feature creep. If it needs a different language, it's a different project
