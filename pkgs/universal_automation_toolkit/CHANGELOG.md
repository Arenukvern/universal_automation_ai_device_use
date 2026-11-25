# Changelog

## 0.6.3

### Patch Changes

- Release tooling: version PRs and tags now come from dart_changesets (no API changes).

## [0.6.2](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_automation_toolkit-v0.6.1...universal_automation_toolkit-v0.6.2) (2026-11-18)


### Bug Fixes

* **universal_automation_toolkit:** document 0.6.2+ GitHub binaries after 0.6.1 gap ([7918565](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/79185657715752eac6161f14b33b020ab90c1b49))
* **universal_automation_toolkit:** document 0.6.2+ GitHub binaries after 0.6.1 gap ([485be69](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/485be6973515f88655fa7adadf9ef87d25e7f97c))

## [0.6.1](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_automation_toolkit-v0.6.0...universal_automation_toolkit-v0.6.1) (2026-11-16)


### Bug Fixes

* **install:** resolve latest via git tags and asset HEAD probes ([d742bee](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/d742bee6e6ba9432c805d8c6b15921614e7e0734))
* **universal_automation_toolkit:** draft GitHub release flow for immutable binaries ([f8868a8](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/f8868a8a3887f95a9417cf24a22fc7c0b48a4176))

## [0.6.0](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_automation_toolkit-v0.5.1...universal_automation_toolkit-v0.6.0) (2026-11-15)


### Features

* **toolkit:** prebuilt universal-automation binaries on GitHub Releases ([93046a8](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/93046a826815d9f8ff30f69bcd2f3e70311c46f7))
* **toolkit:** ship prebuilt MCP binaries on GitHub Releases ([4d0e8a3](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/4d0e8a3e03edb71414d6ea76c25a8774ed90470a))


### Bug Fixes

* **universal_automation_toolkit:** release-please extra-files for version surfaces ([71bce0e](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/71bce0e8f3b6bec2835b4a5a85a6c6d9d9278ee8))
* **universal_automation_toolkit:** release-please version surfaces + CDP reaction floor clock ([a3f2a0e](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/a3f2a0ea964a4b5e7463a24adc5c390915e49111))

## [0.5.1](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_automation_toolkit-v0.5.0...universal_automation_toolkit-v0.5.1) (2026-11-10)


### Bug Fixes

* **universal_automation_toolkit:** remove analyzer warnings from examples and mcp server ([a6e2199](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/a6e21999578b645a15bcb604404547f241d24157))

## [0.5.0](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_automation_toolkit-v0.4.0...universal_automation_toolkit-v0.5.0) (2026-11-10)


### Features

* **semantics:** SemanticLens — compact and design render usefulness ([1c6f798](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/1c6f7982a1764ea090860d23aff284c5df073159))


### Bug Fixes

* **ci:** sync toolkit constraint for universal_driver_flutter 0.1.1 ([04f687a](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/04f687ae4af92e7ab9d02967a80b12d165a23be3))
* **ci:** sync toolkit workspace constraint after driver_flutter 0.1.1 ([f2d15e6](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/f2d15e68446ee50e1a72649e79c2c0debb5682e4))

## 0.4.0

- **Native Flutter vmService tier**: `--vm <vm-service-uri>` (env
  `UNIVERSAL_AUTOMATION_VM`) drives instrumented Flutter apps through
  `universal_driver_flutter` — the MCP toolkit's public
  `ext.mcp.toolkit.*` wire — and `transport: "vmService"` works in the
  MCP server with per-call endpoints. `SessionRegistry` links vmService
  as a builtin factory next to cdp/webdriver; composition roots can
  still replace it.

## [0.3.0](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_automation_toolkit-v0.2.0...universal_automation_toolkit-v0.3.0) (2026-10-27)


### ⚠ BREAKING CHANGES

* universal_automation_interface 0.3.0 — coordinate actions, promotions, OS facades

### Features

* **computer-use:** Codex-parity pid pointer, automation_computer, and evidence ([29f22be](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/29f22be3112f97b7080166960840aa20326c3d66))
* **macos:** OS-AX web-first walk, window-local clickAt, automation_preview ([8ab9a39](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/8ab9a39782d2737db145248697a9a5539b14bbfd))
* plugin ([2e51ebe](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/2e51ebe20e6085b7fae44c03e9e460a1a563c1a3))
* seamless tier routing and optional browser tier (ADR 0003) ([f6c1b68](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/f6c1b6868167dd927584ffe9644624e00388f18d))
* universal automation harness v0.1.0 (ADR 0004 §4) ([b40e35b](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/b40e35bb600482f82f24e8cbcfc02a2add31c3cc))
* universal_automation_interface 0.3.0 — coordinate actions, promotions, OS facades ([6862303](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/6862303e56d1fba0a586c29e4ddc8b6157bd1bc7))

## 0.2.0

- Family train: `universal_automation_interface` moves to `^0.3.0` (coordinate-tier actions join the sealed action set) and `universal_automation_conformance` to `^0.3.0`; dependency constraints widen accordingly (constraint-widening minor bump).
## 0.1.0

- Initial release: declarative plans (sessions/profiles/intents/
  scenarios, `extends` + `include` composition, fail-closed validation),
  the plan runner with structured reports and ADR 0044 behavior
  receipts, the `universal-automation` CLI (observe/act/verify/
  screenshot/validate/run/serve), and the MCP stdio server
  (`automation_observe/act/verify/screenshot/validate_plan/run_plan`).
- v1 links the CDP tier; other transports fail loudly until linked
  (ADR 0046).

## 0.1.1

- Require `universal_driver_macos` ^0.2.1 (hooks/code_assets ^2) and `universal_screencast` ^0.1.2 (CDP ^0.3).

