#!/usr/bin/env bash
# Fail the release train when toolkit shipped but binary reusable did not succeed.
# Env: TOOLKIT_RELEASE_CREATED, RELEASE_BINARIES_BUILD_RESULT
set -euo pipefail

fail() { echo "audit_release_binaries_train: $*" >&2; exit 1; }

toolkit_released() {
  case "${TOOLKIT_RELEASE_CREATED:-}" in
    true|True|TRUE|1) return 0 ;;
    *) return 1 ;;
  esac
}

if ! toolkit_released; then
  echo "audit_release_binaries_train: toolkit not released; binary jobs not required"
  exit 0
fi

if [[ "${RELEASE_BINARIES_BUILD_RESULT:-}" != "success" ]]; then
  fail "release-binaries-build result=${RELEASE_BINARIES_BUILD_RESULT:-unknown} (required for toolkit release)"
fi

echo "audit_release_binaries_train: toolkit binary build reusable succeeded"