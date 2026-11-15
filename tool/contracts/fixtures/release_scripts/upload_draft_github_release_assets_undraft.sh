#!/usr/bin/env bash
# Negative fixture: upload must not undraft.
set -euo pipefail
TAG="${1:?}"
REPO="${GITHUB_REPOSITORY:?}"
gh release edit "$TAG" --repo "$REPO" --draft=false