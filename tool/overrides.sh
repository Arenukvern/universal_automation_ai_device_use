#!/usr/bin/env bash
# Manage gitignored pubspec_overrides.yaml for local path/git experiments.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
example="${repo_root}/pubspec_overrides.yaml.example"
overrides="${repo_root}/pubspec_overrides.yaml"

usage() {
  cat <<'EOF'
Usage: tool/overrides.sh <command>

Commands:
  write    Copy pubspec_overrides.yaml.example → pubspec_overrides.yaml
  remove   Delete pubspec_overrides.yaml (if present)
  status   Show whether pubspec_overrides.yaml exists

Committed pubspec.yaml files must not contain path or absolute overrides.
EOF
}

cmd="${1:-}"
case "${cmd}" in
  write)
    if [[ ! -f "${example}" ]]; then
      echo "missing ${example}" >&2
      exit 1
    fi
    cp "${example}" "${overrides}"
    echo "Wrote ${overrides}"
    ;;
  remove)
    if [[ -f "${overrides}" ]]; then
      rm -f "${overrides}"
      echo "Removed ${overrides}"
    else
      echo "No ${overrides} (already clean)"
    fi
    ;;
  status)
    if [[ -f "${overrides}" ]]; then
      echo "present: ${overrides}"
    else
      echo "absent:  ${overrides}"
    fi
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
