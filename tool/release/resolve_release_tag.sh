#!/usr/bin/env bash
# Resolve release_tag for workflow_dispatch runs (Release Please toolkit tags).
# Writes: release_tag, version to GITHUB_OUTPUT when set.
set -euo pipefail

fail() { echo "resolve_release_tag: $*" >&2; exit 1; }

EVENT_NAME="${GITHUB_EVENT_NAME:-}"
DISPATCH_TAG="${DISPATCH_RELEASE_TAG:-}"

resolve_tag() {
  local tag=""
  if [[ "$EVENT_NAME" == "workflow_dispatch" ]]; then
    tag="$DISPATCH_TAG"
  else
    fail "unsupported GITHUB_EVENT_NAME: $EVENT_NAME (dispatch only)"
  fi

  if [[ -z "$tag" ]]; then
    fail "empty release tag"
  fi
  if [[ ! "$tag" =~ ^universal_automation_toolkit-v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "release tag must match universal_automation_toolkit-vMAJOR.MINOR.PATCH (got '$tag')"
  fi
  if [[ "$tag" == *".."* || "$tag" == *"/"* || "$tag" == *"\\"* ]]; then
    fail "release tag contains invalid path characters"
  fi
  printf '%s' "$tag"
}

TAG="$(resolve_tag)"
VERSION="${TAG#universal_automation_toolkit-v}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "release_tag=$TAG"
    echo "version=$VERSION"
  } >>"$GITHUB_OUTPUT"
fi

echo "resolve_release_tag: tag=$TAG version=$VERSION"