#!/usr/bin/env bash
# Idempotent: publish a draft GitHub release (immutable-safe upload path).
set -euo pipefail

fail() { echo "publish_github_release_from_draft: $*" >&2; exit 1; }
ok() { echo "publish_github_release_from_draft: $*"; }

TAG="${1:-}"
REPO="${GITHUB_REPOSITORY:-${2:-}}"

[[ -n "$TAG" && -n "$REPO" ]] || \
  fail "usage: GITHUB_REPOSITORY=owner/repo publish_github_release_from_draft.sh <tag>"

command -v gh >/dev/null 2>&1 || fail "gh CLI required"

if ! gh release view "$TAG" --repo "$REPO" --json isDraft >/dev/null 2>&1; then
  fail "release not found for tag $TAG"
fi

is_draft="$(gh release view "$TAG" --repo "$REPO" --json isDraft -q .isDraft)"
if [[ "$is_draft" == "true" ]]; then
  gh release edit "$TAG" --repo "$REPO" --draft=false
  ok "published draft release $TAG"
  exit 0
fi

ok "release $TAG already published (idempotent no-op)"