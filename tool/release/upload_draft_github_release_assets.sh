#!/usr/bin/env bash
# Upload binary assets to the existing draft release (softprops cannot target drafts by tag).
set -euo pipefail

fail() { echo "upload_draft_github_release_assets: $*" >&2; exit 1; }
ok() { echo "upload_draft_github_release_assets: $*"; }

TAG="${1:-}"
ASSETS_DIR="${2:-}"
REPO="${GITHUB_REPOSITORY:-${3:-}}"

[[ -n "$TAG" && -n "$ASSETS_DIR" && -n "$REPO" ]] || \
  fail "usage: GITHUB_REPOSITORY=owner/repo upload_draft_github_release_assets.sh <tag> <assets_dir>"

command -v gh >/dev/null 2>&1 || fail "gh CLI required"

is_draft="$(gh release view "$TAG" --repo "$REPO" --json isDraft -q .isDraft 2>/dev/null || true)"
[[ "$is_draft" == "true" ]] || fail "expected draft release for tag $TAG (immutable upload path)"

[[ -d "$ASSETS_DIR" ]] || fail "assets dir missing: $ASSETS_DIR"

gh release upload "$TAG" --repo "$REPO" --clobber \
  "$ASSETS_DIR"/*

ok "uploaded assets to draft $TAG"