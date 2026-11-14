#!/usr/bin/env bash
# bash 3.2 compatible (macOS default): no declare -A, no mapfile.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail() { echo "check_release_workflow: $*" >&2; exit 1; }
ok() { echo "check_release_workflow: $*"; }

dart run "$ROOT_DIR/tool/check_release_workflow.dart"

fixtures_dir="$ROOT_DIR/tool/contracts/fixtures/release_workflow"
shopt -s nullglob
for negative in "$fixtures_dir"/negative_*.yml; do
  name="$(basename "$negative")"
  set +e
  out="$(dart run "$ROOT_DIR/tool/check_release_workflow.dart" --workflow "$negative" 2>&1)"
  st=$?
  set -e
  if [[ "$st" -eq 0 ]]; then
    fail "negative fixture must fail but passed: $name"
  fi
  exp="${negative}.expected"
  if [[ -f "$exp" ]]; then
  want="$(tr -d '\n' <"$exp")"
    if ! printf '%s\n' "$out" | grep -qF "$want"; then
      fail "negative $name: output must contain: $want (got: $out)"
    fi
  fi
  ok "negative fixture rejected: $name"
done

pr_fixtures_dir="$ROOT_DIR/tool/contracts/fixtures/release_workflow_pr"
shopt -s nullglob
for negative in "$pr_fixtures_dir"/negative_*.yml; do
  name="$(basename "$negative")"
  set +e
  out="$(dart run "$ROOT_DIR/tool/check_release_workflow.dart" --pr-smoke-workflow "$negative" 2>&1)"
  st=$?
  set -e
  if [[ "$st" -eq 0 ]]; then
    fail "PR negative fixture must fail but passed: $name"
  fi
  exp="${negative}.expected"
  if [[ -f "$exp" ]]; then
    want="$(tr -d '\n' <"$exp")"
    if ! printf '%s\n' "$out" | grep -qF "$want"; then
      fail "PR negative $name: output must contain: $want (got: $out)"
    fi
  fi
  ok "PR negative fixture rejected: $name"
done

ok "release_binaries workflow structure OK"