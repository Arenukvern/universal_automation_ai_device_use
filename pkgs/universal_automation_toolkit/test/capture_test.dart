// The capture surface: the options an agent asks for, the target
// selector that picks a browser tab, and the tier refusals that keep a
// downgrade from being silent.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_automation_toolkit/src/capture/capture_request.dart';
import 'package:universal_automation_toolkit/src/cli/toolkit_cli.dart';
import 'package:universal_browser_cdp/universal_browser_cdp_testing.dart';

/// A driver that serves the plain frame but honors no options.
final class _PlainDriver implements AutomationDriver {
  @override
  DriverCapabilities get capabilities =>
      const DriverCapabilities(screenshot: true);

  @override
  Future<Snapshot> snapshot() async => Snapshot(
    roots: const [AxNode(role: 'root')],
    capturedAt: DateTime.now().toUtc(),
    revision: 1,
  );

  @override
  Future<void> perform(AutomationAction action) async {}

  @override
  Future<Uint8List> screenshot() async => Uint8List.fromList([1, 2, 3]);

  @override
  Future<void> close() async {}
}

/// A driver that honors the options it is given.
final class _ConfigurableDriver extends _PlainDriver
    implements ConfigurableCapture {
  final List<CaptureOptions> requests = [];

  @override
  Future<Uint8List> capture(CaptureOptions options) async {
    requests.add(options);
    return Uint8List.fromList([4, 5, 6]);
  }
}

void main() {
  group('CaptureRequest', () {
    test('the plain request asks for nothing extra', () {
      final request = CaptureRequest.fromArguments(const {});
      expect(request.isPlain, isTrue);
      expect(request.options.fullPage, isFalse);
      expect(request.options.maxPx, isNull);
      expect(request.options.format, CaptureFormat.png);
    });

    test('reads the options an agent asked for', () {
      final request = CaptureRequest.fromArguments(const {
        'fullPage': true,
        'maxPx': 1024,
        'format': 'jpeg',
        'quality': 80,
      });
      expect(request.isPlain, isFalse);
      expect(request.options.fullPage, isTrue);
      expect(request.options.maxPx, 1024);
      expect(request.options.format, CaptureFormat.jpeg);
      expect(request.options.quality, 80);
    });

    test('a zero cap means no cap', () {
      final request = CaptureRequest.fromArguments(const {'maxPx': 0});
      expect(request.options.maxPx, isNull);
      expect(request.isPlain, isTrue);
    });

    test('a nonsense cap is refused', () {
      expect(
        () => CaptureRequest.fromArguments(const {'maxPx': -5}),
        throwsA(isA<FormatException>()),
      );
    });

    test('a nonsense encoding is refused', () {
      expect(
        () => CaptureRequest.fromArguments(const {'format': 'webp'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('the plain frame comes from the base contract', () async {
      final driver = _PlainDriver();
      final bytes = await CaptureRequest.fromArguments(const {})
          .capture(driver);
      expect(bytes, [1, 2, 3]);
    });

    test('a driver that honors options receives them unchanged', () async {
      final driver = _ConfigurableDriver();
      final request = CaptureRequest.fromArguments(const {
        'fullPage': true,
        'maxPx': 512,
      });
      final bytes = await request.capture(driver);
      expect(bytes, [4, 5, 6]);
      expect(driver.requests.single.fullPage, isTrue);
      expect(driver.requests.single.maxPx, 512);
    });

    test('a driver that cannot honor options refuses rather than '
        'downgrading', () async {
      final driver = _PlainDriver();
      await expectLater(
        CaptureRequest.fromArguments(const {'maxPx': 512}).capture(driver),
        throwsA(
          isA<DriverUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('cannot honor the requested capture options'),
          ),
        ),
      );
    });

    test(
      'a driver with no capture at all refuses the plain frame too',
      () async {
        final driver = _NoCaptureDriver();
        await expectLater(
          CaptureRequest.fromArguments(const {}).capture(driver),
          throwsA(isA<DriverUnsupportedException>()),
        );
      },
    );
  });

  group('CLI capture surface', () {
    late FakeCdpServer fake;
    late Uri endpoint;

    setUp(() async {
      fake = FakeCdpServer();
      endpoint = await fake.start();
    });
    tearDown(() => fake.stop());

    test('screenshot honors a size cap through the browser', () async {
      final out =
          '${Directory.systemTemp.path}/uat-cap-${DateTime.now().microsecondsSinceEpoch}.png';
      addTearDown(() {
        if (File(out).existsSync()) File(out).deleteSync();
      });
      final code = await runToolkitCli([
        'screenshot',
        '--cdp',
        '$endpoint',
        '--out',
        out,
        '--max-px',
        '400',
      ]);
      expect(code, exitOk);
      final params = fake.screenshotParams.single;
      final clip = params['clip']! as Map<String, Object?>;
      expect(clip['scale'], closeTo(0.5, 1e-9));
    });

    test('screenshot asks for the full page', () async {
      final out =
          '${Directory.systemTemp.path}/uat-full-${DateTime.now().microsecondsSinceEpoch}.png';
      addTearDown(() {
        if (File(out).existsSync()) File(out).deleteSync();
      });
      final code = await runToolkitCli([
        'screenshot',
        '--cdp',
        '$endpoint',
        '--out',
        out,
        '--full-page',
      ]);
      expect(code, exitOk);
      expect(fake.screenshotParams.single['captureBeyondViewport'], isTrue);
    });

    test('screenshot asks for jpeg', () async {
      final out =
          '${Directory.systemTemp.path}/uat-jpeg-${DateTime.now().microsecondsSinceEpoch}.jpg';
      addTearDown(() {
        if (File(out).existsSync()) File(out).deleteSync();
      });
      final code = await runToolkitCli([
        'screenshot',
        '--cdp',
        '$endpoint',
        '--out',
        out,
        '--format',
        'jpeg',
        '--quality',
        '70',
      ]);
      expect(code, exitOk);
      final params = fake.screenshotParams.single;
      expect(params['format'], 'jpeg');
      expect(params['quality'], 70);
    });

    test('a target selector picks the tab it names', () async {
      fake.pageTargets = [
        {
          'id': 'page-1',
          'type': 'page',
          'url': 'https://example.com/one',
          'title': 'One',
        },
        {
          'id': 'page-2',
          'type': 'page',
          'url': 'https://example.com/two',
          'title': 'Two',
        },
      ];
      final out =
          '${Directory.systemTemp.path}/uat-tab-${DateTime.now().microsecondsSinceEpoch}.png';
      addTearDown(() {
        if (File(out).existsSync()) File(out).deleteSync();
      });
      final code = await runToolkitCli([
        'screenshot',
        '--cdp',
        '$endpoint',
        '--out',
        out,
        '--target-url',
        '/two',
      ]);
      expect(code, exitOk);
    });

    test('a target selector that matches nothing fails loudly', () async {
      fake.pageTargets = [
        {'id': 'page-1', 'type': 'page', 'url': 'https://example.com/one'},
      ];
      final out =
          '${Directory.systemTemp.path}/uat-miss-${DateTime.now().microsecondsSinceEpoch}.png';
      addTearDown(() {
        if (File(out).existsSync()) File(out).deleteSync();
      });
      final code = await runToolkitCli([
        'screenshot',
        '--cdp',
        '$endpoint',
        '--out',
        out,
        '--target-url',
        '/missing',
      ]);
      expect(code, exitFailure);
    });
  });
}

/// A driver with no capture capability at all.
final class _NoCaptureDriver implements AutomationDriver {
  @override
  DriverCapabilities get capabilities => const DriverCapabilities();

  @override
  Future<Snapshot> snapshot() async => Snapshot(
    roots: const [AxNode(role: 'root')],
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
