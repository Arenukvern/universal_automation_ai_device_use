#!/usr/bin/env bash
# bash 3.2 compatible (macOS default): no declare -A, no mapfile.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail() { echo "check_release_workflow: $*" >&2; exit 1; }
ok() { echo "check_release_workflow: $*"; }

dart run "$ROOT_DIR/tool/check_release_workflow.dart"

run_negative_dir() {
  local mode="$1"
  local dir="$2"
  local flag=""
  case "$mode" in
    build|publish|dispatch) flag="--workflow" ;;
    pr) flag="--pr-smoke-workflow" ;;
    please) flag="--please-caller-workflow" ;;
    *) fail "unknown negative mode: $mode" ;;
  esac
  shopt -s nullglob
  for negative in "$dir"/negative_*.yml; do
    name="$(basename "$negative")"
    exp="${negative}.expected"
    if [[ ! -f "$exp" ]]; then
      fail "negative fixture missing .expected file: $name"
    fi
    want="$(tr -d '\n' <"$exp")"
    if printf '%s' "$want" | grep -qi 'invalid YAML'; then
      fail "negative $name: .expected must not pin invalid YAML (fix the fixture)"
    fi
    set +e
    out="$(dart run "$ROOT_DIR/tool/check_release_workflow.dart" "$flag" "$negative" 2>&1)"
    st=$?
    set -e
    if [[ "$st" -eq 0 ]]; then
      fail "negative fixture must fail but passed: $name"
    fi
    if ! printf '%s\n' "$out" | grep -qF "$want"; then
      fail "negative $name: output must contain: $want (got: $out)"
    fi
    ok "negative fixture rejected: $name"
  done
}

FIX="$ROOT_DIR/tool/contracts/fixtures"
run_negative_dir build "$FIX/release_workflow"
run_negative_dir publish "$FIX/release_workflow_publish"
run_negative_dir dispatch "$FIX/release_workflow_dispatch"
run_negative_dir pr "$FIX/release_workflow_pr"
run_negative_dir please "$FIX/release_workflow_please"

ok "release_binaries workflow structure OK"