#!/usr/bin/env bash
# Regression guards for .github/workflows/release_binaries.yml (dispatch-only).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WF="$ROOT_DIR/.github/workflows/release_binaries.yml"

fail() { echo "check_release_workflow: $*" >&2; exit 1; }
ok() { echo "check_release_workflow: $*"; }

[[ -f "$WF" ]] || fail "missing release_binaries.yml"

if grep -qE '^\s+push:' "$WF" && grep -qE 'tags:' "$WF"; then
  fail "release_binaries.yml must not trigger on tag push (use workflow_dispatch dispatch)"
fi
if ! grep -q 'workflow_dispatch:' "$WF"; then
  fail "release_binaries.yml must support workflow_dispatch"
fi
if ! grep -q 'release_tag:' "$WF"; then
  fail "workflow_dispatch must declare release_tag input"
fi
if ! grep -q 'postflight:' "$WF"; then
  fail "workflow must include postflight job"
fi
if ! grep -q 'assert_release_assets_complete.sh' "$WF"; then
  fail "postflight must assert all release assets"
fi
if ! grep -q 'TOOLING_CHECKOUT_PATH' "$WF"; then
  fail "workflow must checkout trusted tooling separately"
fi
if ! grep -q 'RELEASE_SRC_PATH' "$WF"; then
  fail "workflow must checkout release-src separately"
fi
if ! grep -q 'persist-credentials: false' "$WF"; then
  fail "tooling checkout must set persist-credentials: false"
fi
if ! grep -q 'release_sha:' "$WF"; then
  fail "prepare must output release_sha"
fi
if ! grep -q 'needs.prepare.outputs.release_tag' "$WF"; then
  fail "publish must use prepare.outputs.release_tag"
fi
if ! grep -q 'verify_release_tarball_architecture.sh' "$WF"; then
  fail "release workflow must verify tarball architecture from tooling"
fi
if ! grep -q 'GITHUB_REPOSITORY' "$WF"; then
  fail "gh calls must pass explicit GITHUB_REPOSITORY"
fi

ok "release_binaries workflow structure OK"