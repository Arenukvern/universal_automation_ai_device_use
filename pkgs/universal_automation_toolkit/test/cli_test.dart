// The process-level proofs in this suite spawn `dart` (native-assets
// build hooks on first run); the default 30 s budget is too tight
// for a cold build.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_automation_toolkit/src/cli/toolkit_cli.dart';
import 'package:universal_browser_cdp/universal_browser_cdp_testing.dart';

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

  test('observe prints the snapshot JSON and exits 0', () async {
    final code = await runToolkitCli(['observe', '--cdp', '$endpoint']);
    expect(code, exitOk);
  });

  test('act click exits 0 and synthesizes input at the fake', () async {
    final code = await runToolkitCli([
      'act',
      '--cdp',
      '$endpoint',
      '--click-name',
      'Submit',
    ]);
    expect(code, exitOk);
    expect(
      fake.inputEvents.map((event) => event['method']),
      contains('Input.dispatchMouseEvent'),
    );
  });

  test('act without a verb is a usage error (exit 2)', () async {
    final code = await runToolkitCli(['act', '--cdp', '$endpoint']);
    expect(code, exitUsage);
  });

  test('observe --view-* renders the observation and exits 0', () async {
    final code = await runToolkitCli([
      'observe',
      '--cdp',
      '$endpoint',
      '--view-subtree',
      's_1',
      '--view-fields',
      'role,name',
      '--view-max',
      '2',
    ]);
    expect(code, exitOk);
  });

  test('observe --view-max not-an-int is a usage error (exit 2)', () async {
    final code = await runToolkitCli([
      'observe',
      '--cdp',
      '$endpoint',
      '--view-max',
      'many',
    ]);
    expect(code, exitUsage);
  });

  test('act --return-state exits 0 and closes the loop', () async {
    final code = await runToolkitCli([
      'act',
      '--cdp',
      '$endpoint',
      '--click-name',
      'Submit',
      '--return-state',
    ]);
    expect(code, exitOk);
  });

  test('verify passes when checks hold and fails (exit 1) when not', () async {
    final ok = await runToolkitCli([
      'verify',
      '--cdp',
      '$endpoint',
      '--exists',
      'role=button,name=Submit',
    ]);
    expect(ok, exitOk);

    final fail = await runToolkitCli([
      'verify',
      '--cdp',
      '$endpoint',
      '--exists',
      'name=Missing',
    ]);
    expect(fail, exitFailure);
  });

  test('screenshot writes the PNG (exit 0)', () async {
    final out =
        '${Directory.systemTemp.path}/uat-cli-${DateTime.now().microsecondsSinceEpoch}.png';
    addTearDown(() {
      if (File(out).existsSync()) File(out).deleteSync();
    });
    final code = await runToolkitCli([
      'screenshot',
      '--cdp',
      '$endpoint',
      '--out',
      out,
    ]);
    expect(code, exitOk);
    expect(File(out).existsSync(), isTrue);
  });

  test('validate reports violations without attaching (exit 1)', () async {
    final file = File(
      '${Directory.systemTemp.path}/uat-cli-plan-${DateTime.now().microsecondsSinceEpoch}.yaml',
    );
    await file.writeAsString('''
sessions:
  browser:
    transport: webdriver
    uri: http://127.0.0.1:9515
scenarios:
  s:
    steps:
      - act: {click: {}}
''');
    addTearDown(() => file.deleteSync());

    // A bad step is a validation failure even before transport linking.
    final bad = await runToolkitCli(['validate', '--plan', file.path]);
    expect(bad, exitFailure);

    await file.writeAsString('''
sessions:
  browser:
    transport: cdp
    uri: $endpoint
scenarios:
  s:
    steps:
      - observe: null
''');
    final good = await runToolkitCli(['validate', '--plan', file.path]);
    expect(good, exitOk);
  });

  test('run executes the scenario and prints a report (exit 0)', () async {
    final file = File(
      '${Directory.systemTemp.path}/uat-cli-run-${DateTime.now().microsecondsSinceEpoch}.yaml',
    );
    await file.writeAsString('''
sessions:
  browser:
    transport: cdp
    uri: $endpoint
scenarios:
  s:
    steps:
      - navigate: {url: '$endpoint/#x'}
      - wait: {checks: [{exists: {role: button, name: Submit}}], timeout: 2}
''');
    addTearDown(() => file.deleteSync());

    final code = await runToolkitCli([
      'run',
      '--plan',
      file.path,
      '--out',
      Directory.systemTemp.path,
    ]);
    expect(code, exitOk);
  });

  test('run with a handle override resolves through --set', () async {
    final file = File(
      '${Directory.systemTemp.path}/uat-cli-set-${DateTime.now().microsecondsSinceEpoch}.yaml',
    );
    await file.writeAsString('''
sessions:
  browser:
    transport: cdp
    handle: session-browser-handle
scenarios:
  s:
    steps:
      - observe: null
''');
    addTearDown(() => file.deleteSync());

    final code = await runToolkitCli([
      'run',
      '--plan',
      file.path,
      '--set',
      'session-browser-handle=$endpoint',
    ]);
    expect(code, exitOk);
  });

  test(
    'serve --browser-handle without --handles-dir is a usage error',
    () async {
      final code = await runToolkitCli(['serve', '--browser-handle', 'moli']);
      expect(code, exitUsage);
    },
  );

  // Boots `serve` with the given flags/env in a child process and
  // returns the capabilities payload from the loopback HTTP face.
  Future<Map<String, Object?>> serveCapabilities({
    List<String> flags = const ['--os'],
    Map<String, String> env = const {},
  }) async {
    final script = File(
      '${Directory.current.path}/.dart_tool/uat_tier_probe.dart',
    );
    await script.parent.create(recursive: true);
    final flagArgs = flags.map((f) => "'$f'").join(', ');
    await script.writeAsString('''
import 'dart:io';
import 'package:universal_automation_toolkit/src/cli/toolkit_cli.dart';
Future<void> main() async {
  await runToolkitCli(['serve', '--http', '0', $flagArgs]);
}
''');
    addTearDown(() {
      if (script.existsSync()) script.deleteSync();
    });
    final process = await Process.start('/usr/bin/env', [
      'dart',
      script.path,
    ], environment: env);
    addTearDown(process.kill);
    final banner = await process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    final url = (jsonDecode(banner) as Map<String, Object?>)['url'] as String;
    final port = Uri.parse(url).port;
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.post('127.0.0.1', port, '/mcp')
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/call',
          'params': {'name': 'automation_capabilities', 'arguments': {}},
        }),
      );
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    final result =
        (jsonDecode(body) as Map<Object?, Object?>)['result']!
            as Map<Object?, Object?>;
    final block =
        (result['content']! as List<Object?>).first! as Map<Object?, Object?>;
    return jsonDecode(block['text']! as String) as Map<String, Object?>;
  }

  test('serve --os --cdp configures both tiers; the desktop default '
      'affinity-routes navigate (process-level proof)', () async {
    final payload = await serveCapabilities(
      flags: ['--os', '--cdp', '$endpoint'],
    );
    expect((payload['serve'] as Map)['defaultTransport'], 'osAccessibility');
    expect(((payload['tiers'] as Map)['cdp'] as Map)['configured'], true);
    expect((payload['routing'] as Map)['browserTierConfigured'], true);
  });

  test('env UNIVERSAL_AUTOMATION_CDP configures the browser tier without '
      'flags (the MCP-config env route, ADR 0003)', () async {
    final payload = await serveCapabilities(
      flags: ['--os'],
      env: {'UNIVERSAL_AUTOMATION_CDP': '$endpoint'},
    );
    expect(((payload['tiers'] as Map)['cdp'] as Map)['configured'], true);
    expect(((payload['tiers'] as Map)['cdp'] as Map)['endpoint'], '$endpoint');
    expect((payload['routing'] as Map)['browserTierConfigured'], true);
  });

  test('serve --handles-dir + --browser-handle resolves the published '
      'browser artifact (process-level proof)', () async {
    final handlesDir = await Directory.systemTemp.createTemp('uat-handles');
    addTearDown(() => handlesDir.delete(recursive: true));
    await File('${handlesDir.path}/moli').writeAsString('$endpoint');
    final payload = await serveCapabilities(
      flags: [
        '--os',
        '--handles-dir',
        handlesDir.path,
        '--browser-handle',
        'moli',
      ],
    );
    final handles = payload['handles'] as Map;
    expect(handles['browserHandle'], 'moli');
    expect(handles['resolvedEndpoint'], '$endpoint');
    expect((payload['routing'] as Map)['browserTierConfigured'], true);
  });
}
