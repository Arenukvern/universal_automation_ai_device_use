# Changelog


## [0.3.0](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_driver_linux-v0.2.0...universal_driver_linux-v0.3.0) (2026-10-27)


### ⚠ BREAKING CHANGES

* universal_automation_interface 0.3.0 — coordinate actions, promotions, OS facades

### Features

* seamless tier routing and optional browser tier (ADR 0003) ([f6c1b68](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/f6c1b6868167dd927584ffe9644624e00388f18d))
* universal_automation_interface 0.3.0 — coordinate actions, promotions, OS facades ([6862303](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/6862303e56d1fba0a586c29e4ddc8b6157bd1bc7))


### Bug Fixes

* sync intra-workspace pub constraints for release-please ([84910f2](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/84910f28d94c1881ad0c5e76de8ffc503fa26a6b))
* sync intra-workspace pub constraints for release-please trains ([0887271](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/0887271c9eef9add9ca63a9eeddc4fc7626b64e7))
* **train:** conformance 0.3.0 (interface ^0.3.0) + its dependents' constraints ([8396f32](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/8396f320216483faf9ce747e22da6664104b5443))

## 0.2.0

- Family train: `universal_automation_interface` moves to `^0.3.0` (coordinate-tier actions join the sealed action set) and `universal_automation_conformance` to `^0.3.0`; dependency constraints widen accordingly (constraint-widening minor bump).
## 0.1.1

- Handle the sealed `InvokeAction` case (universal_automation_interface 0.2.0): the tier has no surface action registry, so the driver refuses loudly instead of failing to compile.

- interface constraint bump only; no code changes.

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 - 2026-09-27

### Added

- feat: `AtspiDriver` — AT-SPI2 tree observation and `Action`-based
  clicks with normalized role vocabulary.
- feat: `DBusAtspiBus` (org.a11y.Bus resolution, GetChildren with
  legacy fallback, Properties-based names) and a fake bus for tests.
