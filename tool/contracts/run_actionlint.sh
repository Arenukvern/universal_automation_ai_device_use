#!/usr/bin/env bash
# bash 3.2 compatible (macOS default): no declare -A, no mapfile.
# actionlint v1.7.7 — checksum-pinned per platform (linux/darwin amd64/arm64).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ACTIONLINT_VERSION="1.7.7"

os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
  Linux)
    case "$arch" in
      x86_64|amd64)
        ACTIONLINT_OS="linux"
        ACTIONLINT_ARCH="amd64"
        ACTIONLINT_SHA256="023070a287cd8cccd71515fedc843f1985bf96c436b7effaecce67290e7e0757"
        ;;
      aarch64|arm64)
        ACTIONLINT_OS="linux"
        ACTIONLINT_ARCH="arm64"
        ACTIONLINT_SHA256="401942f9c24ed71e4fe71b76c7d638f66d8633575c4016efd2977ce7c28317d0"
        ;;
      *)
        echo "run_actionlint: skip (unsupported Linux arch: $arch)" >&2
        exit 0
        ;;
    esac
    ;;
  Darwin)
    case "$arch" in
      x86_64|amd64)
        ACTIONLINT_OS="darwin"
        ACTIONLINT_ARCH="amd64"
        ACTIONLINT_SHA256="28e5de5a05fc558474f638323d736d822fff183d2d492f0aecb2b73cc44584f5"
        ;;
      arm64)
        ACTIONLINT_OS="darwin"
        ACTIONLINT_ARCH="arm64"
        ACTIONLINT_SHA256="2693315b9093aeacb4ebd91a993fea54fc215057bf0da2659056b4bc033873db"
        ;;
      *)
        echo "run_actionlint: skip (unsupported Darwin arch: $arch)" >&2
        exit 0
        ;;
    esac
    ;;
  *)
    echo "run_actionlint: skip (unsupported OS: $os)" >&2
    exit 0
    ;;
esac

ARCHIVE="/tmp/actionlint_${ACTIONLINT_VERSION}_${ACTIONLINT_OS}_${ACTIONLINT_ARCH}.tar.gz"
BIN="/tmp/actionlint-${ACTIONLINT_VERSION}-${ACTIONLINT_OS}-${ACTIONLINT_ARCH}"

if [[ ! -x "$BIN" ]]; then
  url="https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_${ACTIONLINT_OS}_${ACTIONLINT_ARCH}.tar.gz"
  curl -sSfL "$url" -o "$ARCHIVE"
  if command -v sha256sum >/dev/null 2>&1; then
    echo "${ACTIONLINT_SHA256}  ${ARCHIVE}" | sha256sum -c -
  elif command -v shasum >/dev/null 2>&1; then
    echo "${ACTIONLINT_SHA256}  ${ARCHIVE}" | shasum -a 256 -c -
  else
    echo "run_actionlint: neither sha256sum nor shasum found" >&2
    exit 1
  fi
  tar -xzf "$ARCHIVE" -C /tmp actionlint
  mv /tmp/actionlint "$BIN"
  chmod +x "$BIN"
fi

# macos-15-intel is GitHub-hosted; actionlint 1.7.7's built-in list predates that label.
"$BIN" -color -shellcheck= \
  -ignore 'label "macos-15-intel" is unknown' \
  "$ROOT_DIR"/.github/workflows/*.yml
echo "run_actionlint: OK"