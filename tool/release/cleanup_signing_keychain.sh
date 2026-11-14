#!/usr/bin/env bash
set -euo pipefail

CERT_FILE="${MACOS_CERT_FILE:-}"
KEYCHAIN="${MACOS_SIGNING_KEYCHAIN:-}"

if [[ -n "$KEYCHAIN" ]]; then
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
fi
if [[ -n "$CERT_FILE" && -f "$CERT_FILE" ]]; then
  rm -f "$CERT_FILE"
fi