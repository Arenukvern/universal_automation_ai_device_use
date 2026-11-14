# Releasing workspace packages to pub.dev

## Zero-touch publish path (default)

1. **Release Please** opens `release-please--branches--main` with version bumps and changelogs.
2. **Green CI on that PR is the gate** — steward review on the release PR plus green `Validate`. CI mirrors the publisher: co-release resolve, manifest drift (`--release-pr`), **every publishable package** `dart analyze` + `dart test` + workspace `dart pub publish --dry-run` (`validate_publishable_packages.dart --dry-run-gate`; fails on exit **65** warnings), and `--audit-published --release-pr` (in-train versions count as pending; pub.dev-latest drift warns only when the in-train dependency version actually satisfies the constraint). Tag publish still dry-runs after the exact-version dep wait in `publish_package.yml`.
3. Merge the release PR to `main`. Release Please tags `universal_<package>-v<version>` for each released component.
4. **`.github/workflows/release-please.yml`** dispatches **`.github/workflows/publish_package.yml`** once per tag (`workflow_dispatch` on the tag ref). **Pub.dev environment reviewers were removed** (Anton’s decision: zero-touch publishing). Human review is the **release PR** (second-steward review) plus green CI — not per-package deployment approvals. OIDC still mints a **fresh** token immediately before `dart pub publish --force`. Workflow-level `concurrency` (`release-please-${{ github.ref }}`, `cancel-in-progress: false`) means a later push to `main` that does **not** cut a release (or a concurrent `workflow_dispatch`) **queues** behind an in-flight train—including `wait-package-publish` and its blocking final audit—instead of cancelling it.
5. **`wait-package-publish`** (180-minute job timeout) runs `tool/wait_publish_train.dart`: waits on each dispatched publish run (new `workflow_dispatch` only; one retry when the publish job failed), then runs a **blocking strict** `dart run tool/check_hosted_deps_resolve.dart --audit-published` on the merged **`main`** checkout — **main mode** (no `--release-pr`; broken pub.dev latest = error). The train **fails** if that audit exits non-zero. With **no** released tags, it still runs that same strict audit. If an environment **approval gate is ever re-added** on `pub.dev`, publishes may still complete after this job times out red — re-run **`post_publish_audit.yml`** manually when that happens.
6. **`post_publish_audit.yml`** — same strict audit, on **workflow_dispatch**, **workflow_call**, and **daily** schedule (`0 6 * * *` UTC) for manual or off-train publishes.

**Deployment policy:** GitHub can deploy only from tag refs matching `universal_*-v*`. Tags are **immutable** via the `release-tags-immutable` ruleset (Admin-only bypass). Do not move or recreate tags to “fix” constraint drift — land a new version instead.

Constraint sync dispatches `validate.yml` on branch `release-please--branches--main` with `expected_sha` so CI verifies the exact synced commit (workflow_dispatch cannot target a bare SHA ref).

### `Validate` on `main` vs release PR vs train end

| When | `--audit-published` | Blocks? |
| --- | --- | --- |
| Release-please PR | with `--release-pr` | yes |
| Ordinary PR | report only (`continue-on-error`) | no |
| Push to `main` (`Validate`) | **skipped** (would race in-flight publishes; was report-only anyway) | — |
| **`wait-package-publish` (train end)** | strict main mode | **yes** |
| `post_publish_audit.yml` | strict main mode | yes (manual / daily / callable) |

The **authoritative strict audit after a release merge** is the tail of **`wait-package-publish`**, not `Validate` on the same push.

### Manual publish recovery (single package)

```bash
gh workflow run publish_package.yml \
  --repo Arenukvern/universal_automation_ai_device_use \
  --ref universal_<package>-vX.Y.Z
```

`publish_package.yml` jobs: **guard** (tag ref + pubspec) → **ci** (release-path resolve + audit + analyze/test) → **publish** (skip-if-listed on pub.dev via object-shaped `/api/packages` versions, runtime dep wait, dry-run, OIDC, `dart pub publish --force`) → **verify** (exact version on pub.dev). Same-tag reruns are serialized (`concurrency: publish-${{ github.ref }}`).

### First publish of a **new** package (one-time manual)

Before CI can publish a package that has never been on pub.dev:

1. Publish **manually once** on pub.dev (owner credentials).
2. On pub.dev → package → **Automated publishing from GitHub Actions**:
   - Tag pattern: `<pkg>-v{{version}}` (e.g. `universal_foo-v{{version}}`)
   - Environment: `pub.dev`
3. Subsequent releases use the zero-touch path above.

Pub.dev deployment in GitHub is restricted to `universal_*-v*` tag refs. **Do not** set `ACTIONS_ID_TOKEN_REQUEST_*` in workflow env; the `pub.dev` environment provides OIDC (`id-token: write`). Published tokens are masked.

### Manual fallback train (`publish_in_order`)

For bulk recovery on a maintainer machine with local pub.dev credentials:

```bash
dart pub get
dart run tool/publish_in_order.dart          # dry-run + commands
dart run tool/publish_in_order.dart --publish --yes
```

Reads `tool/publish_order.yaml`, publishes in dependency order, waits for each version on pub.dev, then runs `--audit-published` (with tag-source provenance).

**Do not** run bare `dart pub publish` outside CI or this train.

### Version policy (summary)

| Context | Command |
| --- | --- |
| Ordinary PR / `main` | `--co-release --warn-manifest-behind-pub` |
| **Release-please PR** | `--co-release --check-manifest-drift --release-pr` + full publishable package tests + `--audit-published` |
| Tag publish workflow | `--co-release --check-manifest-drift --release-pr` + `--audit-published` |
| Post-publish / train end | `--audit-published` |

`--release-pr` accepts pending manifest == pubspec ahead of pub.dev. Published exact-version workspace constraints must match pub.dev archives; tag-source vs hosted mismatches are checked with a **known-history allowlist** (e.g. harness `0.3.0` toolkit pin, screencast `0.3.1` CDP pin) — reported as warnings, not repaired by retagging.

### Release-please constraint sync

The **sync-release-pr-constraints** job writes sibling pins on the release-please branch. When it pushes, CI is dispatched at the **exact synced commit SHA** (`gh workflow run validate.yml --ref <sha>`). Constraint-only commits use `chore:` so release-please does not treat them as releasable churn.

Re-run Release Please from **`main`** only (`workflow_dispatch` / push), never from unreviewed branches.

See [ADR 0001](docs/decisions/0001_drivers_into_ua_private_oss_ready.mdx) for publish order rationale.

## Toolkit GitHub Release binaries (no Dart install)

Tags: `universal_automation_toolkit-v<version>` (Release Please). GitHub Releases
are created by Release Please with `GITHUB_TOKEN`; **tag/release events do not
trigger other workflows**, so binary builds are started only via explicit
`workflow_dispatch`:

1. **`dispatch-release-binaries`** in `release-please.yml` runs
   `dart run tool/dispatch_release_binaries.dart` when the toolkit is in
   `paths_released` (same train as pub.dev publish).
2. **`.github/workflows/release_binaries.yml`** checks out **trusted tooling on
   `main`** plus **immutable tag source**, builds `dart build cli` per matrix
   (darwin-arm64 on `macos-15`, darwin-x64 on `macos-15-intel` — GitHub retired
   `macos-13` on 2025-12-04; Intel runners sunset **Aug 2027**, linux-x64,
   windows-x64 zip), verifies architectures (CLI **and**
   bundled `.dylib`/`.so`/`.dll`), uploads assets to the **existing** toolkit
   release, writes `checksums.txt`, and **postflight**
   `assert_release_assets_complete.sh` asserts every expected asset is present.
3. **`wait-package-publish`** waits for `release_binaries.yml` when the toolkit
   shipped this train (before the strict post-publish audit).

Manual recovery (re-attach assets for an old tag):

```bash
gh workflow run release_binaries.yml \
  --repo Arenukvern/universal_automation_ai_device_use \
  --ref main \
  -f release_tag=universal_automation_toolkit-vX.Y.Z
```

### Dry-run binary build (pre-release smoke)

`workflow_dispatch` loads the workflow definition from the **default branch**
(`main`), not from a release PR branch. After merging the release-binary workflow
to `main` and **before** the first real toolkit release, run a dry build from an
arbitrary commit:

```bash
gh workflow run release_binaries.yml \
  --repo Arenukvern/universal_automation_ai_device_use \
  --ref main \
  -f dry_run=true \
  -f release_tag=<40-char-SHA-or-branch-name>
```

With `dry_run: true`, `release_tag` is a **git ref or full SHA** (not a Release
Please tag). The workflow builds all four platform legs, runs architecture checks,
writes `checksums.txt`, and uploads a single **workflow artifact** bundle. It does
**not** upload to the GitHub Release, and `publish` / `postflight` are skipped.

Installers: root [`install.sh`](install.sh) / [`install.ps1`](install.ps1).
From-source path remains [`plugin/install.sh`](plugin/install.sh).

Plugin bundle versions (`plugin/.cursor-plugin/plugin.json`,
`plugin/.claude-plugin/plugin.json`) are Release Please **extra-files** on the
toolkit package so they stay equal to the binary version.

### macOS code signing (optional; not configured yet)

TCC **Accessibility** and **Screen Recording** grants are tied to the code
signature on macOS. Unsigned builds lose those grants on every binary update.
When ready, add these GitHub **Actions secrets** (all optional; the workflow
skips signing when they are absent):

| Secret | Purpose |
| --- | --- |
| `MACOS_CERT_P12` | Base64-encoded Developer ID Application `.p12` (decoded only in the dedicated macOS **Sign** step — never passed as a filesystem path to build scripts) |
| `MACOS_CERT_PASSWORD` | Import password for the `.p12` (same isolated step as the cert) |
| `MACOS_CODESIGN_IDENTITY` | Optional explicit identity name |
| `APPLE_ID` / `APPLE_TEAM_ID` / `APPLE_APP_PASSWORD` | Notarization (future) |
| App Store Connect API key vars | Alternative notarization (future) |

Until then, release notes and docs mark macOS artifacts as **preview (unsigned)**.
