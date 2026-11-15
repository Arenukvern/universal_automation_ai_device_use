#!/usr/bin/env bash
# Resolve latest toolkit release by tag names + HTTP HEAD probes (no releases JSON).
set -euo pipefail

TOOLKIT_TAG_PREFIX='universal_automation_toolkit-v'

required_binary_asset_names() {
  local ver="$1"
  printf '%s\n' \
    "universal_automation_${ver}_darwin-arm64.tar.gz" \
    "universal_automation_${ver}_darwin-x64.tar.gz" \
    "universal_automation_${ver}_linux-x64.tar.gz" \
    "universal_automation_${ver}_windows-x64.zip" \
    "checksums.txt"
}

is_prerelease_version() {
  [[ "$1" == *-* ]]
}

# matching-refs API JSON only — extract refs/tags/universal_automation_toolkit-v* refs.
# Does not read /releases bodies (release notes can quote decoy "tag_name" strings).
parse_matching_refs_toolkit_tags() {
  grep -oE '"ref"[[:space:]]*:[[:space:]]*"refs/tags/universal_automation_toolkit-v[^"]+"' \
    | sed 's/.*refs\/tags\///; s/"$//'
}

# Print toolkit tags (unsorted), one per line.
list_toolkit_release_tags() {
  local repo="$1"
  if [[ -n "${UNIVERSAL_AUTOMATION_TOOLKIT_TAGS_FIXTURE:-}" ]]; then
    grep -v '^[[:space:]]*#' "$UNIVERSAL_AUTOMATION_TOOLKIT_TAGS_FIXTURE" | sed '/^[[:space:]]*$/d'
    return 0
  fi
  if command -v git >/dev/null 2>&1; then
    git ls-remote --tags "https://github.com/${repo}.git" 'refs/tags/universal_automation_toolkit-v*' 2>/dev/null \
      | awk '/\trefs\/tags\/universal_automation_toolkit-v/ {
          tag = $2
          sub(/^refs\/tags\//, "", tag)
          if (tag !~ /\^\{\}$/) print tag
        }'
    return 0
  fi
  command -v curl >/dev/null 2>&1 || return 1
  curl -fsSL \
    "https://api.github.com/repos/${repo}/git/matching-refs/tags/universal_automation_toolkit-v" \
    2>/dev/null | parse_matching_refs_toolkit_tags
}

# Sort toolkit tags by semver (desc). Drops prerelease versions. Requires awk.
sort_toolkit_tags_by_version_desc() {
  awk -v pfx="$TOOLKIT_TAG_PREFIX" '
  function ver_of(tag,   v) {
    v = tag
    sub("^" pfx, "", v)
    return v
  }
  {
    tag = $0
    if (tag == "") next
    ver = ver_of(tag)
    if (index(ver, "-") > 0) next
    split(ver, a, ".")
    key = sprintf("%05d.%05d.%05d", a[1]+0, a[2]+0, a[3]+0)
    print key "\t" ver "\t" tag
  }
  ' | sort -t '	' -k1,1r | cut -f3
}

release_download_url() {
  local repo="$1" tag="$2" asset="$3"
  if [[ -n "${UNIVERSAL_AUTOMATION_PROBE_BASE_URL:-}" ]]; then
    printf '%s/%s/%s' "${UNIVERSAL_AUTOMATION_PROBE_BASE_URL%/}" "$tag" "$asset"
    return 0
  fi
  printf 'https://github.com/%s/releases/download/%s/%s' "$repo" "$tag" "$asset"
}

# UNIVERSAL_AUTOMATION_ASSET_PROBE_MAP: lines "tag<TAB>asset<TAB>status" (HEAD result).
probe_map_status() {
  local tag="$1" asset="$2" line want_tag want_asset status
  [[ -n "${UNIVERSAL_AUTOMATION_ASSET_PROBE_MAP:-}" ]] || return 1
  [[ -f "$UNIVERSAL_AUTOMATION_ASSET_PROBE_MAP" ]] || return 1
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    want_tag="${line%%	*}"
    line="${line#*	}"
    want_asset="${line%%	*}"
    status="${line#*	}"
    if [[ "$want_tag" == "$tag" && "$want_asset" == "$asset" ]]; then
      printf '%s' "$status"
      return 0
    fi
  done <"$UNIVERSAL_AUTOMATION_ASSET_PROBE_MAP"
  return 1
}

http_head_ok() {
  local url="$1" code tag asset
  if [[ -n "${UNIVERSAL_AUTOMATION_ASSET_PROBE_MAP:-}" ]]; then
    tag="$(basename "$(dirname "$url")")"
    asset="$(basename "$url")"
    if code="$(probe_map_status "$tag" "$asset" 2>/dev/null)"; then
      [[ "$code" =~ ^[23] ]]
      return $?
    fi
    return 1
  fi
  if command -v curl >/dev/null 2>&1; then
    code="$(curl -sS -o /dev/null -w '%{http_code}' -I -L --max-time 15 "$url" 2>/dev/null || echo "000")"
    [[ "$code" =~ ^[23] ]]
    return $?
  fi
  return 1
}

tag_has_complete_binary_set() {
  local repo="$1" tag="$2" ver="$3" asset url
  while IFS= read -r asset; do
    [[ -n "$asset" ]] || continue
    url="$(release_download_url "$repo" "$tag" "$asset")"
    http_head_ok "$url" || return 1
  done < <(required_binary_asset_names "$ver")
  return 0
}

# Prints chosen version on stdout; no complete release => exit 1.
resolve_latest_toolkit_version() {
  local repo="$1" tag ver
  while IFS= read -r tag; do
    [[ -n "$tag" ]] || continue
    ver="${tag#${TOOLKIT_TAG_PREFIX}}"
    is_prerelease_version "$ver" && continue
    if tag_has_complete_binary_set "$repo" "$tag" "$ver"; then
      printf '%s' "$ver"
      return 0
    fi
  done < <(list_toolkit_release_tags "$repo" | sort_toolkit_tags_by_version_desc)
  echo "resolve_toolkit_release: no toolkit tag with all binary assets (HEAD probe)" >&2
  return 1
}