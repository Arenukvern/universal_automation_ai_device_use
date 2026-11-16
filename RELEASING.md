# Releasing workspace packages to pub.dev

## Zero-touch publish path (default)

1. **Release Please** opens `release-please--branches--main` with version bumps and changelogs.
2. **Green CI on that PR is the gate** — steward review on the release PR plus green `Validate`. CI mirrors the publisher: co-release resolve, manifest drift (`--release-pr`), **every publishable package** `dart analyze` + `dart test` + workspace `dart pub publish --dry-run` (`validate_publishable_packages.dart --dry-run-gate`; fails on exit **65** warnings), and `--audit-published --release-pr` (in-train versions count as pending; pub.dev-latest drift warns only when the in-train dependency version actually satisfies the constraint). Tag publish still dry-runs after the exact-version dep wait in `publish_package.yml`.
3. Merge the release PR to `main`. Release Please tags `universal_<package>-v<version>` for each released component.
4. **`.github/workflows/release-please.yml`** dispatches **`.github/workflows/publish_package.yml`** once per tag (`workflow_dispatch` on the tag ref). **Pub.dev environment reviewers were removed** (Anton’s decision: zero-touch publishing). Human review is the **release PR** (second-steward review) plus green CI — not per-package deployment approvals. OIDC still mints a **fresh** token immediately before `dart pub publish --force`. Workflow-level `concurrency` (`release-please-${{ github.ref }}`, `cancel-in-progress: false`) means a later push to `main` that does **not** cut a release (or a concurrent `workflow_dispatch`) **queues** behind an in-flight train—including `wait-package-publish` and its blocking final audit—instead of cancelling it.
5. **Catch-up publish** — after dispatching tags from the release that just merged, `tool/release/catch_up_pub_dev_publish.dart` scans every publishable package in `release-please-config.json` (skips `publish_to: none` and `ecsai`), takes the highest stable `universal_<pkg>-v<semver>` git tag, and dispatches `publish_package.yml` when that version is **not** yet on pub.dev. Tags already dispatched in step 4 are deduped. A pub.dev **404** (package never published) is treated as missing but emits a loud warning (first publish still manual). **Network or non-404 HTTP errors fail the job** and dispatch nothing — uncertainty is never healed by blind dispatch. This runs on every push to `main` (even when release-please created no release), so the next merge can close a gap left by a prior failed train. `wait-package-publish` also waits on catch-up dispatches (`CATCH_UP_DISPATCHED_TAGS`).
6. **`wait-package-publish`** (180-minute job timeout) runs `tool/wait_publish_train.dart`: waits on each dispatched publish run (new `workflow_dispatch` only; one retry when the publish job failed), then runs a **blocking strict** `dart run tool/check_hosted_deps_resolve.dart --audit-published` on the merged **`main`** checkout — **main mode** (no `--release-pr`; broken pub.dev latest = error). The train **fails** if that audit exits non-zero. With **no** released tags, it still runs that same strict audit. If an environment **approval gate is ever re-added** on `pub.dev`, publishes may still complete after this job times out red — re-run **`post_publish_audit.yml`** manually when that happens.
7. **`post_publish_audit.yml`** — same strict audit, on **workflow_dispatch**, **workflow_call**, and **daily** schedule (`0 6 * * *` UTC) for manual or off-train publishes.

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

Tags: `universal_automation_toolkit-v<version>` (Release Please). When the
toolkit ships on a release train, **`release-please.yml` calls**
**`release_binaries_build.yml`** then **`release_binaries_publish.yml`** (no
`workflow_dispatch` between them — integration tokens do not reliably trigger
sibling workflows). Zero manual steps:

1. **`release-binaries-build`** (`release_binaries_build.yml`, `contents: read`
   only) runs when `pkgs/universal_automation_toolkit--release_created` is true,
   passing the toolkit tag and `dry_run: false`. It checks out **caller tooling
   ref on the default branch** plus **immutable tag source**, builds four
   matrix legs, and (for production) signs macOS when secrets are present.
2. **`release-binaries-publish`** (`release_binaries_publish.yml`, caller grants
   `contents: write` only on that reusable job). It downloads build artifacts with
   a plain `actions/download-artifact@v4` step (same top-level workflow run—no
   `run-id` / `github-token`; see [Store and share data with workflow
   artifacts](https://docs.github.com/en/actions/using-workflows/storing-workflow-data-as-artifacts#downloading-artifacts-during-a-workflow-run)
   and [download-artifact](https://github.com/actions/download-artifact)—by
   default the action downloads from the **current workflow run**, which includes
   artifacts from other reusable-workflow jobs in the same caller run).
   **Immutable GitHub releases:** the repository enables immutable releases. Release
   Please therefore creates the toolkit GitHub release as a **draft** with
   **`force-tag-creation: true`** (see `release-please-config.json` and [release-please
   manifest docs](https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md)).
   The git tag exists immediately for `publish_package.yml` and pub.dev; the GitHub
   release stays a draft so CI can upload assets. Publish asserts the release is still
   a draft, uploads **exactly** the four platform archives plus `checksums.txt`
   (`upload_draft_github_release_assets.sh`—explicit paths, no `dist/release/*` glob
   and no `--clobber`), verifies the asset list on the draft, **then** undrafts via
   `publish_github_release_from_draft.sh` only. Postflight downloads every archive from
   the **published** release URL and verifies checksums. If publish runs against an
   already-published release, it fails loudly (no silent assetless releases).
   **Release Please anchor:** without `force-tag-creation`, draft releases use GitHub
   “lazy” tags and the next `release-please` pass may open a duplicate release PR
   (entire history re-listed). The tag ref is the anchor `release-pr` uses; draft
   releases are skipped for “latest installer” resolution in `install.sh` / `install.ps1`.
3. `wait-package-publish` waits on **pub.dev only**. `audit-release-train`
   runs when pub wait succeeds or fails and **fails the workflow** if the
   toolkit released but binary build/publish did not succeed.

### PR / main path smoke (all four legs, artifacts only)

**`.github/workflows/release_binaries_pr.yml`** calls
**`release_binaries_build.yml`** with `dry_run: true`, `tooling_ref` = PR head
SHA (or `github.sha` on `main`), and **no secrets**. Fork PRs get unsigned
macOS builds. Publish never runs on PRs.

### Manual escape hatch (`workflow_dispatch`)

**`release_binaries.yml`** chains build → publish for operators:

```bash
gh workflow run release_binaries.yml \
  --repo Arenukvern/universal_automation_ai_device_use \
  --ref main \
  -f release_tag=universal_automation_toolkit-vX.Y.Z

# artifact-only (no GitHub Release upload):
gh workflow run release_binaries.yml \
  --repo Arenukvern/universal_automation_ai_device_use \
  -f dry_run=true \
  -f release_tag=<40-char-SHA-or-branch-name>
```

With `dry_run: true`, `release_tag` is a **git ref or full SHA** (not a Release
Please tag). The workflow builds all four platform legs, runs architecture checks,
writes `checksums.txt`, and uploads a single **workflow artifact** bundle.

Installers: root [`install.sh`](install.sh) / [`install.ps1`](install.ps1).
**Latest** walks toolkit **git tags** (newest semver first, skipping prereleases)
and **HEAD-probes** all five download URLs (four archives + `checksums.txt`).
No toolkit release on GitHub has ever shipped a full binary set yet
(`v0.6.0` is assetless); **latest fails clearly** until `v0.6.1+` publishes
assets. Pin `--version` / `-Version` after binaries exist. From-source:
[`plugin/install.sh`](plugin/install.sh).

**Partial draft upload / rerun:** if `release-binaries-publish` fails mid-upload,
remove the draft release’s **partial assets** in the GitHub UI, confirm
`check_release_assets_conflict.sh` is clean, then **re-run the same caller workflow**
on the immutable tag ref (do not recreate or move tags). Because upload omits
`--clobber`, a second run fails until conflicting asset names are deleted from the
draft. Only `publish_github_release_from_draft.sh` may undraft; never patch a release
from ad hoc `gh` steps in the workflow YAML.

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
