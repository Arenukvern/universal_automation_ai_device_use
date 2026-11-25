#!/usr/bin/env bash
# Create or update a draft GitHub release for universal_automation_toolkit-v* tags
# (dart_changesets pushes the git tag; binaries publish uploads assets to the draft).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RELEASE_TAG="${1:-}"
if [[ -z "$RELEASE_TAG" ]]; then
  echo "usage: $0 <release_tag>" >&2
  exit 2
fi

fail() { echo "create_toolkit_draft_github_release: $*" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || fail "gh required"
command -v dart >/dev/null 2>&1 || fail "dart required"

if [[ ! "$RELEASE_TAG" =~ ^universal_automation_toolkit-v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  fail "expected universal_automation_toolkit-v semver tag (got: $RELEASE_TAG)"
fi

VERSION="${RELEASE_TAG#universal_automation_toolkit-v}"
REPO="${GITHUB_REPOSITORY:-Arenukvern/universal_automation_ai_device_use}"

NOTES_FILE="$(mktemp)"

(
  cd "$ROOT_DIR"
  dart run dart_changesets@^1.0.2 release-notes \
    --package universal_automation_toolkit \
    --version "$VERSION" >"$NOTES_FILE"
) || fail "dart_changesets release-notes failed"

VIEW_ERR="$(mktemp)"
trap 'rm -f "$VIEW_ERR" "$NOTES_FILE"' EXIT

if gh release view "$RELEASE_TAG" --repo "$REPO" >/dev/null 2>"$VIEW_ERR"; then
  is_draft="$(gh release view "$RELEASE_TAG" --repo "$REPO" --json isDraft -q .isDraft)"
  if [[ "$is_draft" != "true" ]]; then
    fail "release $RELEASE_TAG already published; refusing to edit notes"
  fi
  gh release edit "$RELEASE_TAG" --repo "$REPO" --notes-file "$NOTES_FILE" --draft=true
  echo "Updated draft GitHub release $RELEASE_TAG"
else
  if ! grep -qiE 'release not found|not found|HTTP 404|Could not find' "$VIEW_ERR"; then
    fail "gh release view failed (not a missing release): $(cat "$VIEW_ERR")"
  fi
  gh release create "$RELEASE_TAG" --repo "$REPO" --draft --verify-tag --notes-file "$NOTES_FILE"
  echo "Created draft GitHub release $RELEASE_TAG"
fi