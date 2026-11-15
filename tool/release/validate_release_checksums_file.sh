#!/usr/bin/env bash
set -euo pipefail

fail() { echo "validate_release_checksums_file: $*" >&2; exit 1; }

VERSION="${1:-}"
CHECKSUMS_FILE="${2:-}"

[[ -n "$VERSION" && -f "$CHECKSUMS_FILE" ]] || \
  fail "usage: validate_release_checksums_file.sh <version> <checksums.txt>"

if ! awk -v ver="$VERSION" '
function die(msg) {
  print "validate_release_checksums_file: " msg > "/dev/stderr"
  exit 1
}
BEGIN {
  split("", seen)
  nreq = 4
  required[1] = "universal_automation_" ver "_darwin-arm64.tar.gz"
  required[2] = "universal_automation_" ver "_darwin-x64.tar.gz"
  required[3] = "universal_automation_" ver "_linux-x64.tar.gz"
  required[4] = "universal_automation_" ver "_windows-x64.zip"
  for (i = 1; i <= nreq; i++) want[required[i]] = 1
  lines = 0
}
NF < 2 { next }
$1 !~ /^[0-9a-fA-F]{64}$/ { die("invalid checksum line: " $0) }
{
  name = $NF
  if (name ~ /\// || name ~ /\.\./) {
    die("reject path component in checksum filename: " name)
  }
  if (name in seen) {
    die("duplicate checksum entry: " name)
  }
  seen[name] = 1
  if (!(name in want)) {
    die("unexpected checksum entry: " name)
  }
  lines++
}
END {
  if (lines != 4) {
    die("expected exactly 4 checksum lines, got " lines)
  }
  for (i = 1; i <= nreq; i++) {
    if (!(required[i] in seen)) {
      die("missing checksum for required archive: " required[i])
    }
  }
  print "validate_release_checksums_file: OK (" ver ")"
}
' "$CHECKSUMS_FILE"; then
  fail "checksum validation failed"
fi