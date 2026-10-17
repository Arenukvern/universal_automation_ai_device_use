# Changelog


## 0.2.0

- Family train: `universal_automation_interface` moves to `^0.3.0` (coordinate-tier actions join the sealed action set) and `universal_automation_conformance` to `^0.3.0`; dependency constraints widen accordingly (constraint-widening minor bump).
## 0.1.2

- chore: universal_browser_cdp 0.3.0

## 0.1.1

- interface/cdp constraint bump only; no code changes.

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 - 2026-09-27

### Added

- feat: `Frame`, `FrameSource`, `FrameSink` contracts with declared
  capabilities.
- feat: `ScreencastComposition` fail-closed validation (capability
  matrix, pacing floors per audience) and `ScreencastPipeline` with
  per-sink isolation and structured events.
- feat: `CdpScreencastFrameSource` and `PollingFrameSource`.
- feat: `WebSocketFrameServer`, `MjpegHttpSink`, `FileRecorderSink`.

## 0.1.2

- Require `universal_browser_cdp` ^0.3.0 (align with toolkit / current CDP).
