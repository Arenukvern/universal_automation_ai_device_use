#!/usr/bin/env bash
# Decode base64 MACOS_CERT_P12, import into a temp keychain; write exports to env file.
set -euo pipefail

fail() { echo "setup_signing_keychain: $*" >&2; exit 1; }

ENV_FILE="${1:-}"
[[ -n "$ENV_FILE" ]] || fail "usage: setup_signing_keychain.sh <env-file>"

P12_B64="${MACOS_CERT_P12:-}"
P12_PASS="${MACOS_CERT_PASSWORD:-}"

[[ -n "$P12_B64" && -n "$P12_PASS" ]] || fail "MACOS_CERT_P12 and MACOS_CERT_PASSWORD required"

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "macOS host required for signing"
fi

command -v security >/dev/null 2>&1 || fail "missing security"
command -v base64 >/dev/null 2>&1 || fail "missing base64"

CERT_FILE="${TMPDIR:-/tmp}/ua-macos-cert-$$.p12"
if ! printf '%s' "$P12_B64" | base64 --decode >"$CERT_FILE" 2>/dev/null; then
  printf '%s' "$P12_B64" | base64 -D >"$CERT_FILE"
fi

KEYCHAIN="ua-release-signing-$$.keychain-db"
KEYCHAIN_PATH="$HOME/Library/Keychains/$KEYCHAIN"

security create-keychain -p "$P12_PASS" "$KEYCHAIN" >/dev/null
security set-keychain-settings -lut 21600 "$KEYCHAIN" >/dev/null
security unlock-keychain -p "$P12_PASS" "$KEYCHAIN" >/dev/null
security import "$CERT_FILE" -k "$KEYCHAIN" -P "$P12_PASS" \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null

USER_KEYCHAINS="$(security list-keychains -d user | tr -d '"')"
# shellcheck disable=SC2086
security list-keychains -s "$KEYCHAIN_PATH" $USER_KEYCHAINS >/dev/null

{
  printf 'MACOS_CERT_FILE=%q\n' "$CERT_FILE"
  printf 'MACOS_SIGNING_KEYCHAIN=%q\n' "$KEYCHAIN"
  printf 'MACOS_SIGNING_KEYCHAIN_PATH=%q\n' "$KEYCHAIN_PATH"
} >"$ENV_FILE"

echo "setup_signing_keychain: ready" >&2