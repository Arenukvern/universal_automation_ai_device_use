#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() { echo "test_release_recovery_flow: $*" >&2; exit 1; }
ok() { echo "test_release_recovery_flow: $*"; }

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

tooling="$tmpdir/tooling"
release="$tmpdir/release-src"
mkdir -p "$tooling/tool/release" "$release/pkgs/universal_automation_toolkit"

cp -a "$ROOT_DIR/tool/release/"*.sh "$tooling/tool/release/"
chmod +x "$tooling/tool/release/"*.sh
printf 'version: 0.9.0\n' >"$release/pkgs/universal_automation_toolkit/pubspec.yaml"

git -C "$release" init -q
git -C "$release" add pkgs
git -C "$release" -c user.email=t -c user.name=t commit -q -m "toolkit 0.9.0"
git -C "$release" tag universal_automation_toolkit-v0.9.0
sha="$(git -C "$release" rev-parse 'HEAD^{commit}')"

bash "$tooling/tool/release/verify_release_source_checkout.sh" \
  "$release" universal_automation_toolkit-v0.9.0 "$sha" \
  || fail "verify_release_source_checkout"

RELEASE_ROOT="$release" \
  bash "$tooling/tool/release/assert_release_tag.sh" universal_automation_toolkit-v0.9.0 \
  || fail "assert_release_tag"

gh() {
  echo '{"assets":[{"name":"universal_automation_0.9.0_linux-x64.tar.gz"}]}'
}
export -f gh
export GITHUB_REPOSITORY=example/test

if bash "$tooling/tool/release/check_release_assets_conflict.sh" universal_automation_toolkit-v0.9.0 0.9.0; then
  fail "must fail on conflicting asset names"
else
  ok "conflicting assets rejected"
fi

unset -f gh
gh() { echo '{"assets":[]}'; }
export -f gh
bash "$tooling/tool/release/check_release_assets_conflict.sh" universal_automation_toolkit-v0.9.0 0.9.0 \
  || fail "empty assets should pass"

ok "recovery flow fixtures OK"