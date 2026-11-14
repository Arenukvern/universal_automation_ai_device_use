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

for event in workflow_dispatch push workflow_call; do
  : >"$out"
  GITHUB_EVENT_NAME="$event" \
    DISPATCH_RELEASE_TAG=universal_automation_toolkit-v2.0.0 \
    DRY_RUN=false \
    GITHUB_OUTPUT="$out" \
    bash "$SCRIPT" || fail "production tag with event=$event"
  grep -q 'release_tag=universal_automation_toolkit-v2.0.0' "$out" || fail "event=$event release_tag"
done

if GITHUB_EVENT_NAME=workflow_dispatch DISPATCH_RELEASE_TAG=bad-tag DRY_RUN=false GITHUB_OUTPUT="$out" bash "$SCRIPT" 2>/dev/null; then
  fail "invalid tag must fail"
fi

sha="0123456789abcdef0123456789abcdef01234567"
: >"$out"
GITHUB_EVENT_NAME=workflow_dispatch \
  DISPATCH_RELEASE_TAG="$sha" \
  DRY_RUN=true \
  GITHUB_OUTPUT="$out" \
  bash "$SCRIPT" || fail "dry_run sha"

grep -q "release_ref=$sha" "$out" || fail "dry_run release_ref"
grep -q '^release_tag=$' "$out" || fail "dry_run empty release_tag"

partial="0123456789abcdef"
if GITHUB_EVENT_NAME=workflow_dispatch DISPATCH_RELEASE_TAG="$partial" DRY_RUN=true GITHUB_OUTPUT="$out" bash "$SCRIPT" 2>/dev/null; then
  fail "partial SHA must fail"
fi

ok "resolve_release_tag smoke OK"