# universal_tooling_runtime

Bounded command runs with deadlines and exact stdio, plus admission helpers:
`WorkspacePathPolicy`, cooperative `FileLockTable`, and macOS
`macos_no_fork_candidate_v1` verification. Consumed by
[`ecsai_harness`](https://github.com/Arenukvern/ecsai_harness) and
[`last_answer`](https://github.com/xsoulspace/last_answer). **0.2.0** is the
first pub.dev release as `universal_tooling_runtime` (the DFP workspace name
`xsoulspace_tooling_runtime` was never published).

**Platform scope (this cut):** macOS and Linux POSIX session ownership. Windows
Job Objects (including the Windows UI Automation sidecar in this repo) are
explicitly deferred — see
[ADR 0006](../../docs/decisions/0006_tooling_runtime_into_ua_workspace.mdx).

**Dependencies:** `meta` only for **0.2.0**. [`oka_process`
0.8.1](https://pub.dev/packages/oka_process) is on pub.dev (`meta` only);
adoption is **deferred** until oka ports the posix-perl backend. Planned order:
merge UA #5 → publish this package → oka backend → switch dependency (no git/path
pin in 0.2.0).

One implementation of `runBounded`, `stopProcessTree`, and
`awaitProcessSettlement`, used through harness compatibility exports by host
coding execution/checkers and Last Answer runtime preparation.

POSIX owned sessions use the P0 Perl session leader (`tool/owned_session_p1_leader.pl`)
and the [owned session p1 contract](doc/owned_session_p1.md); conformance lives in
`test/owned_session_p1_conformance_test.dart`.

The host supplies admission, executable, arguments, CWD and limits. On POSIX a
trusted system helper establishes an acknowledged session before target exec;
deadline ownership continues through target/root exit, output drain and live
process-group membership. Successful target output and argv are unchanged.
Missing prerequisites and unobserved/escaped pipe lifetime are named failures.
Windows retains the existing root-only limitation.

The package also owns `WorkspacePathPolicy` and the cooperative, reentrant
`FileLockTable`. Path resolution checks both the lexical request and symlink
resolution against the current injected policy; missing descendants use the
nearest existing ancestor. Construction retains the original root-directory
creation behavior. The harness keeps its ECS resource and write gateway as
adapters over these mechanics.

This package grants no authority, creates no scheduler or transaction and has
no file-content writer. Path policy and cooperative locks are not OS isolation:
hard-link aliases and concurrent replacement require a qualified host boundary.
Generic process groups/sessions require a separately qualified isolation boundary. `ok` requires successful exit and no
reported settlement problem or survivors; it is not semantic task acceptance.


`MacOsCandidateVerifier.verifyCandidate` supplies the explicit
`macos_no_fork_candidate_v1` capability. Its deny-default native profile denies
Mach/AppleEvents, network and fork; a trusted launcher execs the target in its
session-leader PID. Each call grades synthetic containment controls first.
Host-built candidate/read roots, private HOME/TMPDIR, bounded stdin/EOF and
physical settlement remain separate from promotion and semantic acceptance.
The result's `physicallySettled` must be checked before candidate cleanup; false
retains scratch and the outer candidate obligation. There is no uncontained
fallback. Fork-required commands refuse by name before launch.

For Dart use direct `dartaotruntime` + SDK `gen_kernel_aot.dart.snapshot` with an
explicit VM platform, followed by `dart --disable-dart-dev` for kernel execution.
Ordinary fork-capable `dart compile`, Flutter builds and generic shell chains
remain unsupported here. The deprecated native utility needs a supported,
qualified release replacement; this adapter is not general OS isolation or
release certification. See
[ADR 0006](../../docs/decisions/0006_tooling_runtime_into_ua_workspace.mdx) and
the [qualification record](doc/evidence/2026-10-13/README.md) (imported from
dart_flutter_packages).

## Publishing

Releases use [release-please](https://github.com/googleapis/release-please) with
tag `universal_tooling_runtime-v{{version}}`. Pub.dev publish runs only via
`workflow_dispatch` (dispatched from `.github/workflows/release-please.yml` on
each release). There is no `on.push.tags` trigger, so a custom
`RELEASE_PLEASE_TOKEN` cannot double-fire publish (tag push plus dispatch).
Manual recovery: `gh workflow run publish_tooling_runtime.yml --ref
universal_tooling_runtime-vX.Y.Z`.
