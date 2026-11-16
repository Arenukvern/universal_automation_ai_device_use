# universal_webrtc

High-level WebRTC for pure Dart: signaling contracts, a peer factory over
the webrtc-rs sidecar, and a `FrameSink` that pumps screencast frames
through the WebRTC data channel. Intra-workspace `universal_screencast`
constraints are synced on each release-please train (see
[RELEASING.md](https://github.com/Arenukvern/universal_automation_ai_device_use/blob/main/RELEASING.md));
WebRTC releases that adopt a new screencast line ship in the same release
PR after `universal_screencast`.

## Requirements

`WebrtcDataChannelSink` and peer bring-up over screencast frames assume
**`universal_screencast` 0.3.3 or newer**. Hosted `pubspec.yaml` pins are
updated by the release-please constraint sync when WebRTC enters a train;
they are not edited by hand on `main`.

Cross-platform wherever cargo runs;
WebRTC from day one with the media plane separated from signaling
(media-plane discipline).

Part of the `universal_automation_*` family
([ADR 0037](../../docs/decisions/0037_universal_automation_family.md)).

> **Status: lab-proven, still under development.** Frame transfer works
> in both directions, including relay-forced TURN (env-gated
> `XS_TEST_TURN=1` against a local coturn). A physical two-network pass
> over real NATs is still pending; consider the NAT-traversal story
> unproven until then.

## What it does

- `SignalingChannel` — the control plane: `SdpOffer`/`SdpAnswer`/
  `IceCandidate` envelopes over `LoopbackSignalingChannel` (same host,
  tests) or `WebSocketSignalingChannel` (production).
- `SidecarPeerFactory` — peer bring-up with the frame-flow contract:
  frames flow in both directions (offerer ↔ answerer), reassembled by the
  sidecar; bind the sink to whichever peer produces frames.
- `WebrtcDataChannelSink` — a screencast `FrameSink`; each `push`
  becomes a `send_frame` on the data channel.
- `FrameChunkCodec` / `FrameReassembler` — the 12-byte chunk envelope
  shared with the sidecar.

## Usage

```dart
final (viewerSignals, sourceSignals) = LoopbackSignalingChannel.pair();
final viewerFactory = SidecarPeerFactory(sidecar: viewerSidecar, signaling: viewerSignals);
final sourceFactory = SidecarPeerFactory(sidecar: sourceSidecar, signaling: sourceSignals);

final viewer = await viewerFactory.createPeer('pair-1', PeerRole.offerer);
final source = await sourceFactory.createPeer('pair-1', PeerRole.answerer);

final sink = WebrtcDataChannelSink(sidecar: sourceSidecar, peerId: 'pair-1');
await pipelineStart(sinks: [sink]); // feed from ScreencastPipeline
```

The repo's own test runs two real sidecar processes through this exact
path (`test/webrtc_test.dart`) — SDP, trickle ICE, DTLS/SCTP, and three
frames, end to end.

## Non-claims

- v1 is data-channel transport; media tracks (VP8/H264 via the same
  peer connections) are the v2 roadmap.
- No embedded browser engine: Web consumers get the WebRTC path via
  `dart:js_interop` later; the signaling envelope is already
  engine-agnostic.
- Only host candidates; TURN/STUN configuration is future work.
