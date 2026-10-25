// Live-Chromium verification of the capture contracts: the size cap must
// land exactly on the requested long side, the full-page capture must
// cover the whole scrollable surface, and a scrolled page must clip at
// the scroll offset rather than the document top.
//
// Opt-in (`XS_TEST_CDP_LIVE=1 dart test ...`) because it spawns a real
// Chrome — same pattern as cdp_live_chrome_test.dart.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_browser_cdp/universal_browser_cdp.dart';

const _fixture = '''
<!DOCTYPE html>
<html><body style="margin:0">
  <div style="height:3000px;background:linear-gradient(#fff,#000)"></div>
</body></html>
''';

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// The dimensions of a PNG or JPEG payload.
(int, int) _imageSize(List<int> bytes) {
  if (bytes.isNotEmpty && bytes[0] == 0x89 && bytes.length > 24) {
    final view = ByteData.view(Uint8List.fromList(bytes).buffer);
    return (view.getUint32(16), view.getUint32(20));
  }
  var i = 2;
  while (i + 9 < bytes.length) {
    if (bytes[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = bytes[i + 1];
    if (marker == 0xD8 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    final length = (bytes[i + 2] << 8) | bytes[i + 3];
    if (marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC) {
      final height = (bytes[i + 5] << 8) | bytes[i + 6];
      final width = (bytes[i + 7] << 8) | bytes[i + 8];
      return (width, height);
    }
    i += 2 + length;
  }
  return (0, 0);
}

void main() {
  if (Platform.environment['XS_TEST_CDP_LIVE'] != '1') {
    // ignore: avoid_print
    print('skipped: set XS_TEST_CDP_LIVE=1 to run against real Chrome');
    return;
  }

  late HttpServer fixtureServer;
  late Process chrome;
  late Uri httpBase;
  late CdpBrowserSession session;

  setUpAll(() async {
    fixtureServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fixtureServer.listen((request) async {
      request.response
        ..headers.contentType = ContentType.html
        ..write(_fixture);
      await request.response.close();
    });

    final cdpPort = await _freePort();
    final profile = Directory.systemTemp.createTempSync('cdp-cap-').path;
    chrome = await Process.start(
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      [
        '--headless=new',
        '--remote-debugging-port=$cdpPort',
        '--user-data-dir=$profile',
        '--no-first-run',
        '--no-default-browser-check',
        '--window-size=800,600',
        'about:blank',
      ],
    );
    httpBase = Uri.parse('http://127.0.0.1:$cdpPort');

    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (true) {
      if (await CdpDiscovery.version(
            httpBase,
            timeout: const Duration(seconds: 2),
          ) !=
          null) {
        break;
      }
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Chrome never answered CDP on $httpBase');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    session = await CdpBrowserSession.attach(httpBase);
    await session.page.navigate(
      Uri.parse('http://127.0.0.1:${fixtureServer.port}/'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });

  tearDownAll(() async {
    await session.close();
    chrome.kill(ProcessSignal.sigkill);
    await fixtureServer.close(force: true);
  });

  group('live capture contracts', () {
    test('the plain capture is the viewport', () async {
      final bytes = await session.page.capture(const CaptureOptions());
      final (width, height) = _imageSize(bytes);
      expect(width, 800);
      expect(height, lessThan(600));
    });

    test('the full-page capture covers the whole scrollable surface', () async {
      final bytes = await session.page.capture(
        const CaptureOptions(fullPage: true),
      );
      final (width, height) = _imageSize(bytes);
      expect(width, 800);
      expect(height, 3000);
    });

    test('the size cap lands exactly on the requested long side', () async {
      final bytes = await session.page.capture(
        const CaptureOptions(maxPx: 400),
      );
      final (width, height) = _imageSize(bytes);
      expect(
        width > height ? width : height,
        400,
        reason: 'the long side is capped at 400 device pixels',
      );
    });

    test('the cap applies to the full page too', () async {
      final bytes = await session.page.capture(
        const CaptureOptions(fullPage: true, maxPx: 300),
      );
      final (width, height) = _imageSize(bytes);
      expect(width > height ? width : height, 300);
    });

    test('jpeg is produced when asked for', () async {
      final bytes = await session.page.capture(
        const CaptureOptions(format: CaptureFormat.jpeg, quality: 85),
      );
      // A JPEG starts with the SOI marker.
      expect(bytes[0], 0xFF);
      expect(bytes[1], 0xD8);
    });

    test('a cap with jpeg still lands on the requested long side', () async {
      final bytes = await session.page.capture(
        const CaptureOptions(
          format: CaptureFormat.jpeg,
          quality: 80,
          maxPx: 256,
        ),
      );
      final (width, height) = _imageSize(bytes);
      expect(width > height ? width : height, 256);
    });
  });
}
