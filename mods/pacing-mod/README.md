# pacing-mod

A usage pacing pane for Claude Code. It shows the 5-hour and weekly limits with an even-pace marker and a burn-rate forecast, plus the context window with its auto-compact point, in the status bar's own themes. Built for the Desktop app's Code tab and the VS Code panel, where the `statusLine` setting does not run.

| Surface | Pane | Band above the prompt | Reopen after closing |
|---|---|---|---|
| Desktop Code tab | Yes | Yes | Band button, chat row, `/pacing` |
| VS Code panel (extension 2.1.299+) | Yes | Yes, under VS Code's own "From the pacing-mod plugin" caption | Band button, chat row, `/pacing` |
| Desktop Chat and Cowork tabs | No. Mods run in Claude Code sessions only (tested 10 Nov 2026: the plugin installs but never loads) | No | None |
| Terminal | Only on `/pacing` (text version). It never opens by itself, the status line already shows this | No, the status line already shows this | `/pacing` |

## What it shows

For each window: used %, "over pace by 20" / "under pace by 70" / "on pace", the reset countdown, and one line on what happens at this rate ("At this rate you hit the limit in 45m", or "Limit not reached before reset"). The bar's pink marker sits where an even spend would have you by now, labelled with that percent.

The context card shows the fill, tokens used, how many tokens are left before auto-compact (with the status bar's 20k-token warning), the model and window size. Its marker is the auto-compact point.

`/pacing status` prints one line in the chat (`5h 12% (under pace by 70, resets in 53m) · wk 9% (…) · ctx 25% (267k tokens to auto-compact) · Session 2h14m`), for a terminal too narrow to place the pane or a quick check without it.

`/pacing demo` fills the pane with sample data in every state (over pace, past 90%, the per-model weekly swap, near auto-compact) so you can review the look; `/pacing` returns to live.

Bars are drawn as images, so they cannot follow the app's light or dark mode. The track is a translucent grey, the fills are saturated, and the marker carries a thin dark edge, so both modes read. The text around them follows the app.

The maths is the status bar's (`calc_pacing_target`, `calc_forecast`) ported to TypeScript. `tests/vectors.ts` holds shared cases that both the mod's tests and the repo's `tests/pacing_mod.bats` run, so the two cannot drift.

## Data

- `$.session.usage().rateLimits`, pushed by `session.measure` after each reply. Empty until the first reply, and always empty on API-key auth.
- A per-model weekly cap (some plans cap one model below the all-models weekly) is shown when it binds first, from a `seven_day_<model>` limit if Claude Code forwards one, or from the status bar's `~/.claude/.statusline-usage-cache` when that is present and under an hour old.
- Context: `$.session.usage()` with the summary breakdown (a local estimate, no API call) for the auto-compact threshold; `session.measure` keeps the fill current.
- Theme: `colour_theme` and `bar_gradient` from `~/.claude/statusline.conf`, unless the `theme` option pins one.

## Options

Set in `/config` or from the pane's theme picker.

| Option | Default | What it does |
|---|---|---|
| `theme` | `status-bar` | Follow the status bar's conf, or pin one of the 8 themes |
| `band` | `true` | The one-line band above the prompt in Desktop and VS Code |
| `context` | `true` | The context window card in the pane, and `ctx` in the band |
| `toasts` | `true` | One toast per window when it resets, the forecast fires, or usage passes 90% |
| `notify` | `false` | The same alerts as native notifications through your `preferredNotifChannel`, for when the window is not in front. Needs a terminal-backed session; the Desktop app may report `no-surface` |
| `session` | `true` | A "Session 2h14m · $2.50" row under the cards (cost only where the host keeps one, so API-key sessions) |

## Install

```
/plugin install pacing-mod --marketplace briansmith80/claude-code-status-bar
```

In Desktop: `+` next to the prompt, Plugins, Add marketplace `briansmith80/claude-code-status-bar`, Add plugin. A mod installed at user scope from a terminal loads in Desktop too.

## Develop

```
claude plugin validate mods/pacing-mod
claude plugin test mods/pacing-mod
claude --plugin-dir mods/pacing-mod
```

Desktop and VS Code pick a dev copy up from `CLAUDE_CODE_PLUGIN_DIRS` (user environment variable, absolute path), after a full restart.
