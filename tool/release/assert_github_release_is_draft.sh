#!/usr/bin/env bash
# Fail closed when the tag points at a published (non-draft) release — immutable
# GitHub releases cannot accept new assets after publish.
set -euo pipefail

fail() { echo "assert_github_release_is_draft: $*" >&2; exit 1; }
ok() { echo "assert_github_release_is_draft: $*"; }

TAG="${1:-}"
REPO="${GITHUB_REPOSITORY:-${2:-}}"

[[ -n "$TAG" && -n "$REPO" ]] || \
  fail "usage: GITHUB_REPOSITORY=owner/repo assert_github_release_is_draft.sh <tag>"

command -v gh >/dev/null 2>&1 || fail "gh CLI required"

if ! gh release view "$TAG" --repo "$REPO" --json isDraft >/dev/null 2>&1; then
  fail "release not found for tag $TAG"
fi

is_draft="$(gh release view "$TAG" --repo "$REPO" --json isDraft -q .isDraft)"
if [[ "$is_draft" != "true" ]]; then
  cat >&2 <<EOF
assert_github_release_is_draft: release $TAG is already published (not a draft).

GitHub immutable releases reject asset uploads after publish. Configure Release
Please with draft: true and force-tag-creation: true for universal_automation_toolkit,
upload assets while the release is still a draft, then publish with
publish_github_release_from_draft.sh.
EOF
  exit 1
fi

ok "release $TAG is draft (safe for asset upload)"