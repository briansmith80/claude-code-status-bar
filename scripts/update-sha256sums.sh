#!/usr/bin/env bash
#
# Regenerate SHA256SUMS for the files the self-updater downloads and runs.
#
# The runtime self-update (perform_self_update in statusline-command.sh) fetches
# SHA256SUMS from the repo and verifies every staged file against it before
# swapping it in (security finding G1). That manifest therefore MUST stay in sync
# with the three runtime files on the branch the updater pulls from (main).
#
#   - Run this after editing any of the listed files, before committing.
#   - CI (tests.yml) runs `sha256sum -c SHA256SUMS` and fails on drift, so a
#     stale manifest can never reach main.
#
# Usage: scripts/update-sha256sums.sh   (run from anywhere; resolves repo root)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root" || exit 1

files="statusline-command.sh statusline-helper.js statusline-subagent.js"

# Normalise the separator so the manifest is byte-identical across platforms:
# git-bash's sha256sum defaults to binary mode (`hash *name`); rewrite that to
# the canonical text form (`hash  name`) that Linux/macOS produce, so a regen on
# any OS yields the same file (no spurious diffs).
if command -v sha256sum > /dev/null 2>&1; then
  # shellcheck disable=SC2086
  sha256sum $files | sed 's/ \*/  /' > SHA256SUMS
elif command -v shasum > /dev/null 2>&1; then
  # shellcheck disable=SC2086
  shasum -a 256 $files | sed 's/ \*/  /' > SHA256SUMS
else
  echo "error: no sha256sum or shasum found" >&2
  exit 1
fi

echo "Wrote SHA256SUMS:"
cat SHA256SUMS
