import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_automation_toolkit/universal_automation_toolkit.dart';
import 'package:universal_driver_macos/universal_driver_macos.dart';

import 'support/fake_ax_bridge.dart';

Future<Map<String, Object?>?> call(
  ToolkitMcpServer server,
  int id,
  String method, [
  Object? params,
]) =>
    server.handle({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    });

/// Decodes the text content payload of a tools/call result.
Map<String, Object?> payloadOf(Map<String, Object?>? response) => jsonDecode(
      (((response!['result'] as Map<String, Object?>)['content']
              as List<Object?>)
          .single as Map<String, Object?>)['text'] as String,
    ) as Map<String, Object?>;

/// The plain text content of an isError tool result (not JSON) — the
/// prose block; structured details ride as a second block (ADR 0003).
String errorTextOf(Map<String, Object?>? response) =>
    (((response!['result'] as Map<String, Object?>)['content']
                as List<Object?>)
            .first as Map<String, Object?>)['text'] as String;

void main() {
  group('SessionRegistry.attachApp (ADR 0064 anchoring)', () {
    test('pid/bundle/name anchors become ax:// URIs at the factory', () async {
      final endpoints = <Uri>[];
      final registry = SessionRegistry(
        bindings: const {},
        factories: {
          AutomationTransport.osAccessibility: (binding, endpoint, timeout) {
            endpoints.add(endpoint);
            return Future<ResolvedSession>.value(_StubSession(binding));
          },
        },
      );
      await registry.attachApp(
        AutomationTransport.osAccessibility,
        pid: 4242,
      );
      await registry.attachApp(
        AutomationTransport.osAccessibility,
        bundleId: 'com.apple.finder',
      );
      await registry.attachApp(
        AutomationTransport.osAccessibility,
        name: 'Finder',
      );
      expect(
        endpoints.map((uri) => '$uri').toList(),
        ['ax://pid/4242', 'ax://bundle/com.apple.finder', 'ax://name/Finder'],
      );
    });

    test('no anchor falls back to the focused sentinel', () async {
      final endpoints = <Uri>[];
      final registry = SessionRegistry(
        bindings: const {},
        factories: {
          AutomationTransport.osAccessibility: (binding, endpoint, timeout) {
            endpoints.add(endpoint);
            return Future<ResolvedSession>.value(_StubSession(binding));
          },
        },
      );
      await registry.attachApp(AutomationTransport.osAccessibility);
      expect('${endpoints.single}', 'oka:focused');
    });

    test('non-OS transports refuse the anchor vocabulary loudly', () {
      final registry = SessionRegistry(bindings: const {});
      expect(
        () => registry.attachApp(
          AutomationTransport.cdp,
          pid: 4242,
        ),
        throwsA(isA<DriverUnsupportedException>()),
      );
    });

    test('unknown bundle/name anchors fail at the macOS factory', () async {
      final registry = SessionRegistry(
        bindings: const {},
        factories: {
          AutomationTransport.osAccessibility:
              (binding, endpoint, timeout) async {
            final name = Uri.decodeComponent(endpoint.path.substring(1));
            throw ElementNotFoundException(
              'application',
              'name "$name" (running: )',
            );
          },
        },
      );
      await expectLater(
        registry.attachApp(
          AutomationTransport.osAccessibility,
          name: 'Not Running',
        ),
        throwsA(
          isA<ElementNotFoundException>().having(
            (error) => error.locatorValue,
            'locatorValue',
            contains('Not Running'),
          ),
        ),
      );
    });

    test('a pid anchor attaches an anchored macOS driver', () async {
      final bridge = FakeAxDriverBridge();
      final registry = SessionRegistry(
        bindings: const {},
        factories: {
          AutomationTransport.osAccessibility:
              (binding, endpoint, timeout) async {
            return _StubSession(
              binding,
              driver: BehavioralMacosDriver(
                bridge: bridge,
                targetPid: _anchorPid(endpoint),
              ),
            );
          },
        },
      );
      final session = await registry.attachApp(
        AutomationTransport.osAccessibility,
        pid: 4242,
      );
      final driver = session.driver;
      expect(driver, isA<MacosDriver>());
      expect(driver, isA<BehavioralMacosDriver>());
      expect((driver as MacosDriver).targetPid, 4242,
          reason: 'observations route to the anchored pid, not focus');
    });
  });

  group('MCP surface (ADR 0064)', () {
    test('app anchor routes observation to the anchored pid', () async {
      final bridge = FakeAxDriverBridge();
      final server = ToolkitMcpServer(
        defaultTransport: AutomationTransport.osAccessibility,
        factories: {
          AutomationTransport.osAccessibility: (binding, endpoint, timeout) =>
              Future<ResolvedSession>.value(
                _StubSession(binding, driver: BehavioralMacosDriver(
                  bridge: bridge,
                  targetPid: _anchorPid(endpoint),
                )),
              ),
        },
      );
      final response = await call(server, 1, 'tools/call', {
        'name': 'automation_observe',
        'arguments': {
          'app': {'pid': 4242},
        },
      });
      expect(response!['result'] as Map<String, Object?>, isNotNull);
      expect(payloadOf(response)['snapshot'], isNotNull);
      expect(bridge.lastSnapshotPid, 4242);
      // Anchored observation never touches the focused app's walk.
      expect(bridge.calls.contains('snapshot'), isFalse);
    });

    test('setValue flows to the bridge as a semantic write', () async {
      final bridge = FakeAxDriverBridge();
      final server = ToolkitMcpServer(
        defaultTransport: AutomationTransport.osAccessibility,
        factories: {
          AutomationTransport.osAccessibility: (binding, endpoint, timeout) =>
              Future<ResolvedSession>.value(_StubSession(
                binding,
                driver: BehavioralMacosDriver(bridge: bridge),
              )),
        },
      );
      final response = await call(server, 2, 'tools/call', {
        'name': 'automation_act',
        'arguments': {
          'action': 'setValue',
          'name': 'Search',
          'value': 'hello background',
          'returnState': true,
        },
      });
      expect(payloadOf(response)['ok'], true);
      expect(payloadOf(response)['state'], isNotNull);
      expect(bridge.setValues, [(3, 'hello background')]);
    });

    test('elementAction performs the advertised action by name', () async {
      final bridge = FakeAxDriverBridge();
      final server = ToolkitMcpServer(
        defaultTransport: AutomationTransport.osAccessibility,
        factories: {
          AutomationTransport.osAccessibility: (binding, endpoint, timeout) =>
              Future<ResolvedSession>.value(_StubSession(
                binding,
                driver: BehavioralMacosDriver(bridge: bridge),
              )),
        },
      );
      final response = await call(server, 3, 'tools/call', {
        'name': 'automation_act',
        'arguments': {
          'action': 'elementAction',
          'elementAction': 'AXConfirm',
          'name': 'Save',
        },
      });
      expect(payloadOf(response)['ok'], true);
      expect(bridge.elementActionCalls, [(2, 'AXConfirm')]);
    });

    test('focus contract: global clickAt refuses; scroll/type use pid rung; '
        'foreground opt-in activates and records the cost', () async {
      final bridge = FakeAxDriverBridge();
      // Frontmost is Safari while the anchor is Finder (pid 42).
      final server = ToolkitMcpServer(
        defaultTransport: AutomationTransport.osAccessibility,
        factories: {
          AutomationTransport.osAccessibility: (binding, endpoint, timeout) =>
              Future<ResolvedSession>.value(_StubSession(
                binding,
                driver: BehavioralMacosDriver(
                  bridge: bridge,
                  targetPid: 42,
                ),
              )),
        },
      );

      // The ADR 0064 rung: anchored typing posts straight to the
      // target's event queue — no refusal, no activation.
      final typed = await call(server, 4, 'tools/call', {
        'name': 'automation_act',
        'arguments': {
          'action': 'type',
          'text': 'yes',
          'app': {'pid': 42},
        },
      });
      expect(payloadOf(typed)['ok'], true);
      expect(
        bridge.pidTypedText.single,
        (pid: 42, text: 'yes'),
      );
      expect(bridge.lastActivatedPid, isNull);

      // Anchored scroll posts to the pid (ADR 0008 / 0066), no activation.
      final scrolled = await call(server, 6, 'tools/call', {
        'name': 'automation_act',
        'arguments': {
          'action': 'scroll',
          'direction': 'down',
          'app': {'pid': 42},
        },
      });
      expect(payloadOf(scrolled)['ok'], true);
      expect(bridge.scrollToPidCalls, isNotEmpty);
      expect(bridge.lastActivatedPid, isNull);

      // Global clickAt still uses the HID stream: refuse on background anchor.
      final refused = await call(server, 7, 'tools/call', {
        'name': 'automation_act',
        'arguments': {
          'action': 'clickAt',
          'x': 10,
          'y': 20,
          'app': {'pid': 42},
        },
      });
      expect(
        (refused!['result'] as Map<String, Object?>)['isError'],
        true,
      );
      expect(errorTextOf(refused), contains('foregroundRequired'));

      // Opt-in: activate the anchor, retry once, record the rung.
      final activated = await call(server, 5, 'tools/call', {
        'name': 'automation_act',
        'arguments': {
          'action': 'clickAt',
          'x': 10,
          'y': 20,
          'app': {'pid': 42},
          'foreground': true,
        },
      });
      expect(payloadOf(activated)['ok'], true);
      expect(payloadOf(activated)['focusContract'], 'activated');
      expect(bridge.lastActivatedPid, 42);
    });

    test('automation_list_apps enumerates the anchorable record',
        () async {
      final bridge = FakeAxDriverBridge();
      final server = ToolkitMcpServer(
        defaultTransport: AutomationTransport.osAccessibility,
        factories: {
          AutomationTransport.osAccessibility: (binding, endpoint, timeout) =>
              Future<ResolvedSession>.value(_StubSession(
                binding,
                driver: BehavioralMacosDriver(bridge: bridge),
              )),
        },
      );
      final response = await call(server, 6, 'tools/call', {
        'name': 'automation_list_apps',
        'arguments': {},
      });
      final payload = payloadOf(response);
      final apps = payload['apps']! as List<Object?>;
      expect(apps, hasLength(2));
      expect(
        (apps.first as Map<String, Object?>)['bundleId'],
        'com.apple.finder',
      );
    });
  });

  group('resident job plane (ADR 0064)', () {
    late Directory jobsDir;

    setUp(() {
      jobsDir = Directory.systemTemp.createTempSync('uat-jobs-test-');
    });
    tearDown(() {
      jobsDir.deleteSync(recursive: true);
    });

    test('submit-and-detach: a failing plan lands a durable receipt',
        () async {
      final plan = File('${jobsDir.parent.path}/unreachable-plan.yaml')
        ..writeAsStringSync('''
sessions:
  browser:
    transport: cdp
    uri: http://127.0.0.1:1
scenarios:
  main:
    steps:
      - observe: {}
''');
      final queue = JobQueue(directory: jobsDir.path);
      final job = queue.submit(planPath: plan.path);
      expect(job.status, 'queued', reason: 'submit returns immediately');

      // Poll to the terminal state (the queue drains asynchronously).
      BackgroundJob? current;
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(deadline)) {
        current = queue.status(job.id);
        if (current!.status == 'succeeded' || current.status == 'failed') {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(current!.status, 'failed');
      expect(current.report?['ok'], false,
          reason: 'the step failure rides the run report');
      expect(current.report?['steps'], isNotNull);

      // The receipt is on disk and re-readable (survives restarts).
      final records = jobsDir.listSync().whereType<File>().toList();
      expect(records, hasLength(1));
      final restored = BackgroundJob.fromJson(
        jsonDecode(records.single.readAsStringSync()) as Map<String, Object?>,
      );
      expect(restored.status, 'failed');
    });

    test('a passing plan lands the full run report in the receipt',
        () async {
      final bridge = FakeAxDriverBridge();
      final plan = File('${jobsDir.parent.path}/anchor-plan.yaml')
        ..writeAsStringSync('''
sessions:
  finder:
    transport: osAccessibility
    uri: ax://pid/4242
scenarios:
  main:
    steps:
      - observe: {save: snap}
''');
      final queue = JobQueue(
        directory: jobsDir.path,
        factories: {
          AutomationTransport.osAccessibility: (binding, endpoint, timeout) =>
              Future<ResolvedSession>.value(_StubSession(
                binding,
                driver: BehavioralMacosDriver(
                  bridge: bridge,
                  targetPid: _anchorPid(endpoint),
                ),
              )),
        },
      );
      final job = queue.submit(planPath: plan.path);
      BackgroundJob? current;
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(deadline)) {
        current = queue.status(job.id);
        if (current!.status == 'succeeded' || current.status == 'failed') {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(current!.status, 'succeeded');
      expect(current.report?['ok'], true);
      expect(bridge.lastSnapshotPid, 4242,
          reason: 'the plan session anchored by uri drives the anchored pid');
    });
  });
}

/// Resolves the `ax://pid/<n>` host of an anchored endpoint in tests.
int? _anchorPid(Uri endpoint) =>
    endpoint.scheme == 'ax' ? int.tryParse(endpoint.path.substring(1)) : null;

/// A resolved session over an optional fake driver.
final class _StubSession implements ResolvedSession {
  _StubSession(this.binding, {AutomationDriver? driver})
    : driver = driver ?? _NullDriver();

  @override
  final SessionBinding binding;

  @override
  final AutomationDriver driver;

  @override
  Uri? get url => null;

  @override
  BehavioralDriver? asBehavioral() =>
      driver is BehavioralDriver ? driver as BehavioralDriver : null;

  @override
  Future<void> detach() async {}
}

final class _NullDriver implements AutomationDriver {
  @override
  DriverCapabilities get capabilities => const DriverCapabilities();

  @override
  Future<Snapshot> snapshot() async => Snapshot(
    roots: [
      const AxNode(role: 'application', name: 'stub'),
    ],
    capturedAt: DateTime.now().toUtc(),
    revision: 1,
  );

  @override
  Future<void> perform(AutomationAction action) async {}

  @override
  Future<Uint8List> screenshot() async => Uint8List(0);

  @override
  Future<void> close() async {}
}
