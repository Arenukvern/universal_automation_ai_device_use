// End-to-end proof against real Chrome: the CLI capture surface must
// produce a full-page image, an exactly-capped image, and a JPEG — and
// must pick the tab a target selector names.
//
// Opt-in (XS_TEST_CDP_LIVE=1) because it spawns a real Chrome.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_automation_toolkit/src/cli/toolkit_cli.dart';

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
  late Uri cdpBase;
  final outputs = <String>[];

  setUpAll(() async {
    fixtureServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fixtureServer.listen((request) async {
      request.response
        ..headers.contentType = ContentType.html
        ..write(_fixture);
      await request.response.close();
    });

    final cdpPort = await _freePort();
    chrome = await Process.start(
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      [
        '--headless=new',
        '--remote-debugging-port=$cdpPort',
        '--user-data-dir=${Directory.systemTemp.createTempSync('uat-cap-').path}',
        '--no-first-run',
        '--no-default-browser-check',
        '--window-size=800,600',
        // The CLI captures the CURRENT page, so the browser opens on the
        // fixture: a full-page capture needs a scrollable surface.
        'http://127.0.0.1:${fixtureServer.port}/',
      ],
    );
    cdpBase = Uri.parse('http://127.0.0.1:$cdpPort');

    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (true) {
      try {
        final response = await HttpClient()
            .getUrl(cdpBase.replace(path: '/json/version'))
            .timeout(const Duration(seconds: 2));
        await response.close();
        break;
      } on Object {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Chrome never answered CDP on $cdpBase');
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    // The fixture must be laid out before the capture measures it.
    await Future<void>.delayed(const Duration(seconds: 1));
  });

  tearDownAll(() async {
    for (final path in outputs) {
      if (File(path).existsSync()) File(path).deleteSync();
    }
    chrome.kill(ProcessSignal.sigkill);
    await fixtureServer.close(force: true);
  });

  String outputPath(String label) {
    final path =
        '${Directory.systemTemp.path}/uat-live-$label-${DateTime.now().microsecondsSinceEpoch}';
    outputs.add(path);
    return path;
  }

  test('the CLI captures the full page against real Chrome', () async {
    final out = outputPath('full');
    final code = await runToolkitCli([
      'screenshot',
      '--cdp',
      '$cdpBase',
      '--out',
      out,
      '--full-page',
    ]);
    expect(code, exitOk);
    final (width, height) = _imageSize(File(out).readAsBytesSync());
    expect(width, 800);
    expect(height, 3000, reason: 'the whole scrollable surface');
  });

  test('the CLI caps the long side exactly', () async {
    final out = outputPath('cap');
    final code = await runToolkitCli([
      'screenshot',
      '--cdp',
      '$cdpBase',
      '--out',
      out,
      '--max-px',
      '300',
    ]);
    expect(code, exitOk);
    final (width, height) = _imageSize(File(out).readAsBytesSync());
    expect(width > height ? width : height, 300);
  });

  test('the CLI writes a JPEG when asked', () async {
    final out = outputPath('jpeg');
    final code = await runToolkitCli([
      'screenshot',
      '--cdp',
      '$cdpBase',
      '--out',
      out,
      '--format',
      'jpeg',
      '--quality',
      '80',
    ]);
    expect(code, exitOk);
    final bytes = File(out).readAsBytesSync();
    expect(bytes[0], 0xFF);
    expect(bytes[1], 0xD8);
  });

  test('a target selector that matches nothing fails loudly', () async {
    final out = outputPath('miss');
    final code = await runToolkitCli([
      'screenshot',
      '--cdp',
      '$cdpBase',
      '--out',
      out,
      '--target-url',
      '/definitely-not-this-tab',
    ]);
    expect(code, exitFailure);
  });
}
