# Changelog


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
