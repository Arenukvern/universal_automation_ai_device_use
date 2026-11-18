#!/usr/bin/env bash
# Compare checksums.txt on a GitHub release with a local checksums file.
set -euo pipefail

fail() { echo "compare_remote_checksums_with_local: $*" >&2; exit 1; }
ok() { echo "compare_remote_checksums_with_local: $*"; }

TAG="${1:-}"
LOCAL_FILE="${2:-}"
REPO="${GITHUB_REPOSITORY:-${3:-}}"

[[ -n "$TAG" && -n "$LOCAL_FILE" && -n "$REPO" ]] || \
  fail "usage: GITHUB_REPOSITORY=owner/repo compare_remote_checksums_with_local.sh <tag> <local_checksums>"

command -v gh >/dev/null 2>&1 || fail "gh CLI required"
command -v curl >/dev/null 2>&1 || fail "curl required"
command -v jq >/dev/null 2>&1 || fail "jq required"

[[ -f "$LOCAL_FILE" ]] || fail "local checksums missing: $LOCAL_FILE"

assets_json="$(gh release view "$TAG" --repo "$REPO" --json assets)"
url="$(echo "$assets_json" | jq -r '.assets[] | select(.name=="checksums.txt") | .url' | head -n1)"
[[ -n "$url" && "$url" != "null" ]] || fail "release $TAG has no checksums.txt asset"

work="$(mktemp)"
trap 'rm -f "$work"' EXIT
if ! curl -fsSL \
  -H "Accept: application/octet-stream" \
  -H "Authorization: Bearer ${GH_TOKEN:?GH_TOKEN required}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "$url" \
  -o "$work"; then
  fail "download checksums.txt failed"
fi

if ! cmp -s "$work" "$LOCAL_FILE"; then
  fail "remote checksums.txt on $TAG does not match local $LOCAL_FILE"
fi

ok "remote and local checksums.txt match for $TAG"