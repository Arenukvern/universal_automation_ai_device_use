#!/usr/bin/env bash
# Assert that the release tag matches pkgs/universal_automation_toolkit pubspec version.

set -euo pipefail

ROOT_DIR="${RELEASE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PUBSPEC="$ROOT_DIR/pkgs/universal_automation_toolkit/pubspec.yaml"
TAG="${1:-${GITHUB_REF_NAME:-}}"

if [[ -z "$TAG" ]]; then
  echo "assert_release_tag: pass the tag or set GITHUB_REF_NAME" >&2
  exit 1
fi

if [[ ! -f "$PUBSPEC" ]]; then
  echo "assert_release_tag: missing $PUBSPEC" >&2
  exit 1
fi

VERSION="$(sed -nE "s/^version:[[:space:]]*([^[:space:]]+).*$/\1/p" "$PUBSPEC" | head -n1)"
if [[ -z "$VERSION" ]]; then
  echo "assert_release_tag: failed to read version from pubspec" >&2
  exit 1
fi

EXPECTED="universal_automation_toolkit-v$VERSION"
if [[ "$TAG" != "$EXPECTED" ]]; then
  echo "assert_release_tag: tag '$TAG' does not match pubspec '$VERSION' (expected '$EXPECTED')" >&2
  exit 1
fi

echo "assert_release_tag: $TAG matches toolkit $VERSION"