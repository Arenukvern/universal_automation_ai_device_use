#!/usr/bin/env bash
# Smoke-check release archive matches declared triple; verifies CLI + native libs.
set -euo pipefail

fail() { echo "verify_release_tarball_architecture: $*" >&2; exit 1; }
ok() { echo "verify_release_tarball_architecture: $*"; }

ARCHIVE="${1:-}"
TRIPLE="${2:-}"

[[ -n "$ARCHIVE" && -n "$TRIPLE" ]] || fail "usage: verify_release_tarball_architecture.sh <archive> <triple>"
[[ -f "$ARCHIVE" ]] || fail "archive not found: $ARCHIVE"

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

case "$ARCHIVE" in
  *.zip)
    command -v unzip >/dev/null 2>&1 || fail "unzip required"
    unzip -q "$ARCHIVE" -d "$tmpdir"
    ;;
  *.tar.gz)
    tar -C "$tmpdir" -xzf "$ARCHIVE"
    ;;
  *)
    fail "unsupported archive: $ARCHIVE"
    ;;
esac

verify_elf() {
  local bin="$1"
  local file_out
  file_out="$(file "$bin")"
  echo "$file_out" | grep -qE 'ELF 64-bit.*x86-64' || fail "not linux x86-64: $bin → $file_out"
}

verify_macho_arm64() {
  local bin="$1"
  local file_out
  file_out="$(file "$bin")"
  echo "$file_out" | grep -qE 'Mach-O.*arm64' || fail "not darwin arm64: $bin → $file_out"
}

verify_macho_x64() {
  local bin="$1"
  local file_out
  file_out="$(file "$bin")"
  echo "$file_out" | grep -qE 'Mach-O.*x86_64' || fail "not darwin x86_64: $bin → $file_out"
}

verify_pe() {
  local bin="$1"
  local file_out
  file_out="$(file "$bin")"
  echo "$file_out" | grep -qiE 'PE32\+.*(x86-64|80386\+)' || fail "not windows x64 PE: $bin → $file_out"
}

verify_one() {
  local bin="$1"
  case "$TRIPLE" in
    linux-x64) verify_elf "$bin" ;;
    darwin-arm64) verify_macho_arm64 "$bin" ;;
    darwin-x64) verify_macho_x64 "$bin" ;;
    windows-x64) verify_pe "$bin" ;;
    *) fail "unsupported triple: $TRIPLE" ;;
  esac
}

# bash 3.2 compatible — no mapfile.
bins=()
while IFS= read -r -d '' bin; do
  bins+=("$bin")
done < <(find "$tmpdir" -type f \( \
  -name 'universal_automation' -o \
  -name 'universal-automation' -o \
  -name 'universal_automation.exe' -o \
  -name 'universal-automation.exe' -o \
  -name '*.so' -o \
  -name '*.dylib' -o \
  -name '*.dll' \
  \) -print0 | sort -z)

[[ ${#bins[@]} -ge 1 ]] || fail "expected CLI and/or native libs in $ARCHIVE"

cli_seen=0
for bin in "${bins[@]}"; do
  verify_one "$bin"
  case "$(basename "$bin")" in
    universal_automation|universal-automation|universal_automation.exe|universal-automation.exe)
      cli_seen=1
      ;;
  esac
done

[[ "$cli_seen" -eq 1 ]] || fail "CLI binary missing from $ARCHIVE"

ok "$ARCHIVE ($TRIPLE) — ${#bins[@]} binaries verified"