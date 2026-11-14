#!/usr/bin/env bash
# Resolve release_tag for workflow_dispatch runs (Release Please toolkit tags).
# Writes: release_tag, version, release_ref, dry_run to GITHUB_OUTPUT when set.
set -euo pipefail

fail() { echo "resolve_release_tag: $*" >&2; exit 1; }

EVENT_NAME="${GITHUB_EVENT_NAME:-}"
DISPATCH_TAG="${DISPATCH_RELEASE_TAG:-}"
DRY_RUN="${DRY_RUN:-false}"
DRY_RUN_TRUTHY() {
  case "$DRY_RUN" in
    true|True|TRUE|1|yes|Yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_production_tag() {
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

resolve_dry_run_ref() {
  local ref=""
  if [[ "$EVENT_NAME" == "workflow_dispatch" ]]; then
    ref="$DISPATCH_TAG"
  else
    fail "unsupported GITHUB_EVENT_NAME: $EVENT_NAME (dispatch only)"
  fi
  [[ -n "$ref" ]] || fail "empty git ref for dry_run"
  if [[ ${#ref} -eq 40 && "$ref" =~ ^[0-9a-f]{40}$ ]]; then
    printf '%s' "$ref"
    return
  fi
  if [[ "$ref" =~ ^[0-9a-f]{7,39}$ ]]; then
    fail "partial SHAs are not accepted for dry_run (use full 40-char SHA)"
  fi
  if [[ "$ref" == *".."* ]]; then
    fail "ref contains invalid characters"
  fi
  printf '%s' "$ref"
}

TAG=""
VERSION=""
RELEASE_REF=""

if DRY_RUN_TRUTHY; then
  RELEASE_REF="$(resolve_dry_run_ref)"
  TAG=""
  VERSION=""
  echo "resolve_release_tag: dry_run ref=$RELEASE_REF"
else
  TAG="$(resolve_production_tag)"
  VERSION="${TAG#universal_automation_toolkit-v}"
  RELEASE_REF="refs/tags/$TAG"
  echo "resolve_release_tag: tag=$TAG version=$VERSION"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "release_tag=$TAG"
    echo "version=$VERSION"
    echo "release_ref=$RELEASE_REF"
    echo "dry_run=$DRY_RUN"
  } >>"$GITHUB_OUTPUT"
fi