#!/usr/bin/env bash
# Build the universal-automation AOT binary (with native driver assets) and
# link it into ~/.local/bin. Idempotent — safe to re-run.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/../pkgs/universal_automation_toolkit" && pwd)"

if command -v dart >/dev/null 2>&1; then
  DART_BIN="$(command -v dart)"
else
  DART_BIN="${DART_BIN:-/Users/antonio/fvm/default/bin/dart}"
fi

if [[ ! -x "$DART_BIN" ]]; then
  echo "Dart SDK not found; install Dart or set DART_BIN." >&2
  exit 1
fi

cd "$PKG_DIR"
"$DART_BIN" pub get
"$DART_BIN" build cli

BIN="$(ls "$PKG_DIR"/build/cli/*/bundle/bin/universal_automation 2>/dev/null | head -1)"
if [ -z "$BIN" ]; then
  echo "build did not produce a binary; fix dart build cli in $PKG_DIR" >&2
  exit 1
fi

TARGET_DIR="${UNIVERSAL_AUTOMATION_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$TARGET_DIR"
ln -sf "$BIN" "$TARGET_DIR/universal-automation"
echo "universal-automation -> $TARGET_DIR/universal-automation"
echo "ensure $TARGET_DIR is on PATH for MCP clients that resolve bare commands"
