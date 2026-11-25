# Releasing workspace packages to pub.dev

## dart_changesets train (default)

1. **Intent files** — contributors add `.changesets/*.md` in feature PRs:
   `dart run dart_changesets@^1.0.2 add` (or hand-write front matter: `'<package>': patch|minor|major`).
2. **Merge to `main`** — [`.github/workflows/release.yml`](.github/workflows/release.yml) opens/updates `changesets/version-packages`.
3. **Green CI on the version PR** is the gate: intra-workspace constraint check, co-release resolve, manifest drift (`--release-pr`), every publishable package `dart pub publish --dry-run` via [`validate_publishable_packages.dart`](tool/validate_publishable_packages.dart) (warnings → exit **67**), and blocking `--audit-published --release-pr`.
4. **Merge the version PR** — dart_changesets pushes one `<package>-v<version>` tag per release and starts [`publish.yml`](.github/workflows/publish.yml) per tag (tag push + PAT, or `workflow_dispatch` when preflight).
5. **`publish.yml`** — reusable `Arenukvern/dart_changesets/.github/workflows/publish.yml@v1` publishes to pub.dev (OIDC). For `universal_automation_toolkit-v*` only: draft GitHub release + [`release_binaries_build.yml`](.github/workflows/release_binaries_build.yml) → [`release_binaries_publish.yml`](.github/workflows/release_binaries_publish.yml) (four platform archives + `checksums.txt`; same install.sh / asset names as before).

**Human review** is the version-packages PR plus green CI — not per-package deployment approvals. Pub.dev automated publishing must use tag pattern `<package>-v{{version}}` with **Require GitHub Actions environment** OFF.

**Deployment policy:** tags `universal_*-v*` are immutable (`release-tags-immutable` ruleset). Do not move tags; land a new version instead.

### Constraint sync (#62)

`dart_changesets version` rewrites sibling `^` constraints only when the caret no longer admits the new sibling version (same policy as [`sync_workspace_pub_constraints.dart`](tool/sync_workspace_pub_constraints.dart)). CI still runs `dart run tool/sync_workspace_pub_constraints.dart --check` on every PR to block lowering hand-raised floors that changesets does not touch.

### Manual publish recovery (single package)

```bash
gh workflow run publish.yml \
  --repo Arenukvern/universal_automation_ai_device_use \
  --ref universal_<package>-vX.Y.Z \
  -f tag=universal_<package>-vX.Y.Z \
  -f execute=true
```

`dart_changesets publish-tag` inside the reusable workflow runs guard → analyze/test → strict dry-run → OIDC `pub publish --force` → verify on pub.dev.

### First publish of a new package

1. One manual `dart pub publish` / `flutter pub publish` from the package directory.
2. pub.dev → package → **Automated publishing** → repository + tag pattern `<package>-v{{version}}`.
3. Re-dispatch `publish.yml` on the tag (`execute=true`); skip-existing is idempotent.

### Manual bulk recovery

```bash
dart pub get
dart run tool/publish_in_order.dart
dart run tool/publish_in_order.dart --publish --yes
```

### Post-publish audit

[`post_publish_audit.yml`](.github/workflows/post_publish_audit.yml) — strict `--audit-published` on schedule, `workflow_dispatch`, and `workflow_call`.

## Toolkit GitHub Release binaries

When the toolkit tag’s `publish` job succeeds, `toolkit-github-release` creates/updates a **draft** GitHub release (notes from `dart run dart_changesets@^1.0.2 release-notes`). Binaries jobs upload assets and undraft — same immutable-release contract as before (see [`tool/release/`](tool/release/)).

PR smoke: [`.github/workflows/release_binaries_pr.yml`](.github/workflows/release_binaries_pr.yml) (`dry_run: true`). Manual recovery: [`.github/workflows/release_binaries.yml`](.github/workflows/release_binaries.yml).

## Local checks before proposing a release

```bash
dart run dart_changesets@^1.0.2 doctor
dart run dart_changesets@^1.0.2 version --check
dart run tool/sync_workspace_pub_constraints.dart --check
dart run tool/validate_publishable_packages.dart --dry-run-gate
```