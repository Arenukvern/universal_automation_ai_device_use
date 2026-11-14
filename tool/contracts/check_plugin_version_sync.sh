#!/usr/bin/env bash
# Plugin bundle versions must match pkgs/universal_automation_toolkit pubspec (Release Please extra-files).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PUBSPEC="$ROOT_DIR/pkgs/universal_automation_toolkit/pubspec.yaml"

fail() { echo "check_plugin_version_sync: $*" >&2; exit 1; }
ok() { echo "check_plugin_version_sync: $*"; }

command -v jq >/dev/null 2>&1 || fail "jq required"

VERSION="$(sed -nE "s/^version:[[:space:]]*([^[:space:]]+).*$/\1/p" "$PUBSPEC" | head -n1)"
[[ -n "$VERSION" ]] || fail "could not read toolkit version"

for manifest in \
  "$ROOT_DIR/plugin/.cursor-plugin/plugin.json" \
  "$ROOT_DIR/plugin/.claude-plugin/plugin.json"
do
  [[ -f "$manifest" ]] || fail "missing $manifest"
  got="$(jq -r '.version' "$manifest")"
  if [[ "$got" != "$VERSION" ]]; then
    fail "$manifest version $got != toolkit pubspec $VERSION"
  fi
done

grep -q '"extra-files"' "$ROOT_DIR/release-please-config.json" || \
  fail "release-please-config.json must list toolkit extra-files for plugin manifests"

ok "plugin manifests at $VERSION"