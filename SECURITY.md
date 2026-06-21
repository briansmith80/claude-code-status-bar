# Security Policy

## Supported versions

The latest released version is supported. Please update (`bash ~/.claude/statusline-command.sh --update`,
or re-run the installer) and confirm the issue reproduces before reporting.

## Reporting a vulnerability

Please report security issues **privately**, not in a public issue:

- Use GitHub's **"Report a vulnerability"** button under this repository's
  **Security** tab (private security advisories), or
- If you can't use that, open a minimal public issue asking us to make contact,
  without including exploit details.

We aim to acknowledge reports within a few days and will credit reporters who
wish to be credited once a fix ships.

## Security posture

This is a local bash status line (the Node.js helpers are optional). Key points:

- **Nothing is downloaded or executed on the render path** (no `npx`/`npm exec`).
  The only network calls are the opt-in update check (to this project's GitHub
  repo) and the OAuth usage-API fallback (to Anthropic's servers, on older
  Claude Code), both run in detached background subshells.
- **Checksum-verified updates:** the self-updater (`--update` / opt-in
  `auto_update`) and the installers verify every downloaded file against a
  per-release `SHA256SUMS` and abort on any mismatch.
- **No injection from untrusted fields:** paths, branch names, model/vim labels,
  and transcript-derived text are stripped of ANSI/control bytes and both render
  lines are printed with `printf '%s'` (never `%b`), so field text cannot decode
  into live terminal control sequences.
- **Token handling:** the OAuth token (when the usage fallback is used) is passed
  to curl via stdin, never on the command line; caches and temp files are created
  with `umask 077`. No telemetry, no analytics.

See the **Security** section of the [README](README.md) and [PRIVACY.md](PRIVACY.md)
for more detail.
