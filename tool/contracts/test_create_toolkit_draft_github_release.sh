#!/usr/bin/env bash
# Behavioral smoke tests for create_toolkit_draft_github_release.sh (stubbed gh/dart).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/tool/release/create_toolkit_draft_github_release.sh"

fail() { echo "test_create_toolkit_draft_github_release: $*" >&2; exit 1; }
ok() { echo "test_create_toolkit_draft_github_release: $*"; }

[[ -x "$SCRIPT" ]] || chmod +x "$SCRIPT"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
bindir="$tmpdir/bin"
mkdir -p "$bindir"

cat >"$bindir/dart" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "run" ]]; then
  echo "Release notes body"
  exit 0
fi
command -v dart >/dev/null && exec dart "$@"
exit 0
EOF
chmod +x "$bindir/dart"

write_gh_mock() {
  local behavior="$1"
  cat >"$bindir/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" != "release" ]]; then
  echo "unexpected gh: \$*" >&2
  exit 1
fi
case "$behavior" in
  not_found)
    if [[ "\${2:-}" == "view" ]]; then
      echo "release not found" >&2
      exit 1
    fi
    if [[ "\${2:-}" == "create" ]]; then
      for a in "\$@"; do
        if [[ "\$a" == "--verify-tag" ]]; then
          echo "gh release create --verify-tag"
          exit 0
        fi
      done
      echo "missing --verify-tag" >&2
      exit 1
    fi
    ;;
  auth_error)
    if [[ "\${2:-}" == "view" ]]; then
      echo "HTTP 401: Bad credentials" >&2
      exit 1
    fi
  ;;
  existing_draft)
    if [[ "\${2:-}" == "view" ]]; then
      if [[ " \$* " == *" .isDraft "* ]]; then
        echo "true"
      fi
      exit 0
    fi
    if [[ "\${2:-}" == "edit" ]]; then
      echo "gh release edit"
      exit 0
    fi
    ;;
esac
echo "unexpected gh release: \$*" >&2
exit 1
EOF
  chmod +x "$bindir/gh"
}

export PATH="$bindir:$PATH"
export GITHUB_REPOSITORY='Arenukvern/universal_automation_ai_device_use'

write_gh_mock not_found
if ! bash "$SCRIPT" 'universal_automation_toolkit-v1.2.3' >/tmp/out.txt 2>/tmp/err.txt; then
  fail "not_found: $(cat /tmp/err.txt)"
fi
grep -q 'gh release create --verify-tag' /tmp/out.txt || fail 'not_found must create with --verify-tag'

write_gh_mock auth_error
if bash "$SCRIPT" 'universal_automation_toolkit-v1.2.3' >/tmp/out.txt 2>/tmp/err.txt; then
  fail 'auth_error must fail'
fi
grep -qi 'not a missing release' /tmp/err.txt || fail 'auth_error must fail loudly'

write_gh_mock existing_draft
if ! bash "$SCRIPT" 'universal_automation_toolkit-v1.2.3' >/tmp/out.txt 2>/tmp/err.txt; then
  fail "existing_draft: $(cat /tmp/err.txt)"
fi
grep -q 'Updated draft' /tmp/out.txt || fail 'existing_draft must edit'

ok OK