# Changelog

## 0.2.0

- Move package from
  [`xsoulspace/dart_flutter_packages`](https://github.com/xsoulspace/dart_flutter_packages)
  into the
  [`universal_automation_ai_device_use`](https://github.com/Arenukvern/universal_automation_ai_device_use)
  workspace as a standalone publishable member. **UA is the canonical home**; DFP
  PR [#5](https://github.com/xsoulspace/dart_flutter_packages/pull/5) is closed
  without merge.
- Import consolidated from dfp branch
  `fix/harness-owned-pid-snapshot-5165` (includes P0 p1 leader, conformance,
  stdin settlement, oka review ports); last full-sync tip **`f34e4cf`** on
  `cursor/move-tooling-runtime-0ca3`.
- **Dependencies:** `meta` only for this release. [`oka_process`
  0.8.1](https://pub.dev/packages/oka_process) is on pub.dev (`meta` only);
  **adoption deferred** until oka lands the posix-perl backend. Order: merge UA
  #5 → publish 0.2.0 → oka backend → tooling_runtime switches.
- Scope: **macOS and Linux** POSIX behavior. Windows Job Objects (including this
  repo's Windows UI Automation sidecar) remain **deferred**.
- Linux gate: `dart test --concurrency=1` — **53/53** (Windows-only skips);
  `tool/run_p1_oka_probes.sh`.

## 0.1.0

- Initial extraction in dart_flutter_packages: `runBounded`, path policy,
  cooperative locks, macOS no-fork candidate verification.
