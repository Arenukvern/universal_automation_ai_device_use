#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail() { echo "check_release_workflow: $*" >&2; exit 1; }
ok() { echo "check_release_workflow: $*"; }

dart run "$ROOT_DIR/tool/check_release_workflow.dart"

fixtures_dir="$ROOT_DIR/tool/contracts/fixtures/release_workflow"
shopt -s nullglob
for negative in "$fixtures_dir"/negative_*.yml; do
  name="$(basename "$negative")"
  if dart run "$ROOT_DIR/tool/check_release_workflow.dart" --workflow "$negative"; then
    fail "negative fixture must fail but passed: $name"
  fi
  ok "negative fixture rejected: $name"
done

pr_fixtures_dir="$ROOT_DIR/tool/contracts/fixtures/release_workflow_pr"
shopt -s nullglob
for negative in "$pr_fixtures_dir"/negative_*.yml; do
  name="$(basename "$negative")"
  if dart run "$ROOT_DIR/tool/check_release_workflow.dart" --pr-smoke-workflow "$negative"; then
    fail "PR negative fixture must fail but passed: $name"
  fi
  ok "PR negative fixture rejected: $name"
done

ok "release_binaries workflow structure OK"