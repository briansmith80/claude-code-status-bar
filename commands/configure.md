---
description: Customize your claude-code-status-bar settings (guided wizard)
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
---

# claude-code-status-bar — Guided configuration wizard

You are a setup wizard for the user's status bar. Walk them through a short,
**guided** sequence of choices using the **AskUserQuestion** tool (one question
group at a time), then write only the non-default settings to
`~/.claude/statusline.conf`. Be friendly and fast. The whole point is that
*Claude Code is the interactive layer* — the user should never hand-edit a file
unless they want to.

Rules for every question:
- Make the FIRST option the user's CURRENT value (or the default), labelled
  "(keep current)". This lets them breeze through with one keypress.
- Use `multiSelect: true` for the toggle groups (Q3–Q5).
- Skip any group the user says they don't care about. Don't force all six.
- After the questions, PREVIEW before you save, then write only the diff.

## Step 1 — Read the current config and orient

```bash
conf_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline.conf"
if [ -f "$conf_file" ]; then echo "=== current statusline.conf ==="; cat "$conf_file"; else echo "No config yet — all defaults."; fi
```

Summarise the current state in one or two plain sentences (theme, layout, and
anything already non-default). Then offer to preview the themes live — this is
the closest thing to a visual picker and it shows each theme's gradient bars:

```bash
bash ~/.claude/statusline-command.sh --demo
```

## Step 2 — Run the guided questions (AskUserQuestion)

Ask these as a sequence of AskUserQuestion calls. You can batch up to 4 related
questions per call. For each option list, lead with the current/default value.

**Q1 — Theme** (single select): `default`, `nord`, `dracula`, `solarized`,
`tokyo-night`, `catppuccin`, `matrix`, `mono`. Tell them they can run
`--demo <theme>` to preview just one. (Offer 4 at a time if listing all eight;
or ask "which family — neon / muted / pastel / mono?" first, then narrow.)

**Q2 — Layout** (single select):
- `classic` — every metric on line 1, live activity on line 2 (the default)
- `three-line` — model/usage/cost · dir + git state · activity
- `stacked` — dir/model/usage · git state/duration · activity

**Q3 — Usage & limits** (multiSelect). Frame each as a feature to keep/enable:
- **Burn-rate forecast** (`usage_forecast`, default ON) — when you're on track
  to hit a limit before it resets, the countdown becomes a `▲time-to-limit`
  warning (e.g. `▲1h20m`). Quiet unless you're over pace. Recommend keeping ON.
- **Clock reset labels** (`usage_label=clock`, default countdown) — show the
  reset time (`2pm`) instead of the countdown (`2h20m`).
- **5-hour limit** (`show_usage_5h`, default ON) / **7-day limit**
  (`show_usage_7d`, default ON) — uncheck to hide.
- **Claude API status badge** (`show_claude_status`, default OFF): a
  degraded-only early warning fed by the public `status.claude.com` page. It
  shows `● Claude: major outage` (or `critical` / `degraded` / `maintenance`)
  ONLY when Claude is degraded, nothing when healthy, and polls in the
  background so it never touches the render path. If they turn it ON, ask one
  quick follow-up (single select) for sensitivity: **major + critical only**
  (`claude_status_min=major`, the default) or **also minor degradation +
  maintenance** (`claude_status_min=minor`). The poll interval defaults to 5 min
  (`claude_status_cache_seconds=300`) and is rarely worth changing.

**Q4 — Segments** (multiSelect). Offer the commonly-changed ones:
- Turn ON (off by default): cost-per-hour (`show_cost_rate`), token counts
  (`show_tokens`).
- Turn OFF (on by default) for a leaner bar: session cost (`show_cost`),
  lines-changed (`show_lines_changed`), dirty count (`show_dirty_count`),
  ahead/behind (`show_ahead_behind`), stash (`show_stash`), worktree
  (`show_worktree`), duration (`show_duration`), PR (`show_pr`).

**Q5 — Live activity line** (multiSelect):
- **Colourful activity** (`activity_colour`, default ON) — spinner, heat-coloured
  elapsed, red failures, completion flash, gradient todo bar.
- **Pulse** (`activity_pulse`) / **Scanner** (`activity_scanner`) — opt-in motion
  effects. If enabled, OFFER to set `refreshInterval: 3` (Step 5) so they animate.
- **Turn the activity line off** (`show_activity=false`) — drops the Node helper.

**Q6 — Bar style** (single select): `gradient` (the theme's ramp — default),
`heat` (fixed green→red on any theme), `flat` (single colour). Maps to
`bar_gradient=true|heat|false`.

## Step 3 — Preview before saving

Render the pending choices against a sample payload WITHOUT committing, by
sourcing the would-be settings inline:

```bash
# Replace KEY=VALUE pairs with the user's pending choices.
env_conf='colour_theme=nord
usage_forecast=true'
tmp="$(mktemp)"; printf '%s\n' "$env_conf" > "$tmp"
echo '{"cwd":"/tmp/demo","model":{"display_name":"Opus 4.8 (1M context)"},"context_window":{"used_percentage":78,"context_window_size":1000000,"total_input_tokens":780000},"total_cost_usd":1.23,"rate_limits":{"five_hour":{"used_percentage":62,"resets_at":'"$(( $(date +%s) + 5400 ))"'},"seven_day":{"used_percentage":71,"resets_at":'"$(( $(date +%s) + 200000 ))"'}}}' \
  | CLAUDE_CONFIG_DIR="$(dirname "$tmp")" HOME="$(dirname "$tmp")" bash ~/.claude/statusline-command.sh 2>/dev/null || true
rm -f "$tmp"
```

Show the rendered bar, confirm it looks right, then save.

## Step 4 — Write the diff

Write ONLY the keys that differ from defaults to `~/.claude/statusline.conf`,
one `key=value` per line with a short comment header. PRESERVE any existing keys
the wizard didn't touch (read the file, merge, write back). Never write a key
that equals its default — keep the file minimal so future defaults still apply.

## Step 5 — refreshInterval offer (only if pulse/scanner enabled)

`activity_pulse` / `activity_scanner` are wall-clock driven, so they only
animate when the bar re-renders often. On the default `refreshInterval` of 60
they sit static (not broken, just still). Offer to set `refreshInterval: 3`
(low enough to animate, odd so the pulse alternates, safe on every platform):

```bash
settings_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
node -e '
const fs=require("fs"), f=process.argv[1];
const s=JSON.parse(fs.readFileSync(f,"utf8"));
if(!s.statusLine){console.error("No statusLine entry yet. Run /claude-code-status-bar:setup first."); process.exit(1);}
s.statusLine.refreshInterval=3;
fs.writeFileSync(f, JSON.stringify(s,null,2)+"\n");
console.log("Set statusLine.refreshInterval=3");
' "$settings_file"
```

(No Node.js? Edit `settings.json` directly to add `"refreshInterval": 3` inside
the `statusLine` block.) Tell the user changes take effect on the next response.

---

## Appendix — full option reference

For power users who say "show me everything" or want a key the wizard didn't
cover. Every key goes in `~/.claude/statusline.conf` as `key=value`.

### Themes & styling
- `colour_theme` — `default`, `nord`, `dracula`, `solarized`, `tokyo-night`, `catppuccin`, `matrix`, `mono`. Preview with `--demo`.
- `bar_gradient` — `true` (theme ramp, default), `false` (flat), `heat` (fixed green→red).
- `use_icons` (default true) · `icon_set` — `classic` (default) or `modern` (dir ↱, branch ⑂, lines ⇄, duration ⏱).

### Layout
- `layout` — `classic` (default), `three-line`, `stacked`.
- `line1` / `line2` / `line3` — space-separated segment tokens (override the preset, per line). **Quote values with spaces.** `""` hides a row. Tokens: `dir`, `branch`, `model`, `context`, `usage_5h`, `usage_7d`, `lines_changed`, `dirty`, `ahead_behind`, `stash`, `pr`, `duration`, `worktree`, `cost`, `cost_rate`, `vim`, `agent`, `effort`, `fast_mode`, `tokens`, `update`, `activity`.
- `bar_width` (default 10) · `branch_max_length` (default unlimited) · `dir_style` — `auto` (default) / `full` / `basename` · `enable_truncation` (default true) · `max_width`.
- `use_groups` (default false) · `group_open` / `group_close` (default `[` / `]`).

### Segments (all on unless noted)
`show_directory` · `show_branch` · `show_model` · `show_context_bar` · `show_lines_changed` · `show_dirty_count` · `show_ahead_behind` · `show_stash` · `show_duration` · `show_worktree` · `show_cost` · `show_cost_rate` (off) · `show_usage_5h` · `show_usage_7d` · `show_pr` (CC 2.1.145+) · `show_tokens` (off) · `show_effort` (CC 2.1.133+) · `show_fast_mode` · `show_vim_mode` · `show_agent` · `show_activity`.

### Usage, cost & context
- `usage_label` — `countdown` (default, e.g. 2h20m) or `clock` (e.g. 2pm).
- `usage_forecast` (default true) — ▲time-to-limit warning when on track to hit a limit before reset; quiet otherwise.
- `usage_cache_seconds` (default 600) — OAuth fallback refresh; ignored when stdin provides limits.
- `context_warn_threshold` — `auto` (within 20k tokens of auto-compact, default) or a raw % like 80.
- `auto_hide` (default true) — hide zero/empty values.

### Claude API status (status.claude.com)
- `show_claude_status` (default false): opt-in, degraded-only early-warning badge fed by the public Claude status page. Polls in the background (never on the render path) and shows nothing when Claude is healthy.
- `claude_status_min` (default `major`): `major` surfaces major + critical outages; `minor` also surfaces minor degradation and maintenance windows.
- `claude_status_cache_seconds` (default 300): background poll interval. The status page's edge cache is about 10s, so a shorter interval rarely helps.
- The badge links to status.claude.com when `pr_link=true` (the shared hyperlink toggle).

### Git performance (large / network repos)
- `git_untracked` (default true) — `false` skips the untracked-file scan (faster on huge/network repos; untracked then don't count as dirty).
- `git_timeout` (default 0=off) — `N` wraps git in `timeout N` so a hung mount can't stall the render.

### Live activity line
- `activity_colour` (default true) · `activity_ttl_seconds` (default 120) · `activity_fresh_seconds` (default 45) · `activity_pulse` (off) · `activity_scanner` (off, needs `refreshInterval` ~3).
- `pr_link` (default true) — clickable OSC 8 hyperlink on the PR segment.
- `subagent_rows` (default true) — false keeps Claude Code's built-in subagent rows.

### Updates
- `auto_update` (default false) — opt-in: download + install a newer version in the background (atomic, SHA256-verified; never touches statusline.conf or settings.json).

## Final test

```bash
echo '{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":65},"total_cost_usd":1.50}' | bash ~/.claude/statusline-command.sh
```

Tell the user the changes take effect after the next Claude Code response.
