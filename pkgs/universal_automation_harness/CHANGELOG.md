# Changelog


## [0.3.3](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_automation_harness-v0.3.2...universal_automation_harness-v0.3.3) (2026-11-18)


### Bug Fixes

* **universal_automation_harness:** document toolkit ^0.6.2 co-release train ([8ae5d59](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/8ae5d59ff4a3eafca001c925db8e425cbed109fd))
* **universal_automation_harness:** document toolkit ^0.6.2 co-release train ([7030f1a](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/7030f1a6ecc6a70e36ffebcaf1ed4eafb3c62fd4))

## [0.3.2](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_automation_harness-v0.3.1...universal_automation_harness-v0.3.2) (2026-11-16)


### Bug Fixes

* **universal_automation_harness:** co-release note for toolkit 0.6.1 train ([76af98a](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/76af98ac440c5b8688aaf3dd611840cf97cf0350))

## [0.3.1](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_automation_harness-v0.3.0...universal_automation_harness-v0.3.1) (2026-11-15)


### Bug Fixes

* **ci:** hook-only meta test for actionlint guard (no GNU timeout) ([0a588aa](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/0a588aa29bc183689690cf11cd30be6238f0bbbd))
* **universal_automation_harness:** co-release docs for toolkit 0.6.0 train ([5d71e84](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/5d71e849acf7503c04a4380782935b6bdd5bf3cc))
* **universal_automation_harness:** unblock release-please sync for toolkit 0.6.0 train ([49dfc69](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/49dfc6902d39371bdd7283a47d103f05a5aebb4d))

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
