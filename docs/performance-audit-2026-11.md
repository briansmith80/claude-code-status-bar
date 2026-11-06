# Performance and process-leak audit (November 2026)

Written for v2.25.0. Trigger: over 5 to 6 Nov 2026 a Windows PC running about eight
Claude Code sessions (status bar on a 3-second `refreshInterval`) had **416
stuck `git.exe` processes using about 2.5 GB**. All were suspended: one thread,
state Wait/Suspended, 0 ms CPU, parent gone. This file records the cause, the
proof, every outside process and network call the bar makes, and the findings
ranked by impact on the machine.

## Cause (proven)

1. Claude Code cancels an in-flight status line run whenever the next one
   starts (each refresh tick, and every event burst, debounced at 300 ms). In
   the Claude Code 2.1.301 binary the cancel goes through `killProcessTree`,
   which on Windows runs `taskkill /PID <bash> /T /F`. It kills the whole tree.
2. MSYS2 bash (Git Bash) starts a native Windows program (`git.exe`,
   `curl.exe`, `node.exe`) with `CREATE_SUSPENDED` and resumes it a moment
   later. Programs built for MSYS (`cat`, `date`, `mv`) are not started this way.
3. If the tree kill lands between those two steps, the bash process that
   would resume the child is gone and the child stays suspended forever.
   Claude Code starts the status line `detached`, so no job object cleans up.
4. A slow render is more likely to be cancelled, and a busy PC makes renders
   slow. Each leaked process makes the PC busier. It feeds itself.

Proof, using a harness that copies Claude Code's runner (Git Bash, detached,
stdin JSON, cancelled with `taskkill /T /F` at a random 0 to 1.2 s):

| Run (400 cancelled renders, 8 parallel) | Stuck processes left |
|---|---|
| v2.24.0, tree kill (what Claude Code does) | **3** `git.exe` |
| v2.24.0, kill bash only (control) | 0 |
| v2.25.0, tree kill | **0** |

The live machine also showed the same leak for the other native programs:
18 `curl.exe` (the Claude status fetch) and 12 `node.exe` (the activity
helper, about 83 MB each), all suspended with a dead parent.

## What one render starts

"Render" = one run of `statusline-command.sh`. "In the tree" = a child of the
render, so a cancel can kill it. "Detached" = started through
`spawn_detached` (double fork, plus its own process group on Linux/macOS), so the cancel can't reach it.

| Program | Where (v2.25.0) | How often | Cached | If it hangs | If the render is killed |
|---|---|---|---|---|---|
| `cat` (read stdin) | In the tree | Every render | n/a | Can't (stdin closes) | Harmless (MSYS program) |
| `date` | In the tree | Only bash 3.2 (stock macOS); bash 5 uses `$EPOCHSECONDS` | n/a | n/a | Harmless |
| `git` x2 | Detached refresh job | Once per folder every `git_cache_seconds` (5 s), shared by all sessions | Yes, per folder | Lock stops a repeat for 60 s; `git_timeout` caps it | Unreachable |
| `git` x2 | In the tree | Only with no cache at all: first render in a folder (caches are swept after a day unused), or a git setting changed | Writes the cache | Render waits (as before); `git_timeout` caps it | **Can still orphan** (rare, see finding 9) |
| `mv`, `rm` | Mostly detached | With each git refresh / job end | n/a | n/a | Harmless (MSYS) |
| `node statusline-helper.js` | Detached | When the transcript changed or a timed change is due; one run per session at a time | Parse state per transcript | Lock stops a second run for 30 s | Unreachable |
| `curl` update check | Detached | Every 6 h; a failure retries after 30 s | Yes | `--max-time 3` | Unreachable |
| `curl` OAuth usage | Detached | Every 10 min (`usage_cache_seconds`); failures back off to 30 min | Yes | `--max-time 3` | Unreachable |
| `curl` Claude status (opt-in) | Detached | Every 5 min (`claude_status_cache_seconds`); a failure retries after 30 s | Yes | `--max-time 3` | Unreachable |
| `find` (cache sweep) | Detached | About 1 in 37 git-refresh or helper jobs | n/a | n/a | Unreachable |
| `tput cols` | In the tree | Only if `COLUMNS` is unset (Claude Code sets it) | n/a | n/a | Harmless (MSYS) |
| `timeout` | Wraps git | Only with `git_timeout>0` | n/a | Is the cap | Follows git |
| auto-update (`curl` x5, `sha256sum`) | Detached | Opt-in, once per new version, lock dir | n/a | `--max-time` per file | Unreachable |
| `node statusline-subagent.js` | Started by Claude Code, not by the script | About every 5 s per session while Task subagents run | No (stateless) | Claude Code's timeout | Not affected (no MSYS step) |

Network hosts: `raw.githubusercontent.com` (update check, auto-update),
`api.anthropic.com` (OAuth usage, token sent via curl `--config -`),
`status.claude.com` (opt-in).

## Measurements

Same machine, heavily loaded at the time (59% CPU, 4.4 GB free of 32 GB, ~20
`claude.exe`), so wall-clock numbers swing a lot between runs. Counts are
stable.

`--benchmark 10` (the canned payload, warm cache), three rounds each on the
same machine at a quieter moment, after the pre-release audit fixes:

| | v2.24.0 | v2.25.0 |
|---|---|---|
| Round 1 (min / avg / max) | 361 / 626 / 897 ms | 157 / 254 / 380 ms |
| Round 2 | 433 / 697 / 963 ms | 165 / 311 / 602 ms |
| Round 3 | 417 / 667 / 857 ms | 170 / 287 / 564 ms |

Programs started by one render (shim log, this repo as the folder):

| | v2.24.0 | v2.25.0 |
|---|---|---|
| First render in a folder | cat, date, git x2, node | cat, git x2, mv, node (+ rm in background) |
| Warm, nothing changed | cat, date, git x2 | **cat** |
| Warm, new turn in the transcript | cat, date, git x2, node | cat, node (+ git x2 in background if the cache is over 5 s old) |

Load test, 4 fake sessions rendering every 3 s for 60 s in one folder, the
transcript growing every render, Claude status fetch failing (shims count):

| | v2.24.0 | v2.25.0 |
|---|---|---|
| Renders finished | 22 | 80 |
| `git` started | 44 (all inside renders) | 26 (all in background) |
| `curl` started | 22 | 3 |
| `node` started | 22 | 80 (one per finished render, by design of the test) |
| Native programs per render | 4.0 | 1.36 |
| Render time, average | 11.5 s | 0.52 s |

## Findings, ranked by impact on the machine

1. **Suspended orphans after a cancelled render (Windows). Critical.**
   416 `git.exe` (~2.5 GB) on 5 Nov; 29 git, 18 curl and 12 node (~1 GB)
   again within hours of a cleanup. *Fixed in 2.25.0:* all background work goes
   through `spawn_detached`; git is cached per folder so a render normally runs
   none. Kill storm went from 3 orphans to 0.
2. **Render cost times sessions times refresh rate. High.** Eight sessions at 3 s
   is 2.7 renders a second. v2.24.0 started four programs per render including
   two git runs, and today's renders took 1 to 16 s, so most were cancelled
   before finishing: wasted work and more kills. *Fixed:* a warm render now
   starts one program (`cat`) and never waits on git. Raising
   `refreshInterval` to 5 would cut the remaining load by 40%.
3. **Retry storms from failing fetches. High.** A fetch that fails writes no
   cache, so every render of every session retried it (22 curl a minute with
   four sessions, many at once). The usage fetch also piled up at each 10-minute
   expiry. *Fixed:* `claim_slot` allows one attempt per 30 s across all sessions.
4. **Node helper on every render during a busy turn. Medium.** While Claude
   works the transcript changes every render, so each session starts node
   (30 to 80 MB, 100 to 300 ms CPU) about every refresh. *Partly fixed:* one run
   in flight per session. *Next:* a minimum gap per session (for example 2 s),
   or a long-lived helper process.
5. **Cold transcript parse (P-6). Medium.** The first helper run on a long
   session reads the whole transcript into memory. Already on the roadmap:
   cap the cold parse to the tail of the file.
6. **Subagent panel renderer. Low to medium.** Claude Code runs
   `node statusline-subagent.js` about every 5 s per session while subagents
   run. Not part of the leak. `subagent_rows=false` turns it off.
7. **Hung git on a network folder. Low.** Before, a hung mount blocked every
   render and stacked two more git runs per render. Now the refresh is in the
   background, at most one per folder per 60 s, and the render shows the cached
   value. *Advice:* set `git_timeout=10` for network folders.
8. **Caches that grew forever. Low.** `.statusline-transcript-cache/` kept one
   file per transcript ever seen (269 files, 2.9 MB since June). *Fixed:* swept
   after 7 days unused. Git caches and locks are swept after a day.
9. **Remaining in-tree git (cold cache). Low.** The first render in a folder
   (or after a git setting change) still runs git inside the render, so a
   cancel at the wrong instant can still leave one orphan. The pre-release
   audit found the "5+ minutes idle" case did the same and, on a loaded PC,
   a cold probe over 3 s was cancelled by the next tick before it wrote the
   cache and repeated every tick; that case now shows the old result and
   refreshes in the background, so in-tree git is down to the first render in
   a folder. *Option:* do that cold probe in the background too and show no
   branch for one render.
10. **Non-atomic activity cache writes. Low.** The helper writes its cache in
    place, so a render can read a half-written file and skip line 2 once.
    *Partly fixed:* the bash side no longer re-stamps the file while a helper
    run is in flight.
11. **File locks. None found.** git runs with `--no-optional-locks` (it never
    takes `index.lock`), caches are opened briefly, and the git cache is written
    to a temp file then renamed.

## Reproduce

The harness lives outside the repo. In outline: build a sandbox `HOME` with
`.claude/statusline-helper.js`, a test git repo, and a growing transcript; then
from Node spawn `C:\Program Files\Git\bin\bash.exe -c 'bash statusline-command.sh'`
with `detached: true`, write the JSON to stdin, and after a random delay run
`taskkill /PID <pid> /T /F`. Count leftovers with PowerShell: processes named
git, curl or node whose every thread has `ThreadState Wait` and
`WaitReason Suspended`.
