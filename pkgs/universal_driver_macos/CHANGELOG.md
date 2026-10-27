# Changelog


## [0.4.0](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_driver_macos-v0.3.0...universal_driver_macos-v0.4.0) (2026-10-27)


### ⚠ BREAKING CHANGES

* universal_automation_interface 0.3.0 — coordinate actions, promotions, OS facades

### Features

* **macos:** OS-AX web-first walk, window-local clickAt, automation_preview ([8ab9a39](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/8ab9a39782d2737db145248697a9a5539b14bbfd))
* plugin ([2e51ebe](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/2e51ebe20e6085b7fae44c03e9e460a1a563c1a3))
* seamless tier routing and optional browser tier (ADR 0003) ([f6c1b68](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/f6c1b6868167dd927584ffe9644624e00388f18d))
* universal automation harness v0.1.0 (ADR 0004 §4) ([b40e35b](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/b40e35bb600482f82f24e8cbcfc02a2add31c3cc))
* universal_automation_interface 0.3.0 — coordinate actions, promotions, OS facades ([6862303](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/6862303e56d1fba0a586c29e4ddc8b6157bd1bc7))


### Bug Fixes

* **train:** conformance 0.3.0 (interface ^0.3.0) + its dependents' constraints ([8396f32](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/8396f320216483faf9ce747e22da6664104b5443))

## 0.3.0

- Family train: `universal_automation_interface` moves to `^0.3.0` (coordinate-tier actions join the sealed action set) and `universal_automation_conformance` to `^0.3.0`; dependency constraints widen accordingly (constraint-widening minor bump).
## Unreleased

- MacosDriver.windows(onScreenOnly: false) lists normal-layer windows across
  Spaces, using an additive native symbol and optional custom-bridge interface.
  The on-screen default and original ABI are preserved. MacosWindow exposes
  nullable onScreen metadata and toJson; absence stays unknown.

- Resolve Swift source dependencies from packageRoot and native outputs from
  outputDirectory. Consumer builds no longer treat a relative missing source
  as modified during the build; unchanged inputs reuse the cached dylib.
  An opt-in real native hook test verifies build, reuse and source invalidation
  through an isolated consumer without editing repository inputs.

- Refuse ambiguous role/name locators before native click, setValue, or element
  actions, including refreshed targets after stale handles. ProtocolException
  carries the locator and match count; unique locator behavior is unchanged.

## 0.2.0

- **APP MANAGEMENT — the macOS rung** (manage applications, not only the
  focused one): `runningApps()` (discovery of running Dock-able apps),
  `frontmost()`, `launch(bundleId)` (launch-or-activate; a running app is
  adopted, never relaunched), `activate(pid)`, `terminate(pid)`, and
  `snapshotOfApp(pid)` — a semantic snapshot of ANY application's AX tree,
  background included (the old snapshot stays the focused-app shorthand).
  New bridge symbols: `xs_axdrv_apps_json`, `xs_axdrv_frontmost_json`,
  `xs_axdrv_activate_app`, `xs_axdrv_launch_app`, `xs_axdrv_terminate_app`,
  `xs_axdrv_snapshot_app_json`; error codes 7 (app not found) and 8
  (activation/launch/terminate failed) join the table.
- New `MacosApp` record (pid, bundleId, name, active, hidden) — the
  discovery record every app-targeted call consumes.
- Live-proven composition: `mcp_flutter` `showcase/drivers/bin/drive_macos.dart`
  discovers the running apps, targets one by pid or bundle id, activates
  it, observes its tree, reads a BACKGROUND app by pid, verifies, and
  captures a screenshot.

## 0.1.1

- Handle the sealed `InvokeAction` case (universal_automation_interface 0.2.0): the tier has no surface action registry, so the driver refuses loudly instead of failing to compile.

- interface constraint bump only; no code changes.

## 0.1.0 (2026-09-29)

- Initial release: `MacosDriver` implementing the family's
  `AutomationDriver` contract.
- Observe: depth-bounded semantic snapshot of the focused application
  (AXUIElement → `Snapshot`/`AxNode`), plus `elementAtPosition` hit-testing
  in top-left-origin screen coordinates (the hover query for pointer-driven
  UIs).
- Act: semantic clicks via AXPress with one transparent stale-handle
  re-observe, unicode typing, named key presses, wheel-line scrolling with
  sub-line accumulation, screenshots via CGDisplayCreateImage (Screen
  Recording permission).
- Typed exceptions: `AccessibilityPermissionRequiredException`,
  `ElementNotFoundException`, `ProtocolException`,
  `DriverUnsupportedException` (navigate/evaluate have no AX equivalent).
- Native-assets build hook (swiftc → dylib → code asset, the ADR 0001
  pattern); unit tests run without the dylib via the injectable
  `AxDriverBridge` seam.

## 0.2.1

- Depend on hooks/code_assets ^2 for workspace compatibility with Flutter native-assets consumers.
