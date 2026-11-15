#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tool/install/resolve_toolkit_release_lib.sh
source "$ROOT_DIR/tool/install/resolve_toolkit_release_lib.sh"

fail() { echo "test_resolve_toolkit_release: $*" >&2; exit 1; }
ok() { echo "test_resolve_toolkit_release: $*"; }

tags_fixture="$(mktemp)"
probe_map="$(mktemp)"
cleanup() { rm -f "$tags_fixture" "$probe_map"; }
trap cleanup EXIT

cat >"$tags_fixture" <<'TAGS'
universal_automation_toolkit-v0.6.1
universal_automation_toolkit-v0.6.0
TAGS

cat >"$probe_map" <<'MAP'
# 0.6.1 newest but assetless (one missing)
universal_automation_toolkit-v0.6.1	universal_automation_0.6.1_darwin-arm64.tar.gz	404
universal_automation_toolkit-v0.6.1	universal_automation_0.6.1_darwin-x64.tar.gz	404
universal_automation_toolkit-v0.6.1	universal_automation_0.6.1_linux-x64.tar.gz	404
universal_automation_toolkit-v0.6.1	universal_automation_0.6.1_windows-x64.zip	404
universal_automation_toolkit-v0.6.1	checksums.txt	404
universal_automation_toolkit-v0.6.0	universal_automation_0.6.0_darwin-arm64.tar.gz	404
universal_automation_toolkit-v0.6.0	universal_automation_0.6.0_darwin-x64.tar.gz	404
universal_automation_toolkit-v0.6.0	universal_automation_0.6.0_linux-x64.tar.gz	404
universal_automation_toolkit-v0.6.0	universal_automation_0.6.0_windows-x64.zip	404
universal_automation_toolkit-v0.6.0	checksums.txt	404
MAP

export UNIVERSAL_AUTOMATION_TOOLKIT_TAGS_FIXTURE="$tags_fixture"
export UNIVERSAL_AUTOMATION_ASSET_PROBE_MAP="$probe_map"
export UNIVERSAL_AUTOMATION_PROBE_BASE_URL="http://probe.invalid"
if resolve_latest_toolkit_version "test/repo" 2>/dev/null; then
  fail "expected failure when no tag has complete assets"
fi

cat >>"$tags_fixture" <<'TAGS'
universal_automation_toolkit-v0.6.2
TAGS

while IFS= read -r asset; do
  [[ -z "$asset" ]] && continue
  printf 'universal_automation_toolkit-v0.6.2\t%s\t200\n' "$asset"
done < <(required_binary_asset_names "0.6.2") >>"$probe_map"

got="$(resolve_latest_toolkit_version "test/repo")"
[[ "$got" == "0.6.2" ]] || fail "expected 0.6.2, got ${got:-<empty>}"

refs_dir="$ROOT_DIR/tool/contracts/fixtures/install_releases"
for f in matching_refs_pretty.json matching_refs_minified.json matching_refs_reordered.json matching_refs_decoy_body.json; do
  [[ -f "$refs_dir/$f" ]] || fail "missing $f"
  got_tags="$(parse_matching_refs_toolkit_tags <"$refs_dir/$f" | sort -u | wc -l | tr -d ' ')"
  [[ "$got_tags" -ge 1 ]] || fail "$f: expected toolkit refs, got $got_tags"
done

decoy="$(parse_matching_refs_toolkit_tags <"$refs_dir/matching_refs_decoy_body.json")"
[[ "$decoy" == "universal_automation_toolkit-v0.6.1" ]] || fail "decoy JSON must only extract real ref, got: $decoy"

ok "tag list + HEAD probe latest resolution OK"