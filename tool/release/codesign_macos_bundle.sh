#!/usr/bin/env bash
# macOS codesign when MACOS_CERT_P12 + password or import already done via temp keychain.
set -euo pipefail

BUNDLE_DIR="${1:-}"
[[ -d "$BUNDLE_DIR" ]] || {
  echo "codesign_macos_bundle: bundle dir required" >&2
  exit 1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "codesign_macos_bundle: skipped (not macOS host)"
  exit 0
fi

P12_B64="${MACOS_CERT_P12:-}"
P12_PASS="${MACOS_CERT_PASSWORD:-}"
IDENTITY="${MACOS_CODESIGN_IDENTITY:-}"
KEYCHAIN="${MACOS_SIGNING_KEYCHAIN:-}"

if [[ -z "$KEYCHAIN" && ( -z "$P12_B64" || -z "$P12_PASS" ) ]]; then
  echo "codesign_macos_bundle: skipped (signing secrets not set)"
  exit 0
fi

if ! command -v security >/dev/null 2>&1; then
  echo "codesign_macos_bundle: security CLI missing" >&2
  exit 1
fi

if [[ -z "$KEYCHAIN" ]]; then
  sign_env="$(mktemp)"
  bash "$(dirname "${BASH_SOURCE[0]}")/setup_signing_keychain.sh" "$sign_env"
  # shellcheck source=/dev/null
  source "$sign_env"
  rm -f "$sign_env"
  export MACOS_CERT_FILE MACOS_SIGNING_KEYCHAIN MACOS_SIGNING_KEYCHAIN_PATH
  trap 'bash "$(dirname "${BASH_SOURCE[0]}")/cleanup_signing_keychain.sh"' EXIT
  KEYCHAIN="$MACOS_SIGNING_KEYCHAIN"
fi

sign_identity="$IDENTITY"
if [[ -z "$sign_identity" ]]; then
  sign_identity="$(security find-identity -v -p codesigning "$KEYCHAIN" | sed -nE 's/.*"([^"]+)".*/\1/p' | head -n1)"
fi

[[ -n "$sign_identity" ]] || {
  echo "codesign_macos_bundle: no signing identity in keychain" >&2
  exit 1
}

while IFS= read -r -d '' f; do
  codesign --force --options runtime --sign "$sign_identity" --timestamp "$f"
done < <(find "$BUNDLE_DIR" -type f \( -perm -111 -o -name '*.dylib' \) -print0)

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && ( -n "${APPLE_APP_PASSWORD:-}" || -n "${APPLE_NOTARIZE_KEY_ID:-}" ) ]]; then
  echo "codesign_macos_bundle: notarization configured but not automated in this workflow yet (sign-only)"
fi

echo "codesign_macos_bundle: signed bundle at $BUNDLE_DIR"