#!/usr/bin/env bash
# Fail closed when no GitHub Release exists for the tag (draft or published).
# Uses paginated /releases; releases/tags/{tag} ignores drafts.
set -euo pipefail

fail() { echo "assert_github_release_exists: $*" >&2; exit 1; }
ok() { echo "assert_github_release_exists: $*"; }

TAG="${1:-}"
REPO="${GITHUB_REPOSITORY:-${2:-}}"

[[ -n "$TAG" && -n "$REPO" ]] || fail "usage: GITHUB_REPOSITORY=owner/repo assert_github_release_exists.sh <tag>"

if [[ ! "$TAG" =~ ^universal_automation_toolkit-v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "invalid tag format: $TAG"
fi

command -v gh >/dev/null 2>&1 || fail "gh CLI required"
command -v jq >/dev/null 2>&1 || fail "jq required"

found="$(
  gh api --paginate "repos/${REPO}/releases" \
    | jq -s --arg t "$TAG" 'add | map(select(.tag_name == $t)) | length'
)"

if [[ "${found:-0}" -lt 1 ]]; then
  fail "no GitHub release (draft or published) for tag $TAG on $REPO"
fi

ok "GitHub release for $TAG exists on $REPO (draft or published)"