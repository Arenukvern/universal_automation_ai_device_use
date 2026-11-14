#!/usr/bin/env bash
# Optional macOS codesign + notarize when secrets are present; no-op otherwise.
set -euo pipefail

BUNDLE_DIR="${1:-}"
[[ -d "$BUNDLE_DIR" ]] || {
  echo "codesign_macos_bundle: bundle dir required" >&2
  exit 0
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "codesign_macos_bundle: skipped (not macOS host)"
  exit 0
fi

P12="${MACOS_CERT_P12:-}"
P12_PASS="${MACOS_CERT_PASSWORD:-}"
IDENTITY="${MACOS_CODESIGN_IDENTITY:-}"

if [[ -z "$P12" || -z "$P12_PASS" ]]; then
  echo "codesign_macos_bundle: skipped (MACOS_CERT_P12 / MACOS_CERT_PASSWORD not set — preview unsigned build)"
  exit 0
fi

if ! command -v security >/dev/null 2>&1; then
  echo "codesign_macos_bundle: skipped (security CLI missing)"
  exit 0
fi

KEYCHAIN="ua-release-signing.keychain-db"
security create-keychain -p "$P12_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$P12_PASS" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign -T /usr/bin/security

sign_identity="$IDENTITY"
if [[ -z "$sign_identity" ]]; then
  sign_identity="$(security find-identity -v -p codesigning "$KEYCHAIN" | sed -nE 's/.*"([^"]+)".*/\1/p' | head -n1)"
fi

if [[ -z "$sign_identity" ]]; then
  echo "codesign_macos_bundle: skipped (no signing identity)" >&2
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  exit 0
fi

while IFS= read -r -d '' f; do
  codesign --force --options runtime --sign "$sign_identity" --timestamp "$f"
done < <(find "$BUNDLE_DIR" -type f \( -perm -111 -o -name '*.dylib' \) -print0)

# Notarization (optional second gate)
if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && ( -n "${APPLE_APP_PASSWORD:-}" || -n "${APPLE_NOTARIZE_KEY_ID:-}" ) ]]; then
  echo "codesign_macos_bundle: notarization configured but not automated in this workflow yet (sign-only)"
fi

security delete-keychain "$KEYCHAIN" 2>/dev/null || true
echo "codesign_macos_bundle: signed bundle at $BUNDLE_DIR"