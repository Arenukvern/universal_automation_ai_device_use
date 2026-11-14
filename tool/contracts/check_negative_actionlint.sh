#!/usr/bin/env bash
# bash 3.2 compatible (macOS default).
# Every negative fixture must be actionlint-clean except fixtures listed in
# ACTIONLINT_EXPECTED_NOISE: their Dart contract violation is the same shape
# that actionlint rejects (broken reusable ref, invalid needs graph, etc.).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail() { echo "check_negative_actionlint: $*" >&2; exit 1; }
ok() { echo "check_negative_actionlint: $*"; }

bash "$ROOT_DIR/tool/contracts/run_actionlint.sh" >/dev/null

ACTIONLINT_VERSION="1.7.7"
os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
  Linux)
    case "$arch" in
      x86_64|amd64) BIN="/tmp/actionlint-${ACTIONLINT_VERSION}-linux-amd64" ;;
      aarch64|arm64) BIN="/tmp/actionlint-${ACTIONLINT_VERSION}-linux-arm64" ;;
      *) ok "skip (unsupported Linux arch)"; exit 0 ;;
    esac
    ;;
  Darwin)
    case "$arch" in
      x86_64|amd64) BIN="/tmp/actionlint-${ACTIONLINT_VERSION}-darwin-amd64" ;;
      arm64) BIN="/tmp/actionlint-${ACTIONLINT_VERSION}-darwin-arm64" ;;
      *) ok "skip (unsupported Darwin arch)"; exit 0 ;;
    esac
    ;;
  *)
    ok "skip (unsupported OS)"; exit 0 ;;
esac

[[ -x "$BIN" ]] || fail "actionlint binary missing (run tool/contracts/run_actionlint.sh first)"

# basename -> why actionlint must report the same structural break.
ACTIONLINT_EXPECTED_NOISE=(
  negative_build_wrong_needs.yml    # empty needs:[] breaks job graph (syntax-check)
  negative_no_workflow_call.yml     # missing workflow_call → inputs.* undefined
  negative_secrets_in_with.yml      # bogus upload-artifact input "token"
  negative_secrets_step_if.yml      # secrets.* in step if: (context availability)
  negative_please_wrong_build_workflow.yml  # calls dispatch workflow without workflow_call
  negative_pr_wrong_workflow.yml    # same wrong reusable target
  negative_publish_needs_postflight.yml     # cyclic publish↔postflight needs
)

is_expected_noise() {
  local base="$1"
  local entry
  for entry in "${ACTIONLINT_EXPECTED_NOISE[@]}"; do
    if [[ "$entry" == "$base"* ]]; then
      return 0
    fi
  done
  return 1
}

shopt -s nullglob
for negative in "$ROOT_DIR"/tool/contracts/fixtures/**/negative_*.yml; do
  name="$(basename "$negative")"
  set +e
  out="$("$BIN" -shellcheck= -ignore 'label "macos-15-intel" is unknown' "$negative" 2>&1)"
  st=$?
  set -e
  if is_expected_noise "$name"; then
    if [[ "$st" -eq 0 ]] && [[ -z "$out" ]]; then
      fail "$name is on ACTIONLINT_EXPECTED_NOISE but actionlint is clean (remove from list or tighten fixture)"
    fi
    continue
  fi
  if [[ "$st" -ne 0 ]] || [[ -n "$out" ]]; then
    fail "$name must be actionlint-clean outside its dart contract violation: $out"
  fi
done

ok "negative fixtures actionlint-clean (with documented exceptions)"