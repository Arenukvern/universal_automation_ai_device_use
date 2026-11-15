#!/usr/bin/env bash
# Postflight on a published release: download each archive + checksums from the
# public asset URL and verify SHA-256 against checksums.txt.
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
if [[ "$is_draft" == "true" ]]; then
  fail "release $TAG is still a draft; publish before download verification"
fi

required=(
  "universal_automation_${VERSION}_darwin-arm64.tar.gz"
  "universal_automation_${VERSION}_darwin-x64.tar.gz"
  "universal_automation_${VERSION}_linux-x64.tar.gz"
  "universal_automation_${VERSION}_windows-x64.zip"
  "checksums.txt"
)

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

assets_json="$(gh release view "$TAG" --repo "$REPO" --json assets)"
for name in "${required[@]}"; do
  url="$(echo "$assets_json" | jq -r --arg n "$name" '.assets[] | select(.name==$n) | .browser_download_url' | head -n1)"
  [[ -n "$url" && "$url" != "null" ]] || fail "missing release asset metadata for $name"

  if ! curl -fsSL "$url" -o "$work/$name"; then
    fail "download failed for $name"
  fi
done

while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  expected="${line%% *}"
  file="${line#* }"
  file="${file# }"
  [[ -f "$work/$file" ]] || fail "checksums.txt references missing file $file"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$work/$file" | awk '{print $1}')"
  else
    actual="$(shasum -a 256 "$work/$file" | awk '{print $1}')"
  fi
  if [[ "$expected" != "$actual" ]]; then
    fail "checksum mismatch for $file (expected $expected, got $actual)"
  fi
done <"$work/checksums.txt"

ok "downloaded and verified ${#required[@]} assets for $TAG"