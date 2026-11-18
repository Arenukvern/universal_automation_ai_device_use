#!/usr/bin/env bash
# Fail closed when the tag points at a published (non-draft) release — immutable
# GitHub releases cannot accept new assets after publish, except recovery dispatch.
set -euo pipefail

fail() { echo "assert_github_release_is_draft: $*" >&2; exit 1; }
ok() { echo "assert_github_release_is_draft: $*"; }

TAG="${1:-}"
REPO="${GITHUB_REPOSITORY:-${2:-}}"
VERSION="${VERSION:-}"
RELEASE_RECOVERY_MODE="${RELEASE_RECOVERY_MODE:-false}"
CHECKSUMS_FILE="${CHECKSUMS_FILE:-}"

[[ -n "$TAG" && -n "$REPO" ]] || \
  fail "usage: GITHUB_REPOSITORY=owner/repo assert_github_release_is_draft.sh <tag>"

command -v gh >/dev/null 2>&1 || fail "gh CLI required"

if ! gh release view "$TAG" --repo "$REPO" --json isDraft >/dev/null 2>&1; then
  fail "release not found for tag $TAG"
fi

is_draft="$(gh release view "$TAG" --repo "$REPO" --json isDraft -q .isDraft)"
if [[ "$is_draft" == "true" ]]; then
  ok "release $TAG is draft (safe for asset upload)"
  exit 0
fi

if [[ "$RELEASE_RECOVERY_MODE" == "true" ]]; then
  [[ -n "$VERSION" ]] || fail "VERSION required for published recovery verification"
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if ! bash "$script_dir/assert_release_assets_complete.sh" "$TAG" "$VERSION" "$REPO"; then
    cat >&2 <<EOF
assert_github_release_is_draft: release $TAG is published but incomplete.

Re-run failed jobs on the build workflow, or dispatch **Release binaries (toolkit)**
with release_tag=$TAG after the draft has all five assets. Do not re-draft.
EOF
    exit 1
  fi
  if [[ -n "$CHECKSUMS_FILE" && -f "$CHECKSUMS_FILE" ]]; then
    bash "$script_dir/compare_remote_checksums_with_local.sh" "$TAG" "$CHECKSUMS_FILE" "$REPO"
  fi
  ok "release $TAG is published with a complete matching asset set (no changes)"
  exit 0
fi

cat >&2 <<EOF
assert_github_release_is_draft: release $TAG is already published (not a draft).

GitHub immutable releases reject asset uploads after publish. Configure Release
Please with draft: true and force-tag-creation: true for universal_automation_toolkit,
upload assets while the release is still a draft, then publish with
publish_github_release_from_draft.sh.

For manual recovery, workflow_dispatch **Release binaries (toolkit)** with this tag.
EOF
exit 1