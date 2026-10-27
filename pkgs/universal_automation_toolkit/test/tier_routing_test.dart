import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_automation_toolkit/universal_automation_toolkit.dart';
import 'package:universal_browser_cdp/universal_browser_cdp_testing.dart';

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

Map<String, Object?> payloadOf(Map<String, Object?>? response) => jsonDecode(
      (((response!['result'] as Map<String, Object?>)['content']
                  as List<Object?>)
              .first as Map<String, Object?>)['text'] as String,
    ) as Map<String, Object?>;

List<Object?> contentOf(Map<String, Object?>? response) =>
    (response!['result'] as Map<String, Object?>)['content'] as List<Object?>;

/// Records performed actions; refuses evaluate the way the real macOS
/// driver does (with a remedy, ADR 0003).
final class _RecordingOsDriver implements AutomationDriver {
  final actions = <AutomationAction>[];

  @override
  DriverCapabilities get capabilities => const DriverCapabilities(
    a11yTree: true,
    navigate: true,
  );

  @override
  Future<Snapshot> snapshot() async => Snapshot(
    roots: [const AxNode(role: 'application', name: 'stub')],
    capturedAt: DateTime.now().toUtc(),
    revision: 1,
  );

  @override
  Future<void> perform(AutomationAction action) async {
    if (action is EvaluateAction) {
      throw const DriverUnsupportedException(
        'AX cannot evaluate expressions; evaluation is an '
        'instrumented-tier capability',
        details: {
          'remedy': 'configure a browser tier and re-send with '
              'transport "cdp"',
        },
      );
    }
    actions.add(action);
  }

  @override
  Future<Uint8List> screenshot({int maxPx = 0}) async => Uint8List(0);

  @override
  Future<void> close() async {}
}

void main() {
  late FakeCdpServer fake;
  late Uri cdpEndpoint;

  setUp(() async {
    fake = FakeCdpServer();
    cdpEndpoint = await fake.start();
  });
  tearDown(() => fake.stop());

  ToolkitMcpServer osDefaultServer({
    Map<AutomationTransport, Uri> endpoints = const {},
    String? handlesDirectory,
    String? browserHandle,
  }) => ToolkitMcpServer(
    endpoints: endpoints,
    defaultTransport: AutomationTransport.osAccessibility,
    handlesDirectory: handlesDirectory,
    browserHandle: browserHandle,
    factories: {
      AutomationTransport.osAccessibility: (binding, endpoint, timeout) =>
          Future<ResolvedSession>.value(_OsStubSession(binding)),
    },
  );

  test('automation_capabilities reports tiers, probe, routing, schemes',
      () async {
    final server = osDefaultServer(endpoints: {AutomationTransport.cdp: cdpEndpoint});
    final payload = payloadOf(
      await call(server, 1, 'tools/call', {
        'name': 'automation_capabilities',
        'arguments': {},
      }),
    );
    final serve = payload['serve'] as Map<String, Object?>;
    expect(serve['defaultTransport'], 'osAccessibility');
    expect(serve['platform'], Platform.operatingSystem);
    final tiers = payload['tiers'] as Map<String, Object?>;
    final cdp = tiers['cdp'] as Map<String, Object?>;
    expect(cdp['configured'], true);
    expect(cdp['endpoint'], '$cdpEndpoint');
    final probe = cdp['probe'] as Map<String, Object?>;
    expect(probe['reachable'], true);
    expect(probe['browser'], isNotNull);
    expect((tiers['osAccessibility'] as Map<String, Object?>)['endpointFree'],
        true);
    final routing = payload['routing'] as Map<String, Object?>;
    expect(routing['browserTierConfigured'], true);
    expect(
      (routing['instrumentedAffinityVerbs'] as List<Object?>).toSet(),
      {'navigate', 'evaluate', 'invoke'},
    );
    expect(
      ((payload['openUrl'] as Map<String, Object?>)['schemes'] as List)
          .contains('https'),
      true,
    );
  });

  test('unconfigured tiers report configured:false; probe failure is a '
      'fact, not an error', () async {
    final server = osDefaultServer(
      endpoints: {
        AutomationTransport.cdp: Uri.parse('http://127.0.0.1:1'),
      },
    );
    final payload = payloadOf(
      await call(server, 1, 'tools/call', {
        'name': 'automation_capabilities',
        'arguments': {},
      }),
    );
    final tiers = payload['tiers'] as Map<String, Object?>;
    expect((tiers['webdriver'] as Map<String, Object?>)['configured'], false);
    final probe =
        (tiers['cdp'] as Map<String, Object?>)['probe'] as Map<String, Object?>;
    expect(probe['reachable'], false);
  });

  test('navigate on a desktop-default server affinity-routes to the '
      'configured browser tier and reports it', () async {
    final server = osDefaultServer(
      endpoints: {AutomationTransport.cdp: cdpEndpoint},
    );
    final payload = payloadOf(
      await call(server, 2, 'tools/call', {
        'name': 'automation_act',
        'arguments': {
          'action': 'navigate',
          'url': 'https://example.test/network',
        },
      }),
    );
    expect(payload['ok'], true);
    final routedTo = payload['routedTo'] as Map<String, Object?>;
    expect(routedTo['transport'], 'cdp');
    expect(routedTo['endpoint'], '$cdpEndpoint');
  });

  test('navigate resolves a published browser handle (oka artifact, '
      'ADR 0003) when no --cdp endpoint exists', () async {
    final handlesDir = await Directory.systemTemp.createTemp('uatk-handles');
    addTearDown(() => handlesDir.delete(recursive: true));
    await File('${handlesDir.path}/moli')
        .writeAsString('$cdpEndpoint');
    final server = osDefaultServer(
      handlesDirectory: handlesDir.path,
      browserHandle: 'moli',
    );
    final payload = payloadOf(
      await call(server, 3, 'tools/call', {
        'name': 'automation_act',
        'arguments': {
          'action': 'navigate',
          'url': 'https://example.test/via-handle',
        },
      }),
    );
    expect(payload['ok'], true);
    final routedTo = payload['routedTo'] as Map<String, Object?>;
    expect(routedTo['transport'], 'cdp');
    expect(routedTo['endpoint'], '$cdpEndpoint');
  });

  test('explicit transport wins over affinity routing; desktop navigate '
      'lands the system-browser receipt', () async {
    final server = osDefaultServer(
      endpoints: {AutomationTransport.cdp: cdpEndpoint},
    );
    final payload = payloadOf(
      await call(server, 4, 'tools/call', {
        'name': 'automation_act',
        'arguments': {
          'action': 'navigate',
          'url': 'https://example.test/desktop',
          'transport': 'osAccessibility',
        },
      }),
    );
    expect(payload['ok'], true);
    expect(payload.containsKey('routedTo'), false);
    final receipt = payload['navigate'] as Map<String, Object?>;
    expect(receipt['surface'], 'systemBrowser');
    expect(receipt['drivable'], false);
  });

  test('evaluate on the desktop tier with no browser refuses with a '
      'structured remedy across the MCP boundary', () async {
    final server = osDefaultServer();
    final response = await call(server, 5, 'tools/call', {
      'name': 'automation_act',
      'arguments': {'action': 'evaluate', 'expression': '1 + 1'},
    });
    expect((response!['result'] as Map<String, Object?>)['isError'], true);
    final content = contentOf(response);
    expect((content.first as Map)['text'], contains('driverUnsupported'));
    // The structured block: kind + remedy survive the boundary.
    final details =
        jsonDecode((content[1] as Map)['text'] as String)
            as Map<String, Object?>;
    expect(details['kind'], 'driverUnsupported');
    expect(
      '$details',
      contains('configure a browser tier'),
    );
  });
}

final class _OsStubSession implements ResolvedSession {
  _OsStubSession(this.binding);

  @override
  final SessionBinding binding;

  @override
  final _RecordingOsDriver driver = _RecordingOsDriver();

  @override
  Uri? get url => null;

  @override
  BehavioralDriver? asBehavioral() => null;

  @override
  Future<void> detach() async {}
}
