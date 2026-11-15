#!/usr/bin/env bash
set -euo pipefail

fail() { echo "append_draft_release_binary_notes: $*" >&2; exit 1; }

TAG="${1:-}"
NOTES_FILE="${2:-}"
REPO="${GITHUB_REPOSITORY:-${3:-}}"

[[ -n "$TAG" && -n "$NOTES_FILE" && -n "$REPO" && -f "$NOTES_FILE" ]] || \
  fail "usage: append_draft_release_binary_notes.sh <tag> <notes.md>"

command -v gh >/dev/null 2>&1 || fail "gh CLI required"

existing="$(gh release view "$TAG" --repo "$REPO" --json body -q .body 2>/dev/null || true)"
new_notes="$(cat "$NOTES_FILE")"
if [[ -n "$existing" ]]; then
  gh release edit "$TAG" --repo "$REPO" --notes "${existing}

${new_notes}"
else
  gh release edit "$TAG" --repo "$REPO" --notes "$new_notes"
fi