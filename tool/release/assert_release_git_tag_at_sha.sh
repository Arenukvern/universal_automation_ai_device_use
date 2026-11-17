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

remote_url="${RELEASE_GIT_REMOTE:-}"
if [[ -z "$remote_url" ]]; then
  command -v gh >/dev/null 2>&1 || fail "gh CLI required"
  [[ -n "${GH_TOKEN:-}" ]] || fail "GH_TOKEN required for authenticated ls-remote"
  remote_url="https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git"
fi

ls_out="$(mktemp)"
trap 'rm -f "$ls_out"' EXIT

if ! GIT_TERMINAL_PROMPT=0 git ls-remote "$remote_url" \
  "refs/tags/${TAG}" "refs/tags/${TAG}^{}" >"$ls_out"; then
  fail "git ls-remote failed for $remote_url (auth or network)"
fi

peeled_sha=""
plain_sha=""
while IFS=$' \t' read -r sha ref _rest; do
  [[ -n "$sha" && -n "$ref" ]] || continue
  case "$ref" in
    "refs/tags/${TAG}^{}")
      peeled_sha="$sha"
      ;;
    "refs/tags/${TAG}")
      plain_sha="$sha"
      ;;
  esac
done <"$ls_out"

if [[ -n "$peeled_sha" ]]; then
  tag_commit="$peeled_sha"
elif [[ -n "$plain_sha" ]]; then
  tag_commit="$plain_sha"
else
  fail "git tag $TAG not found on remote (ls-remote refs/tags/${TAG})"
fi

if [[ "$tag_commit" != "$EXPECTED_SHA" ]]; then
  fail "tag $TAG ($tag_commit) != expected release SHA ($EXPECTED_SHA)"
fi

ok "git tag $TAG points at $EXPECTED_SHA"