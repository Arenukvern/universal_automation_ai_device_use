# Changelog


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
