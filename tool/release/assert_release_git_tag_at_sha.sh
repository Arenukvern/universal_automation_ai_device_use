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
remote_label=""
if [[ -n "$remote_url" ]]; then
  if [[ "$remote_url" == *'@'* ]]; then
    fail "RELEASE_GIT_REMOTE must not embed credentials"
  fi
  remote_label="$remote_url"
else
  [[ -n "${GH_TOKEN:-}" ]] || fail "GH_TOKEN required for authenticated ls-remote"
  remote_url="https://github.com/${REPO}.git"
  remote_label="$REPO"
fi

ls_out="$(mktemp)"
trap 'rm -f "$ls_out"' EXIT

run_ls_remote() {
  if [[ -n "${RELEASE_GIT_REMOTE:-}" ]]; then
    GIT_TERMINAL_PROMPT=0 git ls-remote "$remote_url" \
      "refs/tags/${TAG}" "refs/tags/${TAG}^{}"
    return
  fi
  local auth_b64
  auth_b64="$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')"
  GIT_TERMINAL_PROMPT=0 git \
    -c "http.extraheader=AUTHORIZATION: basic ${auth_b64}" \
    ls-remote "$remote_url" "refs/tags/${TAG}" "refs/tags/${TAG}^{}"
}

if ! run_ls_remote >"$ls_out"; then
  fail "git ls-remote failed for $remote_label (auth or network)"
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
  fail "git tag $TAG not found on $remote_label (ls-remote refs/tags/${TAG})"
fi

if [[ "$tag_commit" != "$EXPECTED_SHA" ]]; then
  fail "tag $TAG ($tag_commit) != expected release SHA ($EXPECTED_SHA)"
fi

if [[ -n "${RELEASE_GIT_REMOTE:-}" ]]; then
  ok "git tag $TAG points at $EXPECTED_SHA (remote $remote_label)"
else
  ok "git tag $TAG points at $EXPECTED_SHA on $REPO"
fi