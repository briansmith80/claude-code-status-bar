# Privacy Policy

**claude-code-status-bar** is a local status line for Claude Code: a bash script
(with an optional Node.js helper) that runs entirely on your own machine.

## What it collects

**Nothing.** The tool has no analytics, no telemetry, and no tracking of any
kind. It does not collect, store, or transmit any personal data, usage data, or
identifiers to the author or to any third party.

## What runs locally

It reads the JSON that Claude Code passes on stdin (model, context window, usage
limits, cost, git state, transcript path) to render the status line. Optional
caches (parsed activity, usage, the update-check result) are written only under
your `~/.claude/` directory with owner-only permissions (`umask 077`). Nothing
leaves your machine as a result of normal rendering.

## Network access

The only network requests the tool can make are:

- **Update check** (default on, version string only): roughly every 6 hours it
  fetches the latest `VERSION` file from this project's public GitHub repository
  to show an "update available" notice. No information about you is sent.
  Auto-*installing* updates is opt-in (`auto_update`, off by default) and
  verifies every download against a per-release `SHA256SUMS` checksum before
  installing.
- **Usage-limit fallback** (only on Claude Code versions that don't send rate
  limits on stdin): the tool can call Anthropic's own usage API
  (`api.anthropic.com`) using your existing Claude credentials, read from your
  local macOS Keychain or `~/.claude/.credentials.json`, to display your 5h/7d
  usage. This request goes only to Anthropic's servers. The token is passed to
  curl via stdin (never on the command line) and is never logged or stored by
  this tool; only the non-sensitive usage response is cached locally.

There are no other network calls, no third-party servers, and no telemetry
endpoints.

## Permissions

The tool does not require or request "bypass permissions" mode and does not
modify shared system files. It only reads Claude Code's stdin and writes within
your `~/.claude/` directory.

## Contact

Questions or concerns: please open an issue at
<https://github.com/briansmith80/claude-code-status-bar/issues>.

_Last updated: 2026-06-21_
