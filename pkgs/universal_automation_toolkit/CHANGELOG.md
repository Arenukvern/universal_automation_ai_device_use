# Changelog


## [0.3.0](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_automation_toolkit-v0.2.0...universal_automation_toolkit-v0.3.0) (2026-10-27)


### ⚠ BREAKING CHANGES

* universal_automation_interface 0.3.0 — coordinate actions, promotions, OS facades

### Features

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
