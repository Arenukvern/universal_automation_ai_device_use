#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${RELEASE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist/release}"
TOOLKIT_DIR="$ROOT_DIR/pkgs/universal_automation_toolkit"
PUBSPEC="$TOOLKIT_DIR/pubspec.yaml"

VERSION="${VERSION:-$(sed -nE "s/^version:[[:space:]]*([^[:space:]]+).*$/\1/p" "$PUBSPEC" | head -n1)}"
if [[ -z "$VERSION" ]]; then
  echo "Failed to resolve release version from $PUBSPEC" >&2
  exit 1
fi

declare -a TRIPLES=()
CLEAN=0
SKIP_SIGN=0

usage() {
  cat <<USAGE
Usage: tool/release/build_release_artifacts.sh [--version <semver>] [--triple <triple>] [--clean]

Builds release archives for universal-automation (dart build cli bundle layout).
Generates checksum fragments under dist/release/ when building all triples locally.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --triple)
      TRIPLES+=("$2")
      shift 2
      ;;
    --clean)
      CLEAN=1
      shift
      ;;
    --skip-sign)
      SKIP_SIGN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ${#TRIPLES[@]} -eq 0 ]]; then
  TRIPLES=(darwin-arm64 darwin-x64 linux-x64 windows-x64)
fi

if [[ "$CLEAN" -eq 1 ]]; then
  rm -rf "$DIST_DIR"
fi
mkdir -p "$DIST_DIR"

assert_host_can_build() {
  local triple="$1"
  local host_os host_arch
  host_os="$(uname -s)"
  host_arch="$(uname -m)"

  case "$triple" in
    darwin-arm64)
      if [[ "$host_os" == "Darwin" && "$host_arch" == "x86_64" ]]; then
        cat >&2 <<EOF
darwin-arm64 requires an Apple Silicon macOS host.
Use macos-15 (arm64) in CI, or build on an arm64 Mac locally.
EOF
        exit 1
      fi
      ;;
    darwin-x64)
      if [[ "$host_os" == "Darwin" && "$host_arch" == "arm64" ]]; then
        cat >&2 <<EOF
darwin-x64 requires an Intel macOS host (or Rosetta-capable cross build).
Use macos-13 (x64) in CI when available.
EOF
        exit 1
      fi
      ;;
  esac
}

resolve_dart_target() {
  local triple="$1"
  case "$triple" in
    darwin-arm64) echo "macos arm64" ;;
    darwin-x64) echo "macos x64" ;;
    linux-x64) echo "linux x64" ;;
    windows-x64) echo "windows x64" ;;
    *)
      echo "Unsupported triple: $triple" >&2
      exit 1
      ;;
  esac
}

find_bundle_dir() {
  local dir
  dir="$(find "$TOOLKIT_DIR/build/cli" -type d -name bundle 2>/dev/null | head -n1)"
  [[ -n "$dir" ]] || {
    echo "dart build cli did not produce a bundle under build/cli" >&2
    exit 1
  }
  printf '%s' "$dir"
}

resolve_cli_binary() {
  local bundle="$1"
  local triple="$2"
  if [[ "$triple" == windows-x64 ]]; then
    if [[ -f "$bundle/bin/universal_automation.exe" ]]; then
      echo "$bundle/bin/universal_automation.exe"
      return
    fi
    if [[ -f "$bundle/bin/universal-automation.exe" ]]; then
      echo "$bundle/bin/universal-automation.exe"
      return
    fi
  fi
  if [[ -f "$bundle/bin/universal_automation" ]]; then
    echo "$bundle/bin/universal_automation"
    return
  fi
  if [[ -f "$bundle/bin/universal-automation" ]]; then
    echo "$bundle/bin/universal-automation"
    return
  fi
  echo "no CLI binary in $bundle/bin" >&2
  exit 1
}

smoke_cli() {
  local bin="$1"
  "$bin" --help >/dev/null
  "$bin" --version >/dev/null
}

maybe_sign_macos() {
  local bundle="$1"
  local triple="$2"
  if [[ "$SKIP_SIGN" -eq 1 ]]; then
    return 0
  fi
  if [[ "$triple" != darwin-* ]]; then
    return 0
  fi
  local script="${RELEASE_TOOLING_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}/codesign_macos_bundle.sh"
  if [[ ! -x "$script" ]]; then
    script="$(dirname "${BASH_SOURCE[0]}")/codesign_macos_bundle.sh"
  fi
  if [[ -x "$script" ]]; then
    bash "$script" "$bundle" || echo "codesign step skipped or failed (unsigned preview build)" >&2
  fi
}

for triple in "${TRIPLES[@]}"; do
  assert_host_can_build "$triple"
  read -r target_os target_arch <<<"$(resolve_dart_target "$triple")"

  echo "Building $triple ($target_os $target_arch) …"
  (
    cd "$ROOT_DIR"
    dart pub get
    cd "$TOOLKIT_DIR"
    HOME="${HOME:-/tmp}" DART_SUPPRESS_ANALYTICS=true dart build cli
  )

  bundle_dir="$(find_bundle_dir)"
  maybe_sign_macos "$bundle_dir" "$triple"

  package_name="universal_automation_${VERSION}_${triple}"
  stage_dir="$DIST_DIR/$package_name"
  rm -rf "$stage_dir"
  mkdir -p "$stage_dir"
  cp -a "$bundle_dir/." "$stage_dir/"
  if [[ -f "$ROOT_DIR/LICENSE" ]]; then
    cp "$ROOT_DIR/LICENSE" "$stage_dir/LICENSE"
  fi

  cli_bin="$(resolve_cli_binary "$stage_dir" "$triple")"
  smoke_cli "$cli_bin"

  archive_path=""
  case "$triple" in
    windows-x64)
      archive_path="$DIST_DIR/${package_name}.zip"
      rm -f "$archive_path"
      (
        cd "$DIST_DIR"
        if command -v zip >/dev/null 2>&1; then
          zip -qr "$archive_path" "$package_name"
        else
          fail_zip="zip not found"
          echo "$fail_zip" >&2
          exit 1
        fi
      )
      ;;
    *)
      archive_path="$DIST_DIR/${package_name}.tar.gz"
      rm -f "$archive_path"
      tar -C "$DIST_DIR" -czf "$archive_path" "$package_name"
      ;;
  esac

  rm -rf "$stage_dir"
  echo "Built $archive_path"
done

if [[ ${#TRIPLES[@]} -gt 1 ]]; then
  (
    cd "$DIST_DIR"
    shopt -s nullglob
    files=(universal_automation_"$VERSION"_*.tar.gz universal_automation_"$VERSION"_*.zip)
    if [[ ${#files[@]} -eq 0 ]]; then
      exit 0
    fi
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum "${files[@]}" > checksums.txt
    else
      shasum -a 256 "${files[@]}" > checksums.txt
    fi
    echo "Checksums written to $DIST_DIR/checksums.txt"
  )
fi