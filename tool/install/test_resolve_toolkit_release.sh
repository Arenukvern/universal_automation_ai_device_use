#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tool/install/resolve_toolkit_release_lib.sh
source "$ROOT_DIR/tool/install/resolve_toolkit_release_lib.sh"

fail() { echo "test_resolve_toolkit_release: $*" >&2; exit 1; }
ok() { echo "test_resolve_toolkit_release: $*"; }

fixture="$ROOT_DIR/tool/contracts/fixtures/install_releases/assetless_newest.json"
[[ -f "$fixture" ]] || fail "missing fixture $fixture"

got="$(resolve_latest_toolkit_version_from_releases_json <"$fixture")"
[[ "$got" == "0.6.0" ]] || fail "expected 0.6.0, got $got"

none_fixture="$(mktemp)"
trap 'rm -f "$none_fixture"' EXIT
cat >"$none_fixture" <<'JSON'
[
  {
    "tag_name": "universal_automation_toolkit-v0.6.1",
    "draft": false,
    "assets": []
  }
]
JSON

if resolve_latest_toolkit_version_from_releases_json <"$none_fixture" 2>/dev/null; then
  fail "expected failure when no release has assets"
fi

ok "skips assetless newest release"