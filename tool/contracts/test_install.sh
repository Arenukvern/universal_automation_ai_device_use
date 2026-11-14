#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="$ROOT_DIR/install.sh"

fail() { echo "test_install: $*" >&2; exit 1; }
ok() { echo "test_install: $*"; }

[[ -f "$INSTALL" ]] || fail "missing install.sh"
chmod +x "$INSTALL"

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

share="$tmpdir/share"
bin_dir="$tmpdir/bin"
mkdir -p "$bin_dir"

make_bundle() {
  local root="$1"
  local ver="$2"
  mkdir -p "$root/bin"
  cat >"$root/bin/universal_automation" <<BIN
#!/usr/bin/env bash
case "\${1:-}" in
  --version) echo "mock-$ver"; exit 0 ;;
  --help) exit 0 ;;
  *) exit 0 ;;
esac
BIN
  chmod +x "$root/bin/universal_automation"
}

make_broken_bundle() {
  local root="$1"
  mkdir -p "$root/bin"
  cat >"$root/bin/universal_automation" <<'BIN'
#!/usr/bin/env bash
exit 1
BIN
  chmod +x "$root/bin/universal_automation"
}

serve_release() {
  local ver="$1"
  local triple="$2"
  local rel_root="$tmpdir/release"
  local pkg="universal_automation_${ver}_${triple}"
  local arc="$tmpdir/${pkg}.tar.gz"
  mkdir -p "$rel_root"
  bundle="$tmpdir/bundle"
  rm -rf "$bundle"
  make_bundle "$bundle" "$ver"
  tar -C "$tmpdir" -czf "$arc" "$(basename "$bundle")"
  (cd "$tmpdir" && sha256sum "$(basename "$arc")" >"$rel_root/checksums.txt")
  cp "$arc" "$rel_root/"
  printf '%s' "http://127.0.0.1:${HTTP_PORT}"
}

HTTP_PORT=""
http_server() {
  local dir="$1"
  HTTP_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
  python3 -m http.server "$HTTP_PORT" --directory "$dir" >/dev/null 2>&1 &
  echo $! >"$tmpdir/http.pid"
  sleep 0.5
}

stop_http() {
  [[ -f "$tmpdir/http.pid" ]] && kill "$(cat "$tmpdir/http.pid")" 2>/dev/null || true
}

run_install() {
  local ver="$1"
  local base="$2"
  UNIVERSAL_AUTOMATION_SHARE="$share" \
  UNIVERSAL_AUTOMATION_BIN="$bin_dir/universal-automation" \
  UNIVERSAL_AUTOMATION_BASE_URL="$base" \
  bash "$INSTALL" --version "$ver"
}

triple="linux-x64"
ver="9.8.7"
rel_root="$tmpdir/release"
mkdir -p "$rel_root"
bundle="$tmpdir/bundle-a"
make_bundle "$bundle" "$ver"
tar -C "$tmpdir" -czf "$rel_root/universal_automation_${ver}_${triple}.tar.gz" "$(basename "$bundle")"
(
  cd "$rel_root"
  sha256sum "universal_automation_${ver}_${triple}.tar.gz" >checksums.txt
)

http_server "$rel_root"
base="http://127.0.0.1:${HTTP_PORT}"

run_install "$ver" "$base"
first_root="$(readlink "$bin_dir/universal-automation")"
first_dir="$(dirname "$(dirname "$first_root")")"
[[ -d "$first_dir" ]] || fail "first install root missing"

bundle_b="$tmpdir/bundle-b"
make_bundle "$bundle_b" "$ver-bump"
rm -rf "$bundle"
make_bundle "$bundle" "$ver-bump"
tar -C "$tmpdir" -czf "$rel_root/universal_automation_${ver}_${triple}.tar.gz" "$(basename "$bundle")"
(
  cd "$rel_root"
  sha256sum "universal_automation_${ver}_${triple}.tar.gz" >checksums.txt
)

run_install "$ver" "$base"
second_root="$(readlink "$bin_dir/universal-automation")"
[[ "$second_root" != "$first_root" ]] || fail "same-version reinstall must replace active binary path"
[[ -x "$bin_dir/universal-automation" ]] || fail "bin link must remain valid after reinstall"
out="$("$bin_dir/universal-automation" --version)"
[[ "$out" == "mock-$ver-bump" ]] || fail "expected updated binary, got $out"

broken="$tmpdir/broken"
make_broken_bundle "$broken"
tar -C "$tmpdir" -czf "$rel_root/universal_automation_${ver}_${triple}.tar.gz" "$(basename "$broken")"
(
  cd "$rel_root"
  sha256sum "universal_automation_${ver}_${triple}.tar.gz" >checksums.txt
)

if run_install "$ver" "$base" 2>/dev/null; then
  fail "broken binary must not be installed"
fi
[[ "$(readlink "$bin_dir/universal-automation")" == "$second_root" ]] || fail "link changed after failed install"

UNIVERSAL_AUTOMATION_SHARE="$share" \
UNIVERSAL_AUTOMATION_BIN="$bin_dir/universal-automation" \
bash "$INSTALL" --rollback

after_rb="$(readlink "$bin_dir/universal-automation")"
[[ "$after_rb" == "$first_root" ]] || fail "rollback must restore prior binary"

stop_http
ok "install atomicity + rollback OK"