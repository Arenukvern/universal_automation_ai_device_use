# Changelog


## [0.3.0](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_automation_harness-v0.2.0...universal_automation_harness-v0.3.0) (2026-11-10)


### Features

* **semantics:** SemanticLens — compact and design render usefulness ([1c6f798](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/1c6f7982a1764ea090860d23aff284c5df073159))


### Bug Fixes

* **universal_automation_harness:** document toolkit ^0.5.0 requirement ([0ff3134](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/0ff3134b3ec29d7dafe114ce8732f44263599502))
* **universal_automation_harness:** release with toolkit 0.5.0 constraint sync ([ddeb7b4](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/ddeb7b41854e98ce6916ab78a2780ff933a279f9))
* **universal_automation_harness:** release with toolkit 0.5.0 constraint sync ([bff1854](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/bff1854a492d5f53b7170cc7427406c7f5a9b67b))

## [0.2.0](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_automation_harness-v0.1.1...universal_automation_harness-v0.2.0) (2026-10-27)


### ⚠ BREAKING CHANGES

* universal_automation_interface 0.3.0 — coordinate actions, promotions, OS facades

### Features

* universal automation harness v0.1.0 (ADR 0004 §4) ([b40e35b](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/b40e35bb600482f82f24e8cbcfc02a2add31c3cc))
* universal_automation_interface 0.3.0 — coordinate actions, promotions, OS facades ([6862303](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/6862303e56d1fba0a586c29e4ddc8b6157bd1bc7))

## 0.1.1

- Family train: `universal_automation_interface` moves to `^0.3.0` (coordinate-tier actions join the sealed action set) and `universal_automation_conformance` to `^0.3.0`; dependency constraints widen accordingly (constraint-widening minor bump).
## 0.1.0

- Initial release (ADR 0004's harness layer, built on the interface
  promotions and the de-nativized toolkit core):
  - `AutomationAssembly`: sessions, commands, flows, budgets — compiles
    to one `AutomationPlan`, fail closed with every violation at once;
    `snapshot()` for agents, `explain()` for humans.
  - `Flow`: named scenario trees with session defaults that inherit down
    the `extend` chain; the toolkit owns chain semantics.
  - Versioned commands (`CommandSpec` / `CommandRegistry` / `runCommand`):
    declared codec + revision identity + non-cryptographic revision hash;
    compile-time expansion so CLI, serve, and an in-app agent execute
    identical steps.
  - Budgets as components (`ServeBudgets` / `BudgetGuard` /
    `HarnessRunner`): concurrency admission, per-run deadline enforced by
    the toolkit runner at step boundaries, idle/lifetime exit signals —
    the self-bounding serve, inside an oka-supervised process.
  - `RuleEnvelope`: typed rule/guide carrier; content stays world data.
