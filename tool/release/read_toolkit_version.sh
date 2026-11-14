#!/usr/bin/env bash
set -euo pipefail

ROOT="${RELEASE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PUBSPEC="$ROOT/pkgs/universal_automation_toolkit/pubspec.yaml"
[[ -f "$PUBSPEC" ]] || { echo "missing $PUBSPEC" >&2; exit 1; }
VERSION="$(sed -nE "s/^version:[[:space:]]*([^[:space:]]+).*$/\1/p" "$PUBSPEC" | head -n1)"
[[ -n "$VERSION" ]] || { echo "could not read toolkit version" >&2; exit 1; }
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "version=$VERSION" >>"$GITHUB_OUTPUT"
fi
echo "read_toolkit_version: $VERSION"