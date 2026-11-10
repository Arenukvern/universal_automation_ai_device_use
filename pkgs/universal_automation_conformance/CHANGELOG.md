# Changelog

## Unreleased

### Breaking changes

- Require `universal_automation_interface` `^0.4.0`: conformance entrypoints
  (`automationDriverConformanceTests`, frame source/sink suites) take types from
  interface 0.4, so consumers on interface 0.3 must upgrade before adopting this
  release. Also align `universal_screencast` to `^0.3.0` (republish after silent
  drift: chore constraint sync never bumped pub.dev `0.3.1`).

## 0.3.1

- `universal_screencast` constraint widens to `^0.2.0` (missed when the
  family widened; 0.3.0 shipped with the stale pin).

## 0.3.0

- Interface constraint moves to `^0.3.0` (coordinate-tier actions in the
  sealed set); the universal navigate conformance suite gains loud
  scheme-allowlist refusals and the navigate-capability check.

## 0.2.0

- Added `behaviorSynthesisConformanceTests()` — hermetic synthesis
  contract for the behavior dynamics (ADR 0044): plan determinism,
  agentImmediate symmetry litmus, humanPrior range conformance, canonical
  round-trips, fail-closed construction, cadence floors, and the golden
  plan-hash vector.
- Depends on `universal_automation_interface` ^0.2.0.
