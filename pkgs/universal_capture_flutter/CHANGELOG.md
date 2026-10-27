# Changelog


## [0.2.1](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_capture_flutter-v0.2.0...universal_capture_flutter-v0.2.1) (2026-10-27)


### Bug Fixes

* sync intra-workspace pub constraints for release-please ([84910f2](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/84910f28d94c1881ad0c5e76de8ffc503fa26a6b))
* sync intra-workspace pub constraints for release-please trains ([0887271](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/0887271c9eef9add9ca63a9eeddc4fc7626b64e7))
* **train:** conformance 0.3.0 (interface ^0.3.0) + its dependents' constraints ([8396f32](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/8396f320216483faf9ce747e22da6664104b5443))

## 0.2.0

- Family train: `universal_automation_interface` moves to `^0.3.0` (coordinate-tier actions join the sealed action set) and `universal_automation_conformance` to `^0.3.0`; dependency constraints widen accordingly (constraint-widening minor bump).
## 0.1.1

- interface/conformance constraint bump only; no code changes.

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 - 2026-09-27

### Added

- feat: `ToolkitFrameSource` — paced PNG frames from a running Flutter
  app's `ext.mcp.toolkit.view_screenshots` extension, stamped with the
  `toolkit-flutter` source id and conformant with the family frame-source
  contract suite.
- feat: `VmScreenshotGrabber` — VM-service connection owning toolkit
  isolate discovery and PNG grabs, including `normalizeWsUri` for
  `flutter run`-style `http://…/#authToken=…` announcements.
