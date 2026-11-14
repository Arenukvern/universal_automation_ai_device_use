#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

DEFAULT_VERSION=""
PUBSPEC="${ROOT_DIR}/pkgs/universal_automation_toolkit/pubspec.yaml"
if [[ -f "$PUBSPEC" ]]; then
  DEFAULT_VERSION="$(sed -nE "s/^version:[[:space:]]*([^[:space:]]+).*$/\1/p" "$PUBSPEC" | head -n1)"
fi

REPO="${UNIVERSAL_AUTOMATION_REPO:-Arenukvern/universal_automation_ai_device_use}"
VERSION="${UNIVERSAL_AUTOMATION_VERSION:-$DEFAULT_VERSION}"
BASE_URL="${UNIVERSAL_AUTOMATION_BASE_URL:-${UA_RELEASE_BASE_URL:-}}"
ROLLBACK=0

SHARE_ROOT="${UNIVERSAL_AUTOMATION_SHARE:-$HOME/.local/share/universal-automation}"
VERSIONS_DIR="$SHARE_ROOT/versions"
PREVIOUS_FILE="$SHARE_ROOT/previous"
BIN_LINK="${UNIVERSAL_AUTOMATION_BIN:-$HOME/.local/bin/universal-automation}"

usage() {
  cat <<USAGE
Usage: ./install.sh [--version <semver>] [--rollback] [--repo <owner/name>] [--base-url <url>]
       curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash -s -- [--version <semver>]

Installs the universal-automation MCP/CLI binary from GitHub release assets.
No Dart SDK required when a prebuilt asset exists for your platform.

If no prebuilt asset matches, build from source instead:
  curl -fsSL .../main/plugin/install.sh | bash
  # or from a clone: ./plugin/install.sh

Override: UNIVERSAL_AUTOMATION_VERSION or --version.
Testing: UA_RELEASE_BASE_URL or UNIVERSAL_AUTOMATION_BASE_URL (e.g. local file server).
USAGE
}

resolve_latest_release_version() {
  local api_url="https://api.github.com/repos/${REPO}/releases"
  local body tag
  command -v curl >/dev/null 2>&1 || return 1
  body="$(curl -fsSL "$api_url?per_page=30" 2>/dev/null)" || return 1
  tag="$(sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"universal_automation_toolkit-v([^"]+)".*/\1/p' <<<"$body" | head -n1)"
  [[ -n "$tag" ]] || return 1
  printf '%s' "$tag"
}

resolve_cli_in_tree() {
  local root="$1"
  if [[ -f "$root/bin/universal_automation" ]]; then
    echo "$root/bin/universal_automation"
    return 0
  fi
  if [[ -f "$root/bin/universal-automation" ]]; then
    echo "$root/bin/universal-automation"
    return 0
  fi
  return 1
}

version_dir_from_bin() {
  local bin_path="$1"
  dirname "$(dirname "$bin_path")"
}

atomic_switch_link() {
  local target="$1"
  local link_dir bin_tmp
  link_dir="$(dirname "$BIN_LINK")"
  mkdir -p "$link_dir"
  bin_tmp="${link_dir}/.universal-automation.link.$$"
  ln -sfn "$target" "$bin_tmp"
  mv -f "$bin_tmp" "$BIN_LINK"
}

record_previous_install() {
  local current_bin current_root
  current_bin="$(readlink "$BIN_LINK" 2>/dev/null || true)"
  [[ -n "$current_bin" ]] || return 0
  current_root="$(version_dir_from_bin "$current_bin")"
  [[ -d "$current_root" ]] || return 0
  printf '%s\n' "$current_root" >"$PREVIOUS_FILE"
}

prune_version_dirs() {
  local ver="$1"
  local keep_current="$2"
  local keep_previous="$3"
  local d base
  [[ -d "$VERSIONS_DIR" ]] || return 0
  for d in "$VERSIONS_DIR"/*; do
    [[ -d "$d" ]] || continue
    base="$(basename "$d")"
    [[ "$base" == "${ver}.staging."* ]] && continue
    [[ "$base" == "${ver}-"* ]] || continue
    [[ "$d" == "$keep_current" ]] && continue
    [[ -n "$keep_previous" && "$d" == "$keep_previous" ]] && continue
    rm -rf "$d"
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --rollback)
      ROLLBACK=1
      shift
      ;;
    --repo)
      REPO="$2"
      shift 2
      ;;
    --base-url)
      BASE_URL="$2"
      shift 2
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

if [[ "$ROLLBACK" -eq 1 ]]; then
  [[ -f "$PREVIOUS_FILE" ]] || {
    echo "No previous install recorded at $PREVIOUS_FILE" >&2
    exit 1
  }
  prev_root="$(sed -n '1p' "$PREVIOUS_FILE")"
  [[ -d "$prev_root" ]] || {
    echo "Previous install dir missing: $prev_root" >&2
    exit 1
  }
  cli_bin="$(resolve_cli_in_tree "$prev_root")" || {
    echo "CLI missing under $prev_root" >&2
    exit 1
  }
  current_bin="$(readlink "$BIN_LINK" 2>/dev/null || true)"
  if [[ -n "$current_bin" ]]; then
    current_root="$(version_dir_from_bin "$current_bin")"
    printf '%s\n' "$current_root" >"$PREVIOUS_FILE"
  fi
  atomic_switch_link "$cli_bin"
  echo "Rolled back to $(basename "$prev_root")"
  exit 0
fi

if [[ -z "$VERSION" ]]; then
  VERSION="$(resolve_latest_release_version || true)"
fi

if [[ -z "$VERSION" ]]; then
  cat >&2 <<EOF
Unable to resolve install version.

Specify --version, or build from source:
  ./plugin/install.sh
EOF
  usage >&2
  exit 1
fi

version_no_prefix="${VERSION#v}"
version_no_prefix="${version_no_prefix#universal_automation_toolkit-v}"
tag="universal_automation_toolkit-v${version_no_prefix}"

os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
  Darwin) platform="darwin" ;;
  Linux) platform="linux" ;;
  *)
    echo "Unsupported OS: $os (use install.ps1 on Windows or plugin/install.sh from source)" >&2
    exit 1
    ;;
esac

case "$arch" in
  arm64|aarch64) normalized_arch="arm64" ;;
  x86_64|amd64) normalized_arch="x64" ;;
  *)
    echo "Unsupported architecture: $arch" >&2
    exit 1
    ;;
esac

triple="${platform}-${normalized_arch}"
archive="universal_automation_${version_no_prefix}_${triple}.tar.gz"

if [[ -z "$BASE_URL" ]]; then
  BASE_URL="https://github.com/${REPO}/releases/download/${tag}"
fi

work_parent="$(mktemp -d)"
trap 'rm -rf "$work_parent"' EXIT

fetch() {
  local url="$1"
  local output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$output"
    return
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO "$output" "$url"
    return
  fi
  echo "Neither curl nor wget is available." >&2
  exit 1
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
    return
  fi
  echo "No SHA-256 tool available (sha256sum or shasum)." >&2
  exit 1
}

if ! fetch "$BASE_URL/$archive" "$work_parent/$archive" 2>/dev/null; then
  cat >&2 <<EOF
No prebuilt release asset for ${triple} at:
  ${BASE_URL}/${archive}

Build from source (requires Dart SDK):
  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/plugin/install.sh | bash
  # or: ./plugin/install.sh from a repository clone
EOF
  exit 1
fi

fetch "$BASE_URL/checksums.txt" "$work_parent/checksums.txt"

checksum_line="$(awk -v f="$archive" '$2==f {print; exit}' "$work_parent/checksums.txt")"
if [[ -z "$checksum_line" ]]; then
  echo "Missing checksum entry for $archive" >&2
  exit 1
fi

expected_checksum="$(awk '{print $1}' <<<"$checksum_line")"
actual_checksum="$(sha256_file "$work_parent/$archive")"
if [[ "$expected_checksum" != "$actual_checksum" ]]; then
  echo "Checksum verification failed for $archive" >&2
  exit 1
fi

echo "Checksum verified"
tar -C "$work_parent" -xzf "$work_parent/$archive"

package_dir="$work_parent/universal_automation_${version_no_prefix}_${triple}"
if [[ ! -d "$package_dir" ]]; then
  package_dir="$(find "$work_parent" -mindepth 1 -maxdepth 1 -type d | head -n1)"
fi

mkdir -p "$VERSIONS_DIR"
staging="${VERSIONS_DIR}/${version_no_prefix}.staging.$$"
install_root="${VERSIONS_DIR}/${version_no_prefix}-$(date +%s)-$$"
rm -rf "$staging"
cp -a "$package_dir" "$staging"
mv "$staging" "$install_root"

cli_bin="$(resolve_cli_in_tree "$install_root")" || {
  rm -rf "$install_root"
  echo "CLI binary missing in $install_root" >&2
  exit 1
}

if ! "$cli_bin" --version >/dev/null 2>&1; then
  rm -rf "$install_root"
  echo "Staged binary failed --version smoke test; not switching active install" >&2
  exit 1
fi

record_previous_install
atomic_switch_link "$cli_bin"

keep_previous=""
if [[ -f "$PREVIOUS_FILE" ]]; then
  keep_previous="$(sed -n '1p' "$PREVIOUS_FILE")"
fi
prune_version_dirs "$version_no_prefix" "$install_root" "$keep_previous"

if [[ ":$PATH:" != *":$(dirname "$BIN_LINK"):"* ]]; then
  echo "Add $(dirname "$BIN_LINK") to PATH for MCP clients that resolve bare commands."
fi

installed_version="$("$BIN_LINK" --version)"
echo "Installed universal-automation ${installed_version} → $BIN_LINK"
echo "Binary: $cli_bin"
echo "Install root: $install_root"
echo ""
echo "MCP client snippet (stdio, desktop OS tier — lean default per ADR 0009):"
cat <<SNIP
{
  "mcpServers": {
    "universal-automation": {
      "command": "universal-automation",
      "args": ["serve", "--os"],
      "env": {
        "UNIVERSAL_AUTOMATION_CDP": "",
        "UNIVERSAL_AUTOMATION_WEBDRIVER": ""
      }
    }
  }
}
SNIP