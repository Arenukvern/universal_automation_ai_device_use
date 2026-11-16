# Changelog


## [0.3.4](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_capture_macos-v0.3.3...universal_capture_macos-v0.3.4) (2026-11-16)


### Bug Fixes

* screencast CDP 0.6.3 train + cascade dependents (README only; sync writes constraints) ([f09c4e2](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/f09c4e25cfc0f6ea0044622042bf0709fb13337a))
* **universal_capture_macos:** require universal_screencast 0.3.3 ([26e31dc](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/26e31dce94e2f68ee0b8c6f7ad4ca0eea44d987e))

## [0.3.3](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_capture_macos-v0.3.2...universal_capture_macos-v0.3.3) (2026-11-15)


### Bug Fixes

* co-release README notes for CDP 0.6.2 train cascade ([fff11bd](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/fff11bdd999328b6d3ea84549aa3ab03c987ac37))
* note co-release with universal_browser_cdp 0.6.2 train ([dd8072a](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/dd8072a62af1e636e30a19bcde0456a202e9a9ec))

## [0.3.2](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_capture_macos-v0.3.1...universal_capture_macos-v0.3.2) (2026-11-10)


### Bug Fixes

* **universal_capture_macos:** drop unused screencast imports from tests ([cd943fb](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/cd943fbaf3ff2696af568d1735f7192e53667da8))

## [0.3.1](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_capture_macos-v0.3.0...universal_capture_macos-v0.3.1) (2026-11-10)


### Bug Fixes

* clear pub validator analyze errors in capture and driver pkgs ([d8df929](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/d8df929395c8c3591ccfd213cd2061141dbda577))
* pub validator analyze errors in capture and driver packages ([336a966](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/336a966b711705cbbe90104adbd836ea9e7207a3))

## [0.3.0](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_capture_macos-v0.2.0...universal_capture_macos-v0.3.0) (2026-10-27)


### ⚠ BREAKING CHANGES

* universal_automation_interface 0.3.0 — coordinate actions, promotions, OS facades

### Features

* universal_automation_interface 0.3.0 — coordinate actions, promotions, OS facades ([6862303](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/6862303e56d1fba0a586c29e4ddc8b6157bd1bc7))

## 0.2.0

- Family train: `universal_automation_interface` moves to `^0.3.0` (coordinate-tier actions join the sealed action set) and `universal_automation_conformance` to `^0.3.0`; dependency constraints widen accordingly (constraint-widening minor bump).
## 0.1.1

- interface constraint bump only; no code changes.

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 - 2026-09-27

### Fixed

- fix: `CaptureStream.stop` drains the SCStream delivery queue (250 ms)
  before closing the frame callback — closing immediately raced an
  in-flight delegate call and crashed the VM intermittently; the frame
  sink also guards against adds after close.

### Added
- feat: ScreenCaptureKit streaming — `CaptureStream` (continuous
  JPEG frames at a capped fps via `NativeCallable.listener`) and
  `CaptureKitFrameSource`, a screencast `FrameSource` for the
  macOS-native tier. Verified live (permission-gated).

- feat: native-assets build hook compiling the Swift capture bridge
  (CoreGraphics + ApplicationServices) into a code asset.
- feat: `CaptureBridge` — version, AX trust probe, screen-recording
  preflight/request, display enumeration, single-frame PNG capture with
  typed permission errors.

## 0.1.2

- Depend on hooks/code_assets ^2 for workspace compatibility with Flutter native-assets consumers.
