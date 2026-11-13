# Releasing workspace packages to pub.dev

## Zero-touch publish path (default)

1. **Release Please** opens `release-please--branches--main` with version bumps and changelogs.
2. **Green CI on that PR is the gate** — steward review on the release PR plus green `Validate`. CI mirrors the publisher: co-release resolve, manifest drift (`--release-pr`), **every publishable package** `dart analyze` + `dart test` via workspace resolution (`tool/validate_publishable_packages.dart`; publish dry-run stays on `publish_package.yml` after the exact-version dep wait), and `--audit-published --release-pr` (in-train versions count as pending; broken pub.dev-latest sibling edges in the release set warn instead of blocking).
3. Merge the release PR to `main`. Release Please tags `universal_<package>-v<version>` for each released component.
4. **`.github/workflows/release-please.yml`** dispatches **`.github/workflows/publish_package.yml`** once per tag (`workflow_dispatch` on the tag ref). **Pub.dev environment reviewers were removed** (Anton’s decision: zero-touch publishing). Human review is the **release PR** (second-steward review) plus green CI — not per-package deployment approvals. OIDC still mints a **fresh** token immediately before `dart pub publish --force`.
5. **`wait-package-publish`** (180-minute job timeout) waits on each dispatched publish run, watching **new** `workflow_dispatch` runs only, **re-dispatches once** when the **publish** job actually failed (not skipped/cancelled/waiting), then runs **`check_hosted_deps_resolve.dart --audit-published`** as a blocking step. If an environment **approval gate is ever re-added** on `pub.dev`, publishes may still complete after this job times out red — treat **`post_publish_audit.yml`** as the authoritative final audit and re-run it manually when that happens.
6. **Post-publish audit** remains available manually: Actions → **Post-publish audit** → Run workflow.

**Deployment policy:** GitHub can deploy only from tag refs matching `universal_*-v*`. Tags are **immutable** via the `release-tags-immutable` ruleset (Admin-only bypass). Do not move or recreate tags to “fix” constraint drift — land a new version instead.

Constraint sync dispatches `validate.yml` on branch `release-please--branches--main` with `expected_sha` so CI verifies the exact synced commit (workflow_dispatch cannot target a bare SHA ref).

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
