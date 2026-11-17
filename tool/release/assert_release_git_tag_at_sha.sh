#!/usr/bin/env bash
# contents:read — git tags are visible; draft GitHub Releases are not.
set -euo pipefail

fail() { echo "assert_release_git_tag_at_sha: $*" >&2; exit 1; }
ok() { echo "assert_release_git_tag_at_sha: $*"; }

TAG="${1:-}"
EXPECTED_SHA="${RELEASE_SHA:-${2:-}}"
REPO="${GITHUB_REPOSITORY:-${3:-}}"

[[ -n "$TAG" && -n "$EXPECTED_SHA" && -n "$REPO" ]] || \
  fail "usage: RELEASE_SHA=<sha> GITHUB_REPOSITORY=owner/repo assert_release_git_tag_at_sha.sh <tag> [sha]"

if [[ ! "$TAG" =~ ^universal_automation_toolkit-v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "invalid tag format: $TAG"
fi

command -v git >/dev/null 2>&1 || fail "git required"
command -v gh >/dev/null 2>&1 || fail "gh CLI required"
[[ -n "${GH_TOKEN:-}" ]] || fail "GH_TOKEN required for authenticated ls-remote"

remote_url="https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git"
tag_commit=""
while IFS= read -r sha _rest; do
  [[ -n "$sha" ]] && tag_commit="$sha"
done < <(GIT_TERMINAL_PROMPT=0 git ls-remote "$remote_url" "refs/tags/${TAG}^{commit}" 2>/dev/null || true)

[[ -n "$tag_commit" ]] || fail "git tag $TAG not found on $REPO (ls-remote refs/tags/${TAG}^{commit})"

if [[ "$tag_commit" != "$EXPECTED_SHA" ]]; then
  fail "tag $TAG^{commit} ($tag_commit) != expected release SHA ($EXPECTED_SHA)"
fi

ok "git tag $TAG points at $EXPECTED_SHA on $REPO"