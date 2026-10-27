import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_automation_toolkit/universal_automation_toolkit.dart';
import 'package:universal_browser_cdp/universal_browser_cdp_testing.dart';
import 'package:universal_driver_macos/universal_driver_macos.dart';

import '../../universal_driver_macos/test/macos_driver_test.dart' show FakeBridge;

Future<Map<String, Object?>?> call(
  ToolkitMcpServer server,
  int id,
  String method, [
  Object? params,
]) => server.handle({
  'jsonrpc': '2.0',
  'id': id,
  'method': method,
  if (params != null) 'params': params,
});

/// Decodes the text content payload of a tools/call result.
Map<String, Object?> payloadOf(Map<String, Object?>? response) => jsonDecode(
  (((response!['result'] as Map<String, Object?>)['content'] as List<Object?>)
              .single
          as Map<String, Object?>)['text']
      as String,
) as Map<String, Object?>;

void main() {
  late FakeCdpServer fake;
  late Uri endpoint;

  setUp(() async {
    fake = FakeCdpServer();
    // Semantic clicks resolve through the AX path: give the canned
    // nodes backend ids the way real CDP reports them.
    fake.axNodes = [
      {
        'nodeId': '1',
        'role': {'value': 'root'},
        'name': {'value': 'document'},
        'bounds': {'x': 0, 'y': 0, 'width': 800, 'height': 600},
        'childIds': ['2', '4'],
      },
      {
        'nodeId': '2',
        'role': {'value': 'button'},
        'name': {'value': 'Submit'},
        'backendDOMNodeId': 42,
        'bounds': {'x': 40, 'y': 60, 'width': 200, 'height': 80},
      },
      {
        'nodeId': '4',
        'role': {'value': 'textbox'},
        'name': {'value': 'Email'},
        'backendDOMNodeId': 43,
        'value': {'value': ''},
        'childIds': ['5'],
      },
      {
        'nodeId': '5',
        'role': {'value': 'generic'},
        'name': {'value': 'hint'},
      },
    ];
    endpoint = await fake.start();
  });
  tearDown(() => fake.stop());

  test('initialize negotiates a supported protocol version', () async {
    final server = ToolkitMcpServer();
    final response = await call(server, 1, 'initialize', {
      'protocolVersion': '2025-03-26',
      'capabilities': {},
      'clientInfo': {'name': 'test', 'version': '0'},
    });
    final result = response!['result'] as Map<String, Object?>;
    expect(result['protocolVersion'], '2025-03-26');
    expect(
      (result['serverInfo'] as Map<String, Object?>)['name'],
      'universal-automation-toolkit',
    );
    expect(
      (result['serverInfo'] as Map<String, Object?>)['instructions'],
      isNull,
    );
    expect(result['instructions'], contains('list-changed'));
    final capabilities = result['capabilities'] as Map<String, Object?>;
    for (final kind in ['tools', 'resources', 'prompts']) {
      expect(
        (capabilities[kind] as Map<String, Object?>)['listChanged'],
        isTrue,
      );
    }
  });

  test('tools/list advertises the toolkit surface', () async {
    final server = ToolkitMcpServer();
    final response = await call(server, 2, 'tools/list');
    final result = response!['result'] as Map<String, Object?>;
    final names = [
      for (final tool in result['tools'] as List<Object?>)
        (tool as Map<String, Object?>)['name'],
    ];
    expect(
      names,
      containsAll([
        'automation_observe',
        'automation_act',
        'automation_verify',
        'automation_screenshot',
        'automation_preview',
        'automation_computer',
        'automation_validate_plan',
        'automation_run_plan',
      ]),
    );
  });

  test('notifications get no response; unknown methods get -32601', () async {
    final server = ToolkitMcpServer();
    expect(
      await server.handle({
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      }),
      isNull,
    );
    expect(
      [for (final notice in server.takeOutbound()) notice['method']],
      [
        'notifications/tools/list_changed',
        'notifications/resources/list_changed',
        'notifications/prompts/list_changed',
      ],
    );
    final error = await call(server, 3, 'no/such/method');
    expect((error!['error'] as Map<String, Object?>)['code'], -32601);
  });

  test('automation_observe drives the default endpoint', () async {
    fake.axNodes = [
      {
        'nodeId': '1',
        'role': {'value': 'button'},
        'name': {'value': 'Buy'},
      },
    ];
    final server = ToolkitMcpServer(defaultEndpoint: endpoint);
    final response = await call(server, 4, 'tools/call', {
      'name': 'automation_observe',
      'arguments': {},
    });
    final result = response!['result'] as Map<String, Object?>;
    expect(result['isError'], isFalse);
    expect(payloadOf(response)['snapshot'], isNotNull);
  });

  test('automation_act clicks through the driver and reports ok', () async {
    final server = ToolkitMcpServer(defaultEndpoint: endpoint);
    final response = await call(server, 5, 'tools/call', {
      'name': 'automation_act',
      'arguments': {'action': 'click', 'name': 'Submit'},
    });
    expect(payloadOf(response), {'ok': true, 'action': 'click'});
    expect(
      fake.inputEvents.map((event) => event['method']),
      contains('Input.dispatchMouseEvent'),
    );
  });

  test('automation_act with humanPrior reports the behavior outcome', () async {
    final server = ToolkitMcpServer(defaultEndpoint: endpoint);
    final response = await call(server, 6, 'tools/call', {
      'name': 'automation_act',
      'arguments': {
        'action': 'click',
        'name': 'Submit',
        'profile': 'humanPrior',
        'seed': 11,
      },
    });
    final payload = payloadOf(response);
    expect(
      (payload['behavior'] as Map<String, Object?>)['verdict'],
      'complete',
    );
  });

  test('automation_verify returns structured failures', () async {
    final server = ToolkitMcpServer(defaultEndpoint: endpoint);
    final response = await call(server, 7, 'tools/call', {
      'name': 'automation_verify',
      'arguments': {
        'checks': [
          {
            'exists': {'role': 'button', 'name': 'Submit'},
          },
          {
            'exists': {'name': 'NoSuchThing'},
          },
        ],
      },
    });
    final payload = payloadOf(response);
    expect(payload['ok'], isFalse);
    expect(payload['failures'], hasLength(1));
  });

  test('unknown tool surfaces as isError', () async {
    final server = ToolkitMcpServer();
    final response = await call(server, 8, 'tools/call', {
      'name': 'nope',
      'arguments': {},
    });
    expect((response!['result'] as Map<String, Object?>)['isError'], isTrue);
  });

  test('automation_run_plan runs a document end-to-end', () async {
    final dir = Directory.systemTemp.createTempSync('uat-mcp-plan');
    addTearDown(() => dir.deleteSync(recursive: true));
    final plan = File('${dir.path}/plan.yaml');
    await plan.writeAsString('''
sessions:
  browser:
    transport: cdp
    uri: $endpoint
scenarios:
  s:
    steps:
      - observe: null
''');
    final server = ToolkitMcpServer();
    final response = await call(server, 9, 'tools/call', {
      'name': 'automation_run_plan',
      'arguments': {'plan': plan.path, 'scenario': 's'},
    });
    final payload = payloadOf(response);
    expect(payload['ok'], isTrue);
    expect(payload['scenario'], 's');
  });

  test('stdio loop answers newline-delimited requests', () async {
    final script = File(
      '${Directory.current.path}/.dart_tool/uat_stdio_probe.dart',
    );
    await script.parent.create(recursive: true);
    await script.writeAsString('''
import 'dart:io';
import 'package:universal_automation_toolkit/src/mcp/mcp_server.dart';
Future<void> main() async {
  await serveMcpStdio(defaultEndpoint: Uri.parse('$endpoint'));
}
''');
    addTearDown(() {
      if (script.existsSync()) script.deleteSync();
    });

    // Plain `dart <script>` exec through env: under `flutter test` the
    // resolved executable is flutter_tester (not a dart VM), so resolve
    // the real VM from PATH. No `dart run` pub machinery: fast and
    // stable under parallel load.
    final process = await Process.start('/usr/bin/env', ['dart', script.path]);
    final output = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': '2024-11-05'},
      }),
    );
    await process.stdin.flush();
    // Cold JIT start can take several seconds; await the first JSON-RPC
    // line (skipping any launcher banner lines) rather than a fixed
    // delay.
    Map<String, Object?>? response;
    await for (final line in output) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('{')) continue;
      response = jsonDecode(trimmed) as Map<String, Object?>;
      break;
    }
    process.stdin.close();
    process.kill();

    expect(response, isNotNull);
    final json = response!;
    expect(json['id'], 1);
    expect(
      (json['result'] as Map<String, Object?>)['protocolVersion'],
      '2024-11-05',
    );
  }, timeout: Timeout(Duration(minutes: 3)));

  test(
    'desktop tier: osAccessibility default observes the focused app',
    () async {
      final server = ToolkitMcpServer(
        defaultTransport: AutomationTransport.osAccessibility,
        factories: {
          AutomationTransport.osAccessibility:
              (binding, endpoint, timeout) async {
                expect(endpoint, Uri.parse('oka:focused'));
                return _FakeOsResolvedSession(binding);
              },
        },
      );
      final response = await call(server, 10, 'tools/call', {
        'name': 'automation_observe',
        'arguments': {},
      });
      expect((response!['result'] as Map<String, Object?>)['isError'], isFalse);
      final payload = payloadOf(response);
      expect(payload['transport'], 'osAccessibility');
      expect(payload['endpoint'], 'oka:focused');
      final snapshot = payload['snapshot'] as Map<String, Object?>;
      expect(jsonEncode(snapshot), contains('Focused Fake'));
    },
  );

  test(
    'observe view renders; diff closes the loop; returnState on act',
    () async {
      final server = ToolkitMcpServer(defaultEndpoint: endpoint);
      final viewed = await call(server, 20, 'tools/call', {
        'name': 'automation_observe',
        'arguments': {
          'view': {'maxNodes': 2},
        },
      });
      final viewPayload = payloadOf(viewed!)['view'] as Map<String, Object?>;
      expect(viewPayload['render'], contains('# observation'));
      expect(viewPayload['refs'], contains('s_0'));

      final diffed = await call(server, 21, 'tools/call', {
        'name': 'automation_observe',
        'arguments': {
          'view': {'maxNodes': 2},
          'diff': true,
        },
      });
      expect(payloadOf(diffed!)['delta'], '# no change');

      final acted = await call(server, 22, 'tools/call', {
        'name': 'automation_act',
        'arguments': {'action': 'click', 'name': 'Submit', 'returnState': true},
      });
      expect(
        (payloadOf(acted!)['state'] as String),
        contains('button "Submit"'),
      );
    },
  );

  test('per-call transport override switches tiers; unknown refuses', () async {
    final server = ToolkitMcpServer(
      factories: {
        AutomationTransport.osAccessibility:
            (binding, endpoint, timeout) async {
              return _FakeOsResolvedSession(binding);
            },
      },
    );
    final os = await call(server, 11, 'tools/call', {
      'name': 'automation_observe',
      'arguments': {'transport': 'osAccessibility'},
    });
    expect(payloadOf(os!)['transport'], 'osAccessibility');

    // No endpoint anywhere and no os transport: loud, not silent CDP.
    final missing = await call(server, 12, 'tools/call', {
      'name': 'automation_observe',
      'arguments': {},
    });
    expect((missing!['result'] as Map<String, Object?>)['isError'], isTrue);

    final unknown = await call(server, 13, 'tools/call', {
      'name': 'automation_observe',
      'arguments': {'transport': 'telepathy'},
    });
    expect(
      (((unknown!['result'] as Map<String, Object?>)['content'] as List).single
          as Map<String, Object?>)['text'],
      contains('unknown transport'),
    );
  });

  test(
    'screenshot image blocks are opt-in; windowId refuses off-tier',
    () async {
      final server = ToolkitMcpServer(
        factories: {
          AutomationTransport.osAccessibility:
              (binding, endpoint, timeout) async {
                return _FakeOsResolvedSession(binding);
              },
        },
      );
      final dir = await Directory.systemTemp.createTemp('uat-shot');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/shot.png';

      // Default: file only, no image content.
      final plain = await call(server, 31, 'tools/call', {
        'name': 'automation_screenshot',
        'arguments': {'transport': 'osAccessibility', 'path': path},
      });
      final plainResult = plain!['result'] as Map<String, Object?>;
      expect(plainResult['content'], hasLength(1));
      expect(payloadOf(plain)['bytes'], 3);

      // image: true appends an image content block; the reserved key
      // never reaches the JSON text.
      final withImage = await call(server, 32, 'tools/call', {
        'name': 'automation_screenshot',
        'arguments': {
          'transport': 'osAccessibility',
          'path': path,
          'image': true,
        },
      });
      final content =
          (withImage!['result'] as Map<String, Object?>)['content']
              as List<Object?>;
      expect(content, hasLength(2));
      final image = content[1] as Map<String, Object?>;
      expect(image['type'], 'image');
      expect(image['mimeType'], 'image/png');
      expect(image['data'], base64Encode([1, 2, 3]));
      expect(
        (content.first as Map<String, Object?>)['text'],
        isNot(contains('_imageContent')),
      );

      // windowId on a browser-tier driver refuses loudly.
      final cdpServer = ToolkitMcpServer(defaultEndpoint: endpoint);
      final windowed = await call(cdpServer, 33, 'tools/call', {
        'name': 'automation_screenshot',
        'arguments': {
          'path': path,
          'windowId': 7,
        },
      });
      expect(
        ((windowed!['result'] as Map<String, Object?>)['content'] as List)
            .single,
        isA<Map<String, Object?>>().having(
          (block) => block['text'],
          'text',
          contains('windowId needs the OS tier'),
        ),
      );

      final osWindowed = await call(server, 34, 'tools/call', {
        'name': 'automation_screenshot',
        'arguments': {
          'transport': 'osAccessibility',
          'path': path,
          'windowId': 99,
        },
      });
      expect(payloadOf(osWindowed)['bytes'], 2);
    },
  );

  test('automation_computer bind returns scale metadata', () async {
    final bridge = FakeBridge();
    bridge.windowScreenshotResult = (
      code: 0,
      bytes: Uint8List.fromList(_onePixelPng),
    );
    final server = ToolkitMcpServer(
      defaultTransport: AutomationTransport.osAccessibility,
      factories: {
        AutomationTransport.osAccessibility:
            (binding, endpoint, timeout) async =>
                _MacosResolvedSession(binding, bridge: bridge),
      },
    );
    final response = await call(server, 41, 'tools/call', {
      'name': 'automation_computer',
      'arguments': {
        'transport': 'osAccessibility',
        'action': 'bind',
        'app': {'pid': 42},
        'windowId': 77,
      },
    });
    final payload = payloadOf(response);
    expect(payload['bound'], isTrue);
    expect(payload['scale'], isA<num>());
    expect(payload['width'], 1);
  });

  test('automation_preview frame returns window bytes on OS tier', () async {
    final server = ToolkitMcpServer(
      defaultTransport: AutomationTransport.osAccessibility,
      factories: {
        AutomationTransport.osAccessibility:
            (binding, endpoint, timeout) async =>
                _FakeOsResolvedSession(binding),
      },
    );
    final response = await call(server, 40, 'tools/call', {
      'name': 'automation_preview',
      'arguments': {
        'transport': 'osAccessibility',
        'op': 'frame',
        'windowId': 99,
        'maxPx': 320,
      },
    });
    final payload = payloadOf(response);
    expect(payload['ok'], isTrue);
    expect(payload['bytes'], 2);
    expect(payload['windowId'], 99);
  });
}

final class _FakeOsResolvedSession implements ResolvedSession {
  _FakeOsResolvedSession(this.binding);

  @override
  final SessionBinding binding;

  @override
  AutomationDriver get driver => _FakeOsDriver();

  @override
  Uri? get url => null;

  @override
  BehavioralDriver? asBehavioral() => null;

  @override
  Future<void> detach() async {}
}

/// Minimal 1×1 PNG for window capture dimension tests.
final _onePixelPng = Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49,
  0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
  0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44,
  0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0d,
  0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42,
  0x60, 0x82,
]);

final class _MacosResolvedSession implements ResolvedSession {
  _MacosResolvedSession(this.binding, {required FakeBridge bridge})
    : driver = MacosDriver(bridge: bridge, targetPid: 42);

  @override
  final SessionBinding binding;

  @override
  final AutomationDriver driver;

  @override
  Uri? get url => null;

  @override
  BehavioralDriver? asBehavioral() => null;

  @override
  Future<void> detach() async {}
}

final class _FakeOsDriver implements AutomationDriver, OsWindowCapture {
  @override
  DriverCapabilities get capabilities => const DriverCapabilities(
    screenshot: true,
    a11yTree: true,
    inputSynthesis: true,
  );

  @override
  Future<Snapshot> snapshot() async => Snapshot(
    roots: const [AxNode(role: 'window', name: 'Focused Fake')],
    capturedAt: DateTime.now().toUtc(),
    revision: 1,
  );

  @override
  Future<void> perform(AutomationAction action) async {}

  @override
  Future<Uint8List> screenshot() async => Uint8List.fromList([1, 2, 3]);

  @override
  Future<List<OsWindowRecord>> windows({int pid = 0}) async => [
    MacosWindow(windowId: 99, pid: pid, name: 'Fake'),
  ];

  @override
  Future<Uint8List> windowScreenshot(int windowId, {int? maxPx}) async =>
      Uint8List.fromList([windowId, maxPx ?? 0]);

  @override
  Future<void> close() async {}
}
