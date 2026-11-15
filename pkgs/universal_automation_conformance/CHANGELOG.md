# Changelog

## [0.4.1](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_automation_conformance-v0.4.0...universal_automation_conformance-v0.4.1) (2026-11-15)


### Bug Fixes

* co-release README notes for CDP 0.6.2 train cascade ([fff11bd](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/fff11bdd999328b6d3ea84549aa3ab03c987ac37))
* note co-release with universal_browser_cdp 0.6.2 train ([dd8072a](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/dd8072a62af1e636e30a19bcde0456a202e9a9ec))

## [0.4.0](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_automation_conformance-v0.3.1...universal_automation_conformance-v0.4.0) (2026-11-10)


### ⚠ BREAKING CHANGES

* **conformance:** conformance suites now target universal_automation_interface 0.4 types (AutomationDriver and related APIs used by automationDriverConformanceTests, FrameSource, and FrameSink conformance entrypoints). Consumers on interface 0.3 must upgrade before adopting this release.

### Bug Fixes

* **conformance:** require interface ^0.4.0 and screencast ^0.3.0 ([bf39be8](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/bf39be85f09167a37fc29784033ba892c1eebb27))

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
