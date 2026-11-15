#!/usr/bin/env bash
set -euo pipefail

fail() { echo "validate_release_checksums_file: $*" >&2; exit 1; }

VERSION="${1:-}"
CHECKSUMS_FILE="${2:-}"

[[ -n "$VERSION" && -f "$CHECKSUMS_FILE" ]] || \
  fail "usage: validate_release_checksums_file.sh <version> <checksums.txt>"

required=(
  "universal_automation_${VERSION}_darwin-arm64.tar.gz"
  "universal_automation_${VERSION}_darwin-x64.tar.gz"
  "universal_automation_${VERSION}_linux-x64.tar.gz"
  "universal_automation_${VERSION}_windows-x64.zip"
)

found_darwin_arm=0
found_darwin_x64=0
found_linux=0
found_windows=0
line_count=0

while IFS= read -r line || [[ -n "$line" ]]; do
  line="$(printf '%s' "$line" | sed 's/[[:space:]]*$//')"
  [[ -z "$line" ]] && continue
  if ! printf '%s' "$line" | grep -qE '^[0-9a-fA-F]{64}[[:space:]]+[^[:space:]/?]+$'; then
    fail "invalid checksum line: $line"
  fi
  name="${line#* }"
  name="$(printf '%s' "$name" | awk '{print $NF}')"
  if printf '%s' "$name" | grep -q '/'; then
    fail "reject path component in checksum filename: $name"
  fi
  case "$name" in
    *..*) fail "reject traversal in checksum filename: $name" ;;
  esac
  dup="$(grep -cE "^[0-9a-fA-F]{64}[[:space:]]+$(printf '%s' "$name" | sed 's/[.[\*^$()+?{|]/\\&/g')$" "$CHECKSUMS_FILE" || true)"
  if [[ "$dup" -gt 1 ]]; then
    fail "duplicate checksum entry: $name"
  fi
  line_count=$((line_count + 1))
  for req in "${required[@]}"; do
    [[ "$name" == "$req" ]] || continue
    case "$req" in
      *_darwin-arm64.tar.gz) found_darwin_arm=1 ;;
      *_darwin-x64.tar.gz) found_darwin_x64=1 ;;
      *_linux-x64.tar.gz) found_linux=1 ;;
      *_windows-x64.zip) found_windows=1 ;;
    esac
  done
  skip=0
  for req in "${required[@]}"; do
    [[ "$name" == "$req" ]] && skip=1
  done
  [[ "$skip" -eq 1 ]] || fail "unexpected checksum entry: $name"
done <"$CHECKSUMS_FILE"

[[ "$found_darwin_arm" -eq 1 && "$found_darwin_x64" -eq 1 && "$found_linux" -eq 1 && "$found_windows" -eq 1 ]] || \
  fail "checksums.txt must list exactly the four required archives"
[[ "$line_count" -eq 4 ]] || fail "expected exactly 4 checksum lines, got $line_count"

printf 'validate_release_checksums_file: OK (%s)\n' "$VERSION"