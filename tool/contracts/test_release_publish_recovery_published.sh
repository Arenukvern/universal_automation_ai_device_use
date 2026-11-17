#!/usr/bin/env bash
# Publish-job script order for published release + recovery_mode (workflow_dispatch).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() { echo "test_release_publish_recovery_published: $*" >&2; exit 1; }
ok() { echo "test_release_publish_recovery_published: $*"; }

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

tooling="$tmpdir/tooling"
dist="$tmpdir/dist/release"
bindir="$tmpdir/bin"
mkdir -p "$tooling/tool/release" "$dist" "$bindir"

cp -a "$ROOT_DIR/tool/release/"*.sh "$tooling/tool/release/"
chmod +x "$tooling/tool/release/"*.sh

TAG=universal_automation_toolkit-v0.9.0
VERSION=0.9.0
REPO=example/test
export GITHUB_REPOSITORY="$REPO"
export RELEASE_RECOVERY_MODE=true
export VERSION
export GITHUB_REPOSITORY_SLUG="$REPO"
export GH_TOKEN=fixture

checksums_file="$dist/checksums.txt"
cat >"$checksums_file" <<'EOF'
abc123 universal_automation_0.9.0_linux-x64.tar.gz
EOF

for leg in darwin-arm64.tar.gz darwin-x64.tar.gz linux-x64.tar.gz; do
  touch "$dist/universal_automation_0.9.0_$leg"
done
touch "$dist/universal_automation_0.9.0_windows-x64.zip"
export CHECKSUMS_FILE="$checksums_file"

cat >"$bindir/gh" <<'GH_EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"release upload"* || "$*" == *"release edit"* ]]; then
  echo "gh must not upload/edit in published recovery test: $*" >&2
  exit 1
fi
if [[ "$*" == *"release view"* ]]; then
  if [[ "$*" == *isDraft* && "$*" == *-q* ]]; then
    printf '%s\n' 'false'
    exit 0
  fi
  if [[ "$*" == *assets* ]]; then
    printf '%s\n' '{"isDraft":false,"assets":[{"name":"universal_automation_0.9.0_darwin-arm64.tar.gz","url":"https://example.test/a1"},{"name":"universal_automation_0.9.0_darwin-x64.tar.gz","url":"https://example.test/a2"},{"name":"universal_automation_0.9.0_linux-x64.tar.gz","url":"https://example.test/a3"},{"name":"universal_automation_0.9.0_windows-x64.zip","url":"https://example.test/a4"},{"name":"checksums.txt","url":"https://example.test/checksums.txt"}]}'
    exit 0
  fi
  if [[ "$*" == *isDraft* ]]; then
    printf '%s\n' '{"isDraft":false}'
    exit 0
  fi
fi
echo "unexpected gh: $*" >&2
exit 1
GH_EOF

cat >"$bindir/curl" <<'CURL_EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" != *checksums.txt* ]]; then
  echo "unexpected curl: $*" >&2
  exit 1
fi
out=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-o" ]]; then
    out="$arg"
  fi
  prev="$arg"
done
if [[ -z "$out" ]]; then
  cat "${CHECKSUMS_FILE:?CHECKSUMS_FILE required}"
  exit 0
fi
cat "${CHECKSUMS_FILE:?CHECKSUMS_FILE required}" >"$out"
exit 0
CURL_EOF

chmod +x "$bindir/gh" "$bindir/curl"
export PATH="$bindir:$PATH"

bash "$tooling/tool/release/check_release_assets_conflict.sh" "$TAG" "$VERSION" \
  || fail "conflict check"

bash "$tooling/tool/release/assert_github_release_is_draft.sh" "$TAG" \
  || fail "assert published recovery"

out="$(bash "$tooling/tool/release/append_binary_install_notes_to_draft_release.sh" "$TAG")"
[[ "$out" == *"skipping"* ]] || fail "append must skip on published"

out="$(bash "$tooling/tool/release/upload_draft_github_release_assets.sh" "$TAG" "$dist")"
[[ "$out" == *"skipping"* ]] || fail "upload must skip on published"

bash "$tooling/tool/release/assert_release_assets_complete_on_draft.sh" "$TAG" "$VERSION" \
  || fail "verify published recovery"

out="$(bash "$tooling/tool/release/publish_github_release_from_draft.sh" "$TAG")"
[[ "$out" == *"already published"* ]] || fail "publish must no-op on published"

ok "published recovery publish-job path OK"