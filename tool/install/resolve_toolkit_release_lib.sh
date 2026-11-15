#!/usr/bin/env bash
# Resolve the newest universal_automation_toolkit-v* release that has a full
# binary asset set (skips assetless releases such as immutable-published 0.6.0).
set -euo pipefail

_toolkit_tag_pattern='^universal_automation_toolkit-v(.+)$'

required_binary_asset_names() {
  local ver="$1"
  printf '%s\n' \
    "universal_automation_${ver}_darwin-arm64.tar.gz" \
    "universal_automation_${ver}_darwin-x64.tar.gz" \
    "universal_automation_${ver}_linux-x64.tar.gz" \
    "universal_automation_${ver}_windows-x64.zip" \
    "checksums.txt"
}

# Args: version asset_name...
release_asset_set_complete() {
  local ver="$1"
  shift
  local -a have=("$@")
  local want name h
  while IFS= read -r want; do
    [[ -n "$want" ]] || continue
    for h in "${have[@]}"; do
      if [[ "$h" == "$want" ]]; then
        want=""
        break
      fi
    done
  done < <(required_binary_asset_names "$ver")
  [[ -z "$want" ]]
}

# Reads JSON array of GitHub releases from stdin; prints chosen semver on stdout.
# Skips drafts, prereleases without assets, and releases missing any required asset.
resolve_latest_toolkit_version_from_releases_json() {
  local py='
import json, re, sys
pattern = re.compile(r"^universal_automation_toolkit-v(.+)$")
required = lambda v: [
    f"universal_automation_{v}_darwin-arm64.tar.gz",
    f"universal_automation_{v}_darwin-x64.tar.gz",
    f"universal_automation_{v}_linux-x64.tar.gz",
    f"universal_automation_{v}_windows-x64.zip",
    "checksums.txt",
]
def complete(v, names):
    want = set(required(v))
    have = set(names)
    return want.issubset(have)
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError as e:
    print(f"resolve_toolkit_release: invalid releases JSON: {e}", file=sys.stderr)
    sys.exit(1)
if not isinstance(data, list):
    print("resolve_toolkit_release: releases payload must be a JSON array", file=sys.stderr)
    sys.exit(1)
for rel in data:
    if not isinstance(rel, dict):
        continue
    if rel.get("draft") is True:
        continue
    tag = rel.get("tag_name") or ""
    m = pattern.match(tag)
    if not m:
        continue
    ver = m.group(1)
    assets = rel.get("assets") or []
    names = [a.get("name") for a in assets if isinstance(a, dict) and a.get("name")]
    if complete(ver, names):
        print(ver)
        sys.exit(0)
print("resolve_toolkit_release: no published toolkit release with complete binary assets", file=sys.stderr)
sys.exit(1)
'
  if ! command -v python3 >/dev/null 2>&1; then
    echo "resolve_toolkit_release: python3 required" >&2
    return 1
  fi
  python3 -c "$py"
}