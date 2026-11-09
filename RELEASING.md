# Releasing workspace packages to pub.dev

## Sanctioned publish path

Use the publish train only:

```bash
dart pub get
dart run tool/publish_in_order.dart              # dry-run (default)
dart run tool/publish_in_order.dart --publish    # owner: real publishes
```

`tool/publish_in_order.dart` reads `tool/publish_order.yaml`, selects the **release set** (pubspec versions not yet on pub.dev), runs co-release + manifest drift checks, verifies siblings are already on pub.dev before each package, runs `dart pub publish` per package in order, **waits** for each exact version on the pub.dev API, then runs **`--audit-published`** at the end.

**Do not** run bare `dart pub publish` from package directories outside this train — order and pub.dev visibility are not enforced.

`universal_tooling_runtime` additionally has [`.github/workflows/publish_tooling_runtime.yml`](.github/workflows/publish_tooling_runtime.yml) (tag dispatch). All other family packages are manual via `publish_in_order.dart`.

## After every publish train

1. Confirm the train finished with **post-publish audit** passing (automatic with `--publish`).
2. Optionally re-run the workflow: **Actions → Post-publish audit → Run workflow** (`post_publish_audit.yml`), which runs `dart run tool/check_hosted_deps_resolve.dart --audit-published` (blocking, fail closed).

## Release-please

Merge release-please PRs only when **release-path** CI passes: co-release resolve, manifest drift, and pub.dev audit on the release branch.

See also [ADR 0001](docs/decisions/0001_drivers_into_ua_private_oss_ready.mdx) (publish order) and [PR #23](https://github.com/Arenukvern/universal_automation_ai_device_use/pull/23) (guards).
