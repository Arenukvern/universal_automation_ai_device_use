#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-}"
REPO="${GITHUB_REPOSITORY:-}"
SLUG="${GITHUB_REPOSITORY_SLUG:-$REPO}"
VERSION="${VERSION:-}"

[[ -n "$TAG" && -n "$SLUG" && -n "$VERSION" ]] || {
  echo "append_binary_install_notes_to_draft_release: missing TAG, VERSION, or repo slug" >&2
  exit 1
}

command -v gh >/dev/null 2>&1 || {
  echo "append_binary_install_notes_to_draft_release: gh CLI required" >&2
  exit 1
}

is_draft="$(gh release view "$TAG" --repo "$REPO" --json isDraft -q .isDraft 2>/dev/null || true)"
if [[ "$is_draft" != "true" ]]; then
  if [[ "${RELEASE_RECOVERY_MODE:-false}" == "true" ]]; then
    echo "append_binary_install_notes_to_draft_release: release already published; skipping"
    exit 0
  fi
fi

NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
cat >"$NOTES" <<EOF
## Prebuilt \`universal-automation\` binaries

macOS darwin archives are **signed with Developer ID** when the CI
**Sign macOS bundle** step runs (\`HAS_SIGNING=true\` on the build job);
otherwise they are **preview (unsigned)** (see [RELEASING.md](RELEASING.md)).

Install without Dart:

\`\`\`sh
curl -fsSL https://raw.githubusercontent.com/${SLUG}/main/install.sh | bash -s -- --version ${VERSION}
\`\`\`

\`\`\`powershell
\$env:UNIVERSAL_AUTOMATION_VERSION='${VERSION}'; irm https://raw.githubusercontent.com/${SLUG}/main/install.ps1 | iex
\`\`\`
EOF

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/append_draft_release_binary_notes.sh" "$TAG" "$NOTES"