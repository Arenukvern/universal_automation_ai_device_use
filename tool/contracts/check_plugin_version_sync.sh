#!/usr/bin/env bash
# Plugin bundle versions must match pkgs/universal_automation_toolkit pubspec (Release Please extra-files).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PUBSPEC="$ROOT_DIR/pkgs/universal_automation_toolkit/pubspec.yaml"
CONFIG="$ROOT_DIR/release-please-config.json"
TOOLKIT_PKG="pkgs/universal_automation_toolkit"

fail() { echo "check_plugin_version_sync: $*" >&2; exit 1; }
ok() { echo "check_plugin_version_sync: $*"; }

command -v jq >/dev/null 2>&1 || fail "jq required"
[[ -f "$CONFIG" ]] || fail "missing $CONFIG"

VERSION="$(sed -nE "s/^version:[[:space:]]*([^[:space:]]+).*$/\1/p" "$PUBSPEC" | head -n1)"
[[ -n "$VERSION" ]] || fail "could not read toolkit version"

resolve_extra_file_path() {
  local rel="$1"
  if [[ "$rel" == /* ]]; then
    printf '%s' "$ROOT_DIR$rel"
    return
  fi
  printf '%s' "$ROOT_DIR/$TOOLKIT_PKG/$rel"
}

count=0
while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  count=$((count + 1))
  manifest="$(resolve_extra_file_path "$rel")"
  [[ -f "$manifest" ]] || fail "extra-files path missing on disk: $rel → $manifest"
  got="$(jq -r '.version' "$manifest")"
  if [[ "$got" != "$VERSION" ]]; then
    fail "$manifest version $got != toolkit pubspec $VERSION"
  fi
done < <(jq -r --arg pkg "$TOOLKIT_PKG" '
    .packages[$pkg]."extra-files"[]? | .path // empty
  ' "$CONFIG")

[[ "$count" -ge 1 ]] || fail "release-please-config.json must list toolkit extra-files"

ok "plugin manifests at $VERSION ($count extra-files)"