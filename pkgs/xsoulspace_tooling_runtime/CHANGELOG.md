# Changelog

## 0.2.0

- Move package from
  [`xsoulspace/dart_flutter_packages`](https://github.com/xsoulspace/dart_flutter_packages)
  (`pkgs/xsoulspace_tooling_runtime`) into the
  [`universal_automation_ai_device_use`](https://github.com/Arenukvern/universal_automation_ai_device_use)
  workspace as a standalone publishable member.
- Source aligned with dfp PR
  [#5](https://github.com/xsoulspace/dart_flutter_packages/pull/5) at commit
  **`2f9ce9b1`** (P0 Perl owned-session leader, `doc/owned_session_p1.md`,
  conformance suite, owned settle without pipe-EOF races). That SHA may move
  during PR review; re-sync before publish.
- UA-local stdin settlement / settlement-priority fixes are also offered upstream
  as `dfp-stdin-settlement.patch` (format-patch against `2f9ce9b1`; saved as a
  run artifact).
- Document follow-up: depend on pub.dev `oka_process` (from
  [Arenukvern/oka](https://github.com/Arenukvern/oka)) once tagged and
  published; keep `meta` only until then.
- Scope for this cut: **macOS and Linux** POSIX behavior. Windows Job Objects
  (including this repo's Windows UI Automation sidecar) remain **deferred**.
- Linux CI runs the full VM test suite except DFP PR #5 ps-fallback conformance
  cases (`SIGSTOP` + owned-session timing), which stay gated on macOS until
  `oka_process` and merged DFP PR #5 land.

## 0.1.0

- Initial extraction in dart_flutter_packages: `runBounded`, path policy,
  cooperative locks, macOS no-fork candidate verification.
