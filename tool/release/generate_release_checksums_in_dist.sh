#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
DIST="${2:-dist/release}"

[[ -n "$VERSION" ]] || {
  echo "generate_release_checksums_in_dist: usage: <version> [dist_dir]" >&2
  exit 1
}

cd "$DIST"
shopt -s nullglob
files=(universal_automation_"${VERSION}"_*.tar.gz universal_automation_"${VERSION}"_*.zip)
sha256sum "${files[@]}" > checksums.txt