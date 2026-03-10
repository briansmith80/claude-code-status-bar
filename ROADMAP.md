# Roadmap

Feature roadmap for claude-code-status-bar, informed by the [official Claude Code statusLine API](https://code.claude.com/docs/en/statusline), community projects, and user feedback.

## Competitive Landscape

| Project | Language | Stars | Key Differentiator |
|---------|----------|-------|-------------------|
| **claude-code-status-bar (ours)** | Bash | — | Pure bash, no deps, cross-platform, usage pacing markers |
| [ccstatusline](https://github.com/sirmalloc/ccstatusline) | Node.js | 3.1k | Powerline styling, interactive TUI config, 30+ widgets, token speed |
| [claude-powerline](https://github.com/Owloops/claude-powerline) | Bash | — | Vim-style powerline, 10+ context bar styles, 6 themes, daily usage |
| [claude_monitor_statusline](https://github.com/gabriel-dehan/claude_monitor_statusline) | Ruby | — | Plan-specific limits (Pro/Max5/Max20), message count |
| [claude-code-usage-bar](https://github.com/leeguooooo/claude-code-usage-bar) | Python | — | Cost depletion estimate, P90 budget tracking, auto-updating |
| [CCometixLine](https://github.com/Haleclipse/CCometixLine) | Rust | — | High-performance, TUI config, git integration |
| [claudia-statusline](https://github.com/hagan/claudia-statusline) | Rust | — | Persistent stats, cloud sync, XDG-compliant |
| [rz1989s/claude-code-statusline](https://github.com/rz1989s/claude-code-statusline) | Bash | — | 4-line layout, MCP monitoring, prayer times, 28 themes, 77 tests |
| [claude-statusline](https://github.com/dwillitzer/claude-statusline) | — | — | Multi-provider (Claude, GPT, Gemini, Grok) |

### Our Unique Strengths

- **Pure bash, zero dependencies** — no jq, no node, no python, no rust, no compiled binaries
- **Pacing markers** on usage progress bars (unique to us)
- **One-line installer** with background update checks
- **External config file** that survives updates
- **Priority-based truncation** for narrow terminals
- **Security hardening** — umask 077, stdin token passing, ANSI sanitization, wget redirect protection

---

## v1.3.1 — Bug Fixes

Issues discovered during codebase analysis. Low-effort, high-value fixes.

- [ ] **Fix CHANGELOG inaccuracy** — CHANGELOG.md says "`input=$(cat)` replaced with `read -r -d ''`" but the code uses `input=$(cat)` (the `read` approach was reverted due to MSYS2 incompatibility). Update the CHANGELOG entry.
- [ ] **Add numeric guard for update cache** — `cached_time` at line 131 lacks the `case *[!0-9]* ) 0` guard that the usage cache has at line 464. A corrupted update cache file causes an arithmetic error.
- [ ] **Document wget auth header exposure** — The wget fallback passes `--header="${HTTP_AUTH_HEADER}"` as a CLI argument (visible in `ps aux`). Curl uses `--config -` (hidden). Note this limitation in CLAUDE.md.
- [ ] **Handle empty-string JSON values** — `extract_from()` regex `\"([^\"]+)\"` requires at least one character, so `"key": ""` returns nothing. Add a second regex branch for empty strings.
- [ ] **Session start placeholder** — When JSON fields are null (before first API response), show "Starting..." instead of `? ░░░░░░░░░░ 0%`.

---

## v1.4.0 — New API Fields & Quick Wins

Low-effort features using JSON fields already provided by Claude Code but not yet consumed. The official API now provides a [restructured nested JSON schema](https://code.claude.com/docs/en/statusline).

### Unused API Fields

| Field | Current Status | Potential Use |
|-------|---------------|---------------|
| `model.id` | Not used | Full model ID for granular display |
| `workspace.project_dir` | Not used | Show project name when cwd differs from launch dir |
| `session_id` | Not used | Short session identifier or per-session caching |
| `transcript_path` | Not used | Clickable link to transcript file |
| `version` | Not used | Claude Code version number |
| `output_style.name` | Not used | Show when non-default output style is active |
| `cost.total_api_duration_ms` | Not used | Time spent waiting for API responses |
| `context_window.total_input_tokens` | Not used | Cumulative input token count |
| `context_window.total_output_tokens` | Not used | Cumulative output token count |
| `context_window.remaining_percentage` | Not used | Pre-calculated remaining % |
| `context_window.current_usage.*` | Not used | Per-call token breakdown (input, output, cache_creation, cache_read) |
| `exceeds_200k_tokens` | Not used | Boolean: tokens from last response exceed 200k |
| `vim.mode` | Not used | NORMAL/INSERT when vim mode enabled |
| `agent.name` | Not used | Agent name when running with `--agent` |
| `worktree.path`, `.branch`, `.original_cwd`, `.original_branch` | Not used | Extended worktree info |

### New Segments

| Segment | API Field | Toggle | Description |
|---------|-----------|--------|-------------|
| Vim mode | `vim.mode` | `show_vim_mode` | Show NORMAL/INSERT when vim mode is enabled |
| Agent name | `agent.name` | `show_agent` | Show agent name when running with `--agent` |
| Token counts | `context_window.total_input_tokens` / `total_output_tokens` | `show_tokens` | Cumulative in/out token counts (e.g., "15k in 4k out") |
| API wait time | `cost.total_api_duration_ms` | `show_api_duration` | Time spent waiting for API responses |
| 200k warning | `exceeds_200k_tokens` | (automatic) | Warning indicator when tokens exceed 200k |
| Cache hit ratio | `current_usage.cache_read_input_tokens` | `show_cache_ratio` | % of input tokens served from cache |

### Enhancements

- [ ] **Use `workspace.current_dir`** instead of flat `cwd` (preferred per official docs, with `cwd` as fallback)
- [ ] **Use `workspace.project_dir`** in directory display — show project name when cwd differs from project root
- [ ] **Multi-line support** — `layout=two-line` puts git/directory on line 1, metrics on line 2. Claude Code natively supports multi-line output (each `echo` is a separate row).
- [ ] **Autocompact buffer visualization** — reserve ~22.5% of the context progress bar as a "buffer zone" (dimmed), showing effective free space vs raw free space
- [ ] **`padding` setting** — document that `settings.json` supports a `padding` field for horizontal spacing

### New Config Options

- [ ] **`bar_width`** — progress bar width (currently hardcoded to 10)
- [ ] **`branch_max_length`** — truncate long branch names (e.g., `feature/JIRA-1234-impl...`)
- [ ] **`dir_style`** — `full` (current), `basename`, or `fish` (fish-style `/h/u/p/my-app`)
- [ ] **`separator`** — segment separator character (currently hardcoded as two spaces)

---

## v1.5.0 — Visual Polish & UX

### Progress Bar Styles

Add a `bar_style` config option:

| Style | Example | Config Value |
|-------|---------|-------------|
| Block (current) | `████░░░░░░` | `block` |
| Filled | `▓▓▓▓░░░░░░` | `filled` |
| Braille | `⣿⣿⣿⣿⡀⠀⠀⠀⠀⠀` | `braille` |
| Dots | `●●●●○○○○○○` | `dots` |
| Line | `━━━━┅┅┅┅┅┅` | `line` |
| ASCII | `####......` | `ascii` |

### Separator Styles

| Style | Example | Config Value |
|-------|---------|-------------|
| Space (current) | `seg1  seg2  seg3` | `space` |
| Pipe | `seg1 │ seg2 │ seg3` | `pipe` |
| Powerline | `seg1seg2seg3` | `powerline` |
| Capsule | `(seg1) (seg2) (seg3)` | `capsule` |

### Layout

- [ ] **Segment reordering** — `segment_order="dir,branch,model,context,..."` to control display order
- [ ] **Right-aligned segments** — `align_right="cost,duration"` pushes segments to the right edge using Starship's fill-character pattern
- [ ] **Progressive truncation cascade** — before dropping entire segments, first: shorten directory (fish-style), abbreviate model names ("S" for Sonnet), shorten labels ("5h" → "5"). More info visible at narrow widths.
- [ ] **Overflow indicator** — when segments are dropped, show `…` or `+N` at the end

### More Themes

| Theme | Description |
|-------|-------------|
| `tokyo-night` | Tokyo Night colour palette |
| `rose-pine` | Rosé Pine colour palette |
| `gruvbox` | Gruvbox colour palette |
| `catppuccin` | Catppuccin colour palette |

### Visual Modifiers

- [ ] **`CLR_DIM`** — dim modifier for secondary info (reset times, $/hr) to create visual hierarchy
- [ ] **Model tier coloring** — colour model name by tier: Haiku=green (cheap), Sonnet=yellow (mid), Opus=red (expensive)
- [ ] **Per-segment icon overrides** — allow `icon_branch="🌿"` etc. in config

---

## v1.6.0 — Smart Features

### Token Speed

Display tokens-per-second using a rolling window calculation:

```
⚡ 142 tok/s
```

Implementation: track `total_input_tokens` + `total_output_tokens` delta between invocations using a small cache file. Configurable window (default 30s).

- Toggle: `show_token_speed`
- Config: `token_speed_window=30`

### Cost Intelligence

- [ ] **Cost depletion estimate** — "at current burn rate, budget depletes in Xh" using cost rate + plan limits
- [ ] **Daily cost aggregation** — track cost across sessions per day using a persistent file
- [ ] **Session budget** — `session_budget=5.00` shows a progress bar of spend against budget with threshold coloring
- [ ] **Cost velocity indicator** — `$2.40/hr ↑` (accelerating), `$1.80/hr ↓` (decelerating), `$2.00/hr →` (steady)
- [ ] **Budget alert** — `budget_alert_usd=10.00` triggers a warning colour when daily spend exceeds threshold

### Clickable Links (OSC 8)

Claude Code supports [OSC 8 hyperlinks](https://en.wikipedia.org/wiki/ANSI_escape_code#OSC) in terminals that support them (iTerm2, Kitty, WezTerm):

- [ ] **Clickable branch name** — links to GitHub branch
- [ ] **Clickable repo name** — links to GitHub repo
- [ ] **Clickable transcript** — links to `transcript_path`
- [ ] Config: `use_links=true` (default false, since many terminals don't support it)

### Context Window Intelligence

- [ ] **Cache hit ratio** — display `cache_read_input_tokens / (cache_read + cache_creation)` as a percentage
- [ ] **Context remaining countdown** — estimated messages remaining based on average tokens per turn
- [ ] **Rate limit countdown** — when usage hits 100%, show countdown to reset: `5hr LIMIT resets in 47m`
- [ ] **Pace-ahead/behind text** — `5hr: 12% ahead of pace` alongside the visual marker

### Other

- [ ] **Alert-only usage mode** — `usage_alert_threshold=80` hides usage bars entirely until utilization exceeds threshold. Reduces noise, surfaces info only when it matters.
- [ ] **Plan-aware limits** — `plan_type=max5` enables message/token caps display (Pro: 250 msgs, Max5: 1000, Max20: 2000). Config: `plan_type`.

---

## v1.7.0 — Persistent Analytics & CLI

### Session History

Track metrics across sessions in a lightweight log file (`~/.claude/.statusline-history.jsonl`):

```jsonl
{"ts":1741600000,"session":"abc123","cost":1.23,"tokens_in":45000,"tokens_out":12000,"duration":3600,"lines_added":150,"lines_removed":30}
```

- [ ] **Today's totals** — `show_today_cost`, `show_today_tokens` segments showing aggregated daily metrics
- [ ] **Session count** — "Session 3 today" indicator
- [ ] **CLI reporting** — `--stats today`, `--stats week`, `--stats month` for historical summaries

### CLI Enhancements

- [ ] **`--uninstall`** — removes all installed files and settings.json entry (currently requires manual 5-step process)
- [ ] **`--dump-config`** — prints all current config values (defaults + user overrides merged) for debugging
- [ ] **`--test`** — accepts JSON on stdin and outputs with debug info (which segments were hidden, truncation decisions)
- [ ] **`--preview`** — render status bar with sample data for theme/config testing

### MCP Server Monitoring

- [ ] **MCP status indicator** — green dot when MCP servers are healthy, red when disconnected
- [ ] Config: `show_mcp_status` toggle

---

## v2.0.0 — Architecture Evolution

### Modular Segments

Break the monolithic script into a plugin-like architecture:

```
~/.claude/statusline-command.sh          # Core + loader
~/.claude/statusline-segments/           # Optional segment overrides
  custom-weather.sh                      # User-created segment
```

Each segment is a function that outputs `value|priority|group`. Users can add custom segments without modifying the main script.

### Performance

Current estimated fork count per invocation: ~20-25 subprocesses. Key reduction targets:

- [ ] **Optimize `sanitize()`** — add fast-path: if string contains no ANSI escapes, skip `printf | sed | tr` chain (saves 6-8 forks for typical invocations)
- [ ] **Replace `echo | cut` for ahead/behind** — use bash parameter expansion `${ab_output%%$'\t'*}` (saves 2 forks)
- [ ] **Replace `git stash list | wc -l`** — use `git rev-list --count refs/stash` (single process, no pipe)
- [ ] **Benchmark mode** — `--benchmark` runs the script 100 times and reports average execution time
- [ ] **Lazy git operations** — cache all git operations together (branch, dirty, ahead/behind, stash) in a single cache file with configurable TTL
- [ ] **Reduce `format_reset_label()` forks** — currently forks `date` 1-2 times per call × 2 calls. Use epoch arithmetic to produce hour/day strings without `date`.

### Testing

Currently **no automated tests exist**. The CI pipeline only runs ShellCheck.

- [ ] **BATS test suite** — [bats-core](https://github.com/bats-core/bats-core) tests for:
  - JSON parsing correctness (malformed JSON, missing keys, Unicode, empty strings)
  - Progress bar rendering at 0%, 50%, 80%, 100% with and without pacing markers
  - Sanitization of ANSI escape sequences
  - Theme application and NO_COLOR
  - Config file loading, defaults, and user overrides
  - Truncation behavior and priority ordering
  - Edge cases: empty stdin, no git repo, no network
- [ ] **CI matrix** — test on macOS, Ubuntu, and Windows (MSYS2) in GitHub Actions (currently only `ubuntu-latest`)
- [ ] **Install script testing** — CI job that runs `install.sh` on a fresh environment
- [ ] **Automated release workflow** — GitHub Actions triggered on VERSION file changes for tagging and release creation

### Documentation

- [ ] **Screenshots/GIF** for README — show actual terminal output with colours
- [ ] **"How it works" section** — explain that the script receives JSON from Claude Code
- [ ] **JSON schema docs** — document the expected input format for contributors
- [ ] **CONTRIBUTING.md** — PR guidelines, testing instructions, code conventions
- [ ] **FAQ section** — common questions (usage bars not appearing, icon customization, performance)

---

## Known Claude Code Issues Affecting Statusline

Open issues in [anthropics/claude-code](https://github.com/anthropics/claude-code/issues) that affect statusline scripts:

| Issue | Status | Impact |
|-------|--------|--------|
| [#31415](https://github.com/anthropics/claude-code/issues/31415) Effort level not in statusline JSON | Open | Can't show thinking effort level natively |
| [#30189](https://github.com/anthropics/claude-code/issues/30189) Expose plan_mode/sandbox in JSON | Open | Can't show plan mode or sandbox status |
| [#30266](https://github.com/anthropics/claude-code/issues/30266) Invoke statusline on session start | Open | Status bar is blank until first assistant response |
| [#27929](https://github.com/anthropics/claude-code/issues/27929) Disable built-in statusline content | Open | "Context low" banner compresses custom statuslines |
| [#29411](https://github.com/anthropics/claude-code/issues/29411) Not rendered on resumed sessions | Open | Status bar missing when resuming a session |
| [#32406](https://github.com/anthropics/claude-code/issues/32406) Expand hook input with more data | Open | Missing model, effort, context data in hooks |

---

## Future Ideas (Unscheduled)

Lower priority. Community interest would promote them to a version.

| Idea | Source | Notes |
|------|--------|-------|
| Reasoning effort indicator | szerintedmi gist | Read from settings files as fallback until API exposes it |
| Message count tracking | claude_monitor_statusline | Not in API; would need transcript parsing |
| Multi-provider support | claude-statusline (dwillitzer) | Support Claude, GPT, Gemini display |
| Persistent stats + cloud sync | claudia-statusline | Heavy feature; may be better as separate tool |
| Rust rewrite for speed | CCometixLine, claudia-statusline | Bash is fast enough; adds build dependency |
| tmux session detection | claude-powerline | Show session name when inside tmux |
| Desktop notification on threshold | Original idea | `osascript`/`notify-send` when context > threshold |
| Config hot-reload detection | Original idea | Detect `statusline.conf` changes without restart |
| Segment animations (spinner) | ccstatusline | Show spinner in model segment during API calls |
| Container/devcontainer awareness | Starship docker_context | Detect if running inside a container |
| Virtual env indicator | Starship conda/nix modules | Show active Python venv, conda env, nvm version |
| Project detector | Starship package module | Detect `package.json`, `Cargo.toml`, etc. and show project info |
| Cost sparkline | Original idea | Tiny `▁▂▃▅█` sparkline showing cost trend over session |
| Session streak | Original idea | Track consecutive days with sessions: "7 days" |
| Custom segments | Starship custom module | User-defined shell commands as segments in config |

---

## Priority Matrix

```
                    HIGH IMPACT
                        │
  v1.3.1 Bug fixes      │    v1.4 Multi-line layout
  v1.4 Vim/Agent/Tokens  │    v1.4 Autocompact buffer
  v1.4 200k warning     │    v1.5 Progressive truncation
  v1.4 bar_width config │    v1.6 Token speed
  v1.4 Fish-style dirs  │    v1.6 Cost depletion
                        │    v1.6 Plan-aware limits
  ──────────────────────┼──────────────────────
                        │
  v1.5 More themes      │    v1.7 Session history
  v1.5 Separators       │    v1.7 --uninstall CLI
  v1.5 CLR_DIM          │    v2.0 BATS test suite
  v1.6 OSC 8 links      │    v2.0 CI matrix
  v1.5 Model tier color │    v2.0 Modular segments
                        │
                   LOW IMPACT
       LOW EFFORT ──────┼────── HIGH EFFORT
```

---

## Principles

1. **Stay pure bash** — no jq, no node, no python, no compiled binaries. This is our core differentiator.
2. **Never block the status bar** — all network/slow operations run in background subshells with caching.
3. **Config survives updates** — user overrides in `statusline.conf` are never overwritten.
4. **Cross-platform first** — every feature must work on macOS, Linux, and Windows/MSYS2.
5. **Security by default** — sanitize untrusted input, hide tokens from process lists, restrictive file permissions.
6. **Backward compatible** — old config keys continue to work via shims. Breaking changes only at major versions.
7. **Minimize forks** — prefer bash builtins over subprocesses. Track fork count per invocation (~20-25 currently).
