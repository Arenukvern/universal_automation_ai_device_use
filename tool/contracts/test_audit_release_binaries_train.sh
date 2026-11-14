#!/usr/bin/env bash
# bash 3.2 compatible (macOS default).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/tool/release/audit_release_binaries_train.sh"

fail() { echo "test_audit_release_binaries_train: $*" >&2; exit 1; }
ok() { echo "test_audit_release_binaries_train: $*"; }

[[ -f "$SCRIPT" ]] || fail "missing audit script"
chmod +x "$SCRIPT"

TOOLKIT_RELEASE_CREATED=false RELEASE_BINARIES_BUILD_RESULT=skipped \
  bash "$SCRIPT" || fail "no toolkit release should pass"

TOOLKIT_RELEASE_CREATED=true RELEASE_BINARIES_BUILD_RESULT=success \
  bash "$SCRIPT" || fail "success path"

if TOOLKIT_RELEASE_CREATED=true RELEASE_BINARIES_BUILD_RESULT=failure \
  bash "$SCRIPT" 2>/dev/null; then
  fail "build failure must fail"
fi

ok "audit_release_binaries_train smoke OK"