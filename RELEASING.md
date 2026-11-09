# Releasing workspace packages to pub.dev

## Sanctioned publish path

Run the publish train **on the owner’s Mac** with their own pub.dev credentials (`dart pub token` / interactive login). CI does not publish family packages.

```bash
dart pub get
dart run tool/publish_in_order.dart
# prints release set, publish_order.yaml sequence, and exact `(cd pkgs/… && dart pub publish)` commands (dry-run)

dart run tool/publish_in_order.dart --publish
# prompts: type `publish` to confirm

dart run tool/publish_in_order.dart --publish --yes
# non-interactive confirm (scripts only; prefer interactive)
```

Default is **dry-run** (`dart pub publish --dry-run` per release-set package). Real publishes need `--publish` plus confirmation (`publish` on stdin) or `--yes`.

`tool/publish_in_order.dart` reads `tool/publish_order.yaml`, selects the **release set** (pubspec > pub.dev latest and not yet on pub.dev), runs the full **version policy** + co-release resolve, verifies siblings are already on pub.dev before each package, runs `dart pub publish` per package in order, **waits** for each exact version on the pub.dev API, then runs **`--audit-published`** at the end.

**Do not** run bare `dart pub publish` from package directories outside this train — order and pub.dev visibility are not enforced.

### Version policy (CI + publish train)

- **Manifest** (release-please) = last released version on `main`; on an open **release-please PR** the manifest is bumped to the **next** version together with pubspec (not yet on pub.dev).
- **Blocking everywhere** except on **`main` and ordinary PRs** until companion PR **#24** lands: manifest markers that trail pub.dev (`manifest < pub.dev latest`, or manifest version never shipped) are **warnings** on the blocking `--co-release --warn-manifest-behind-pub` step (not errors). **Release paths** keep manifest-behind blocking; see the table below for manifest-not-on-pub.dev. **Git-tag reuse** runs only on `--check-manifest-drift` paths, and only for packages in the **release set** (not on ordinary PR validate).
- Pubspec < pub.dev latest → error (backward). Pubspec equals pub.dev latest → OK only if unchanged since git tag `<package>-v<version>` (else version reuse error; no tag → OK with warning). Pubspec on pub.dev but not latest → reuse error. Pending packages (ahead of pub.dev, not published) satisfy sibling constraints via co-release in `publish_order.yaml` order.

| Context | Command | Manifest not on pub.dev |
| --- | --- | --- |
| `main` / ordinary PR validate | `--co-release --warn-manifest-behind-pub` | Warning (if manifest trails policy) |
| Publish / tag workflows | `--co-release --check-manifest-drift` | Error: claimed release never shipped |
| **Release-please PR** sync job | `--co-release --check-manifest-drift --release-pr` | OK when manifest == pubspec **>** pub.dev latest (pending release); otherwise error |
| Post-publish | `--audit-published` | N/A (all workspace versions must exist on pub.dev) |

`--release-pr` is only valid with `--check-manifest-drift`. Pre-publish `--audit-published` runs from `publish_in_order.dart` and `post_publish_audit.yml`, not from the release-please constraint sync job.

`universal_tooling_runtime` additionally has [`.github/workflows/publish_tooling_runtime.yml`](.github/workflows/publish_tooling_runtime.yml) (tag dispatch). All other family packages are manual via `publish_in_order.dart`.

## After every publish train

1. Confirm the train finished with **post-publish audit** passing (automatic with `--publish`).
2. Optionally re-run the workflow: **Actions → Post-publish audit → Run workflow** (`post_publish_audit.yml`), which runs `dart run tool/check_hosted_deps_resolve.dart --audit-published` (blocking, fail closed).

## Release-please

The **sync-release-pr-constraints** job checks out the release-please branch at the repo root (for `pkgs/` and manifest) and a nested **trusted** checkout of the triggering `main` commit; it runs `dart run trusted/tool/…` from the release tree so guards like `--release-pr` always match CI on `main`.

Merge release-please PRs only when **release-path** CI passes: co-release resolve and release-PR version policy (`--check-manifest-drift --release-pr`) on the release branch.

See also [ADR 0001](docs/decisions/0001_drivers_into_ua_private_oss_ready.mdx) (publish order) and [PR #23](https://github.com/Arenukvern/universal_automation_ai_device_use/pull/23) (guards).
