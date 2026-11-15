#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
V="$ROOT/tool/release/validate_release_checksums_file.sh"
FIX="$ROOT/tool/contracts/fixtures/release_checksums"
fail() { echo "test_validate_release_checksums: $*" >&2; exit 1; }

run_neg() {
  local name="$1"
  if bash "$V" 0.6.2 "$FIX/$name" 2>/dev/null; then
    fail "expected failure for $name"
  fi
}

good="$FIX/good.txt"
[[ -f "$good" ]] || fail "missing good fixture"
bash "$V" "0.6.2" "$good"

run_neg "three_of_four.txt"
run_neg "empty.txt"
run_neg "duplicate.txt"
run_neg "traversal.txt"

echo "test_validate_release_checksums: OK"