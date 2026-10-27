# Changelog


## [0.3.0](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_browser_webdriver-v0.2.0...universal_browser_webdriver-v0.3.0) (2026-10-27)


### ⚠ BREAKING CHANGES

* universal_automation_interface 0.3.0 — coordinate actions, promotions, OS facades

### Features

* seamless tier routing and optional browser tier (ADR 0003) ([f6c1b68](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/f6c1b6868167dd927584ffe9644624e00388f18d))
* universal_automation_interface 0.3.0 — coordinate actions, promotions, OS facades ([6862303](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/6862303e56d1fba0a586c29e4ddc8b6157bd1bc7))


### Bug Fixes

* **train:** conformance 0.3.0 (interface ^0.3.0) + its dependents' constraints ([8396f32](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/8396f320216483faf9ce747e22da6664104b5443))

## 0.2.0

- Family train: `universal_automation_interface` moves to `^0.3.0` (coordinate-tier actions join the sealed action set) and `universal_automation_conformance` to `^0.3.0`; dependency constraints widen accordingly (constraint-widening minor bump).
## 0.1.1

- interface constraint bump to ^0.2.0.
- `KeyPressAction` actually presses keys (the wire-key mapping was dead
  code after an unconditional throw); unknown keys refuse with the
  supported set named.
- `no such element` envelopes map to `ElementNotFoundException`
  (surface state) instead of `DriverUnsupportedException`.

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 - 2026-09-27

### Added
- feat: WebDriver BiDi — `WebDriverBidiConnection`/`WebDriverBidiSession`
  (subscribe, context tree, navigate, evaluate, live events) over the
  `webSocketUrl` a new-session response advertises, plus fake-server
  BiDi coverage.

- feat: `WebDriverClient` — W3C classic sessions, navigation, elements,
  clicks, typing, key actions, screenshots.
- feat: `WebDriverDriver` adapter with honest `a11yTree: false`.
- feat: `SafariDriverEndpoint` — `safaridriver` spawn + `/status` wait.
- feat: `FakeWebDriverServer` test double
  (`package:universal_browser_webdriver/testing.dart`).
