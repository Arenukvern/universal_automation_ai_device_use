#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/tool/release/resolve_release_tag.sh"

fail() { echo "test_resolve_release_tag: $*" >&2; exit 1; }
ok() { echo "test_resolve_release_tag: $*"; }

[[ -x "$SCRIPT" ]] || chmod +x "$SCRIPT"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
out="$tmpdir/out.txt"

GITHUB_EVENT_NAME=workflow_dispatch \
  DISPATCH_RELEASE_TAG=universal_automation_toolkit-v1.2.3 \
  DRY_RUN=false \
  GITHUB_OUTPUT="$out" \
  bash "$SCRIPT" || fail "valid tag"

grep -q 'release_tag=universal_automation_toolkit-v1.2.3' "$out" || fail "release_tag output"
grep -q 'version=1.2.3' "$out" || fail "version output"
grep -q 'release_ref=refs/tags/universal_automation_toolkit-v1.2.3' "$out" || fail "release_ref output"

if GITHUB_EVENT_NAME=workflow_dispatch DISPATCH_RELEASE_TAG=bad-tag DRY_RUN=false GITHUB_OUTPUT="$out" bash "$SCRIPT" 2>/dev/null; then
  fail "invalid tag must fail"
fi

sha="0123456789abcdef0123456789abcdef0123456789"
: >"$out"
GITHUB_EVENT_NAME=workflow_dispatch \
  DISPATCH_RELEASE_TAG="$sha" \
  DRY_RUN=true \
  GITHUB_OUTPUT="$out" \
  bash "$SCRIPT" || fail "dry_run sha"

grep -q "release_ref=$sha" "$out" || fail "dry_run release_ref"
grep -q 'release_tag=$' "$out" || grep -q '^release_tag=$' "$out" || true

ok "resolve_release_tag smoke OK"