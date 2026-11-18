#!/usr/bin/env bash
# Verify the GitHub release lists all toolkit binary assets (draft before undraft,
# or published when recovery dispatch already completed upload).
set -euo pipefail

fail() { echo "assert_release_assets_complete_on_draft: $*" >&2; exit 1; }
ok() { echo "assert_release_assets_complete_on_draft: $*"; }

TAG="${1:-}"
VERSION="${2:-}"
REPO="${GITHUB_REPOSITORY:-${3:-}}"
RELEASE_RECOVERY_MODE="${RELEASE_RECOVERY_MODE:-false}"
CHECKSUMS_FILE="${CHECKSUMS_FILE:-}"

[[ -n "$TAG" && -n "$VERSION" && -n "$REPO" ]] || \
  fail "usage: GITHUB_REPOSITORY=owner/repo assert_release_assets_complete_on_draft.sh <tag> <version>"

command -v gh >/dev/null 2>&1 || fail "gh CLI required"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

is_draft="$(gh release view "$TAG" --repo "$REPO" --json isDraft -q .isDraft 2>/dev/null || true)"
if [[ "$is_draft" == "true" ]]; then
  exec bash "$script_dir/assert_release_assets_complete.sh" "$TAG" "$VERSION" "$REPO"
fi

if [[ "$RELEASE_RECOVERY_MODE" == "true" ]]; then
  bash "$script_dir/assert_release_assets_complete.sh" "$TAG" "$VERSION" "$REPO"
  if [[ -n "$CHECKSUMS_FILE" && -f "$CHECKSUMS_FILE" ]]; then
    bash "$script_dir/compare_remote_checksums_with_local.sh" "$TAG" "$CHECKSUMS_FILE" "$REPO"
  fi
  ok "published release $TAG has complete matching asset set (recovery)"
  exit 0
fi

fail "release $TAG is not a draft (refusing draft-only asset verification)"