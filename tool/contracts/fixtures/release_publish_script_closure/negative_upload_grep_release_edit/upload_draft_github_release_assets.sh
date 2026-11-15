#!/usr/bin/env bash
set -euo pipefail

fail() { echo "upload_draft_github_release_assets: $*" >&2; exit 1; }
ok() { echo "upload_draft_github_release_assets: $*"; }

TAG="${1:-}"
ASSETS_DIR="${2:-}"
VERSION="${VERSION:-${3:-}}"
REPO="${GITHUB_REPOSITORY:-${4:-}}"

[[ -n "$TAG" && -n "$ASSETS_DIR" && -n "$VERSION" && -n "$REPO" ]] || \
  fail "usage: VERSION=... GITHUB_REPOSITORY=owner/repo upload_draft_github_release_assets.sh <tag> <assets_dir>"

command -v gh >/dev/null 2>&1 || fail "gh CLI required"

is_draft="$(gh release view "$TAG" --repo "$REPO" --json isDraft -q .isDraft 2>/dev/null || true)"
[[ "$is_draft" == "true" ]] || fail "expected draft release for tag $TAG (immutable upload path)"

[[ -d "$ASSETS_DIR" ]] || fail "assets dir missing: $ASSETS_DIR"

assets=(
  "${ASSETS_DIR}/universal_automation_${VERSION}_darwin-arm64.tar.gz"
  "${ASSETS_DIR}/universal_automation_${VERSION}_darwin-x64.tar.gz"
  "${ASSETS_DIR}/universal_automation_${VERSION}_linux-x64.tar.gz"
  "${ASSETS_DIR}/universal_automation_${VERSION}_windows-x64.zip"
  "${ASSETS_DIR}/checksums.txt"
)
for f in "${assets[@]}"; do
  [[ -f "$f" ]] || fail "missing asset file: $f"
done

gh release edit "$TAG" --repo "$REPO" --draft=false
gh release upload "$TAG" --repo "$REPO" "${assets[@]}"

ok "uploaded assets to draft $TAG"