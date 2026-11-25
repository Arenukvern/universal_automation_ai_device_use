# universal_automation_conformance

Conformance suites proving `AutomationDriver`, `FrameSource`, and
`FrameSink` implementations are swappable. Adoption is one call, exactly
like `universal_storage_conformance`.

**Breaking from 0.3.x:** depends on `universal_automation_interface` `^0.4.0`
(interface 0.4 `AutomationDriver` / frame types in the suite APIs) and
`universal_screencast` `^0.3.0`.

Intra-workspace `universal_screencast` constraints are synced on each
dart_changesets version PR (see
[RELEASING.md](https://github.com/Arenukvern/universal_automation_ai_device_use/blob/main/RELEASING.md));
conformance releases that adopt a new screencast line ship in the same
release PR after `universal_screencast`.

## Requirements

Frame source/sink conformance suites that exercise screencast types assume
**`universal_screencast` 0.3.3 or newer** (aligned with the CDP 0.6.3
release train). Hosted `pubspec.yaml` pins are updated by the
dart_changesets version step when conformance enters a train; they are
not edited by hand on `main`.

```dart
void main() {
  automationDriverConformanceTests(
    'CdpDriver over FakeCdpServer',
    createDriver: () async {
      final server = FakeCdpServer();
      final base = await server.start();
      final session = await CdpBrowserSession.attach(base);
      return session.driver;
    },
  );

  frameSourceConformanceTests(
    'PollingFrameSource',
    createSource: () async => PollingFrameSource(grab),
  );

  frameSinkConformanceTests(
    'WebSocketFrameServer',
    createSink: () async {
      final sink = WebSocketFrameServer();
      await sink.start();
      return sink;
    },
  );
}
```

A backend that does not pass its suite is not swappable; fix the backend
before shipping an adapter.

## Non-claims

- The suites exercise contracts, not protocol conformance: CDP wire
  semantics are covered by `universal_browser_cdp`'s own tests.
