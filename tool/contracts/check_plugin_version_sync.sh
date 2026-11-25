#!/usr/bin/env bash
# Plugin bundle versions must match pkgs/universal_automation_toolkit pubspec (changesets version_files).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PUBSPEC="$ROOT_DIR/pkgs/universal_automation_toolkit/pubspec.yaml"
CONFIG="$ROOT_DIR/changesets.yaml"
TOOLKIT_NAME="universal_automation_toolkit"

fail() { echo "check_plugin_version_sync: $*" >&2; exit 1; }
ok() { echo "check_plugin_version_sync: $*"; }

command -v jq >/dev/null 2>&1 || fail "jq required"
command -v python3 >/dev/null 2>&1 || fail "python3 required"
[[ -f "$CONFIG" ]] || fail "missing $CONFIG"

VERSION="$(sed -nE "s/^version:[[:space:]]*([^[:space:]]+).*$/\1/p" "$PUBSPEC" | head -n1)"
[[ -n "$VERSION" ]] || fail "could not read toolkit version"

count=0
while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  count=$((count + 1))
  manifest="$ROOT_DIR/$rel"
  [[ -f "$manifest" ]] || fail "version_files path missing on disk: $rel → $manifest"
  got="$(jq -r '.version' "$manifest")"
  if [[ "$got" != "$VERSION" ]]; then
    fail "$manifest version $got != toolkit pubspec $VERSION"
  fi
done < <(python3 - "$CONFIG" "$TOOLKIT_NAME" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
pkg = re.escape(sys.argv[2])
m = re.search(rf"^[ \t]*{pkg}:[ \t]*\n((?:[ \t]+-[^\n]*\n)+)", text, re.MULTILINE)
if not m:
    sys.exit(0)
block = m.group(1)
for line in block.splitlines():
    pm = re.match(r"^[ \t]+- path:[ \t]+(.+)$", line)
    if pm:
        p = pm.group(1).strip()
        if p.endswith(".json"):
            print(p)
PY
)

[[ "$count" -ge 1 ]] || fail "changesets.yaml must list toolkit JSON version_files"

ok "plugin manifests at $VERSION ($count version_files)"