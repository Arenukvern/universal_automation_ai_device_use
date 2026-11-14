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
  GITHUB_OUTPUT="$out" \
  bash "$SCRIPT" || fail "valid tag"

grep -q 'release_tag=universal_automation_toolkit-v1.2.3' "$out" || fail "release_tag output"
grep -q 'version=1.2.3' "$out" || fail "version output"

if GITHUB_EVENT_NAME=workflow_dispatch DISPATCH_RELEASE_TAG=bad-tag GITHUB_OUTPUT="$out" bash "$SCRIPT" 2>/dev/null; then
  fail "invalid tag must fail"
fi

ok "resolve_release_tag smoke OK"