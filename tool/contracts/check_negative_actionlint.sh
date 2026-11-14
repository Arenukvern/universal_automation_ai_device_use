#!/usr/bin/env bash
# bash 3.2 compatible (macOS default).
# Every negative fixture must be actionlint-clean except fixtures listed in
# ACTIONLINT_NOISE_RULES: their Dart contract violation is the same shape
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

# basename -> space-separated allowed actionlint rule ids (from trailing [rule-id]).
ACTIONLINT_NOISE_RULES=(
  "negative_build_wrong_needs.yml|syntax-check expression"
  "negative_no_workflow_call.yml|syntax-check expression"
  "negative_secrets_in_with.yml|action expression"
  "negative_secrets_step_if.yml|expression"
  "negative_please_wrong_build_workflow.yml|workflow-call expression"
  "negative_pr_wrong_workflow.yml|workflow-call"
  "negative_publish_needs_postflight.yml|job-needs"
)

allowed_rules_for() {
  local base="$1"
  local row entry rules
  for row in "${ACTIONLINT_NOISE_RULES[@]}"; do
    entry="${row%%|*}"
    rules="${row#*|}"
    if [[ "$entry" == "$base" ]]; then
      printf '%s' "$rules"
      return 0
    fi
  done
  return 1
}

is_expected_noise() {
  local base="$1"
  allowed_rules_for "$base" >/dev/null
}

# Returns 0 when output matches pinned rules; 1 on mismatch; 2 when clean but expected noise.
validate_noise_rules() {
  local yml="$1"
  local base="$2"
  local allowed out st rule found
  if ! allowed="$(allowed_rules_for "$base")"; then
    fail "validate_noise_rules: $base not in ACTIONLINT_NOISE_RULES"
  fi
  set +e
  out="$("$BIN" -shellcheck= -ignore 'label "macos-15-intel" is unknown' "$yml" 2>&1)"
  st=$?
  set -e
  if [[ "$st" -eq 0 ]] && [[ -z "$out" ]]; then
    echo "check_negative_actionlint: $base is on ACTIONLINT_NOISE_RULES but actionlint is clean" >&2
    return 2
  fi
  while IFS= read -r rule; do
    [[ -z "$rule" ]] && continue
    found=0
    for allowed_rule in $allowed; do
      if [[ "$rule" == "$allowed_rule" ]]; then
        found=1
        break
      fi
    done
    if [[ "$found" -eq 0 ]]; then
      echo "check_negative_actionlint: $base: unexpected actionlint rule [$rule] (allowed: $allowed)" >&2
      echo "check_negative_actionlint: output: $out" >&2
      return 1
    fi
  done < <(printf '%s\n' "$out" | grep -oE '\[[-a-z0-9]+\]' | tr -d '[]' | sort -u)
  return 0
}

shopt -s nullglob
for negative in "$ROOT_DIR"/tool/contracts/fixtures/**/negative_*.yml; do
  name="$(basename "$negative")"
  set +e
  out="$("$BIN" -shellcheck= -ignore 'label "macos-15-intel" is unknown' "$negative" 2>&1)"
  st=$?
  set -e
  if is_expected_noise "$name"; then
    set +e
    validate_noise_rules "$negative" "$name"
    rc=$?
    set -e
    if [[ "$rc" -eq 2 ]]; then
      fail "$name is on ACTIONLINT_NOISE_RULES but actionlint is clean"
    fi
    if [[ "$rc" -eq 1 ]]; then
      fail "$name: pinned actionlint rule mismatch (see stderr)"
    fi
    continue
  fi
  if [[ "$st" -ne 0 ]] || [[ -n "$out" ]]; then
    fail "$name must be actionlint-clean outside its dart contract violation: $out"
  fi
done

META_EXTRA="$ROOT_DIR/tool/contracts/fixtures/actionlint_meta/publish_needs_postflight_extra_actionlint.yml"
if [[ ! -f "$META_EXTRA" ]]; then
  fail "missing actionlint meta fixture: publish_needs_postflight_extra_actionlint.yml"
fi
PIN_BASE="negative_publish_needs_postflight.yml"
if ! allowed="$(allowed_rules_for "$PIN_BASE")"; then
  fail "meta self-test: $PIN_BASE not in ACTIONLINT_NOISE_RULES"
fi
set +e
meta_out="$("$BIN" -shellcheck= -ignore 'label "macos-15-intel" is unknown' "$META_EXTRA" 2>&1)"
set -e
meta_rules="$(printf '%s\n' "$meta_out" | grep -oE '\[[-a-z0-9]+\]' | tr -d '[]' | sort -u)"
meta_rejected_extra=0
while IFS= read -r rule; do
  [[ -z "$rule" ]] && continue
  found=0
  for allowed_rule in $allowed; do
    if [[ "$rule" == "$allowed_rule" ]]; then
      found=1
      break
    fi
  done
  if [[ "$found" -eq 0 ]]; then
    meta_rejected_extra=1
    break
  fi
done <<<"$meta_rules"
if [[ "$meta_rejected_extra" -ne 1 ]]; then
  fail "noise rule pin must reject extra unrelated actionlint errors (meta fixture)"
fi

ok "negative fixtures actionlint-clean (with documented exceptions)"