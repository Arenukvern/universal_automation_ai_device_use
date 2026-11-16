# universal_screencast

Declarative frame pipeline: `FrameSource` → `FrameSink` with fail-closed
composition validation and audience policies. Frames are read-only
observations — `frames != semantics`.

Intra-workspace `universal_browser_cdp` constraints are synced on each
release-please train (see
[RELEASING.md](https://github.com/Arenukvern/universal_automation_ai_device_use/blob/main/RELEASING.md)).
Screencast releases that adopt a new CDP minor (for example 0.6.2 after the
behavior reaction-floor fix) ship in the same release PR as `universal_browser_cdp`.

## Requirements

`CdpScreencastFrameSource` and CDP-backed pacing assume **`universal_browser_cdp`
0.6.3 or newer** for the monotonic pause / drift fix in behavior timing. Hosted
`pubspec.yaml` pins are updated by the release-please constraint sync when
screencast enters a train; they are not edited by hand on `main`.

Part of the `universal_automation_*` family
([ADR 0037](../../docs/decisions/0037_universal_automation_family.md)).
The invariants encode production-proven discipline
(media-plane separation, SDK/product boundaries):

- pacing and single-flight at the **source**;
- per-sink isolation: a failing sink degrades alone (`SinkDegraded`);
- source failure fails the pipeline and closes every sink with the error
  — error-frame-then-close, never silence;
- slow sinks drop oldest frames instead of backpressuring the source.

## Sources

- `CdpScreencastFrameSource` — damage-driven CDP frames with
  `screencastFrameAck` flow control.
- `PollingFrameSource` — paced screenshot polling over any driver,
  single-flight by construction.

## Sinks

- `WebSocketFrameServer` — binary frames (text meta + binary payload)
  with `?token=` auth and error-frame-then-close semantics.
- `MjpegHttpSink` — multipart MJPEG any browser can render in `<img>`.
- `FileRecorderSink` — payload file + JSONL receipts (offset, revision,
  capturedAt) aligned with the `recording`/`receipts` contracts.

## Audiences

`ScreencastAudience {agent, human, recorder}` caps the pacing floor —
agents get ≤5 fps keyframes, humans and recorders get up to 30 fps —
and compositions that pair incompatible sinks with sources are rejected
at construction.

## Usage

```dart
final pipeline = await ScreencastPipeline.start(
  ScreencastComposition(
    source: PollingFrameSource(() => grabJpeg(), interval: Duration(milliseconds: 250)),
    sinks: [wsServer, FileRecorderSink(directory: '/tmp/frames')],
    audiences: [ScreencastAudience.agent, ScreencastAudience.recorder],
  ),
);
pipeline.events.listen(print);
await pipeline.stop();
```

## Non-claims

- No WebRTC transport yet — it arrives behind the same `FrameSink`
  interface in wave 3 (`universal_webrtc`), with the media plane
  separated from signaling from day one.
- Frames are not semantic snapshots; use a driver's `snapshot()` for
  structure and frames for pixels only.
