#!/usr/bin/env bash
# Postflight: GitHub release must list every expected binary asset and checksums.txt.
set -euo pipefail

fail() { echo "assert_release_assets_complete: $*" >&2; exit 1; }
ok() { echo "assert_release_assets_complete: $*"; }

TAG="${1:-}"
VERSION="${2:-}"
REPO="${GITHUB_REPOSITORY:-${3:-}}"

[[ -n "$TAG" && -n "$VERSION" && -n "$REPO" ]] || \
  fail "usage: GITHUB_REPOSITORY=owner/repo assert_release_assets_complete.sh <tag> <version>"

command -v gh >/dev/null 2>&1 || fail "gh CLI required"
command -v jq >/dev/null 2>&1 || fail "jq required"

required=(
  "universal_automation_${VERSION}_darwin-arm64.tar.gz"
  "universal_automation_${VERSION}_darwin-x64.tar.gz"
  "universal_automation_${VERSION}_linux-x64.tar.gz"
  "universal_automation_${VERSION}_windows-x64.zip"
  "checksums.txt"
)

json="$(gh release view "$TAG" --repo "$REPO" --json assets)"
names=()
while IFS= read -r name; do
  [[ -n "$name" ]] && names+=("$name")
done < <(echo "$json" | jq -r '.assets[].name')

has_name() {
  local want="$1"
  local n
  for n in "${names[@]}"; do
    if [[ "$n" == "$want" ]]; then
      return 0
    fi
  done
  return 1
}

missing=()
for want in "${required[@]}"; do
  if ! has_name "$want"; then
    missing+=("$want")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  fail "release $TAG on $REPO missing assets: ${missing[*]}"
fi

ok "release $TAG has all ${#required[@]} required assets"