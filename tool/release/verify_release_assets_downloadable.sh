#!/usr/bin/env bash
set -euo pipefail

fail() { echo "verify_release_assets_downloadable: $*" >&2; exit 1; }
ok() { echo "verify_release_assets_downloadable: $*"; }

TAG="${1:-}"
VERSION="${2:-}"
REPO="${GITHUB_REPOSITORY:-${3:-}}"

[[ -n "$TAG" && -n "$VERSION" && -n "$REPO" ]] || \
  fail "usage: GITHUB_REPOSITORY=owner/repo verify_release_assets_downloadable.sh <tag> <version>"

command -v gh >/dev/null 2>&1 || fail "gh CLI required"
command -v curl >/dev/null 2>&1 || fail "curl required"
command -v jq >/dev/null 2>&1 || fail "jq required"

is_draft="$(gh release view "$TAG" --repo "$REPO" --json isDraft -q .isDraft)"
[[ "$is_draft" != "true" ]] || fail "release $TAG is still a draft"

archives=(
  "universal_automation_${VERSION}_darwin-arm64.tar.gz"
  "universal_automation_${VERSION}_darwin-x64.tar.gz"
  "universal_automation_${VERSION}_linux-x64.tar.gz"
  "universal_automation_${VERSION}_windows-x64.zip"
)

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

assets_json="$(gh release view "$TAG" --repo "$REPO" --json assets)"
download_asset() {
  local name="$1"
  url="$(echo "$assets_json" | jq -r --arg n "$name" '.assets[] | select(.name==$n) | .url' | head -n1)"
  [[ -n "$url" && "$url" != "null" ]] || fail "missing release asset metadata for $name"
  if ! curl -fsSL \
    -H "Accept: application/octet-stream" \
    -H "Authorization: Bearer ${GH_TOKEN:?GH_TOKEN required}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$url" \
    -o "$work/$name"; then
    fail "download failed for $name"
  fi
}

for name in "${archives[@]}"; do
  download_asset "$name"
done
download_asset "checksums.txt"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$script_dir/validate_release_checksums_file.sh" "$VERSION" "$work/checksums.txt"

while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  expected="${line%% *}"
  file="${line#* }"
  file="$(printf '%s' "$file" | awk '{print $NF}')"
  [[ -f "$work/$file" ]] || fail "checksums.txt references missing file $file"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$work/$file" | awk '{print $1}')"
  else
    actual="$(shasum -a 256 "$work/$file" | awk '{print $1}')"
  fi
  [[ "$expected" == "$actual" ]] || fail "checksum mismatch for $file"
done <"$work/checksums.txt"

ok "downloaded and verified release assets for $TAG"