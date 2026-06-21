<!-- Thanks for contributing! See CONTRIBUTING.md for the design principles. -->

## What & why

<!-- What does this change, and what problem does it solve? -->

## Checklist

- [ ] `bats tests/` passes and I added/updated tests for the change
- [ ] ShellCheck is clean (CI enforces this)
- [ ] Kept the design constraints (pure bash, no jq, bash 3.2, never block, REPLY convention) — see CONTRIBUTING.md
- [ ] If I changed `statusline-command.sh` / `statusline-helper.js` / `statusline-subagent.js`, I ran `scripts/update-sha256sums.sh`
- [ ] Updated docs (README / CLAUDE.md / `statusline.conf.example`) for any new config
- [ ] Did **not** bump `VERSION` / `CHANGELOG.md` (releases are batched by the maintainer)

## Notes for reviewers

<!-- Anything to call out: trade-offs, follow-ups, screenshots of the rendered bar. -->
