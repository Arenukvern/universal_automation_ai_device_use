// Capture contracts: the full-page extension, the size cap, the encoding
// choice, and the target selector that stops a multi-tab browser from
// attaching to an arbitrary tab.
import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_browser_cdp/testing.dart';
import 'package:universal_browser_cdp/universal_browser_cdp.dart';

void main() {
  late FakeCdpServer server;
  late Uri httpBase;

  setUp(() async {
    server = FakeCdpServer();
    httpBase = await server.start();
  });

  tearDown(() async {
    await server.stop();
  });

  group('CaptureOptions', () {
    test('rejects an out-of-range cap and quality', () {
      expect(
        const CaptureOptions(maxPx: 0).validate(),
        contains('capture.maxPx must be positive (got 0)'),
      );
      expect(
        const CaptureOptions(quality: 0).validate(),
        contains('capture.quality must be 1..100 (got 0)'),
      );
      expect(
        const CaptureOptions(quality: 101).validate(),
        contains('capture.quality must be 1..100 (got 101)'),
      );
    });

    test('rejects a quality setting on the lossless format', () {
      expect(
        const CaptureOptions(quality: 90).validate(),
        contains('capture.quality applies to jpeg only; png is lossless'),
      );
      expect(
        const CaptureOptions(
          format: CaptureFormat.jpeg,
          quality: 90,
        ).validate(),
        isEmpty,
      );
    });

    test('a valid option set passes', () {
      expect(const CaptureOptions().validate(), isEmpty);
      expect(
        const CaptureOptions(fullPage: true, maxPx: 1024).validate(),
        isEmpty,
      );
    });

    test('ensureValid throws on an invalid set', () {
      expect(
        () => const CaptureOptions(maxPx: -1).ensureValid(),
        throwsA(isA<SpecViolationException>()),
      );
    });
  });

  group('CdpPage.capture', () {
    late CdpBrowserSession session;

    setUp(() async {
      session = await CdpBrowserSession.attach(httpBase);
    });

    tearDown(() async {
      await session.close();
    });

    test('a plain capture asks for no clip and no format change', () async {
      await session.page.capture(const CaptureOptions());
      final params = server.screenshotParams.single;
      expect(params['format'], 'png');
      expect(params.containsKey('clip'), isFalse);
      expect(params.containsKey('captureBeyondViewport'), isFalse);
    });

    test('full page asks the browser to capture beyond the viewport', () async {
      await session.page.capture(const CaptureOptions(fullPage: true));
      final params = server.screenshotParams.single;
      expect(params['captureBeyondViewport'], isTrue);
    });

    test(
      'a size cap is applied as a browser-side clip, never a resample',
      () async {
        // 800x600 content at dpr 1: the long side is 800 device pixels, so
        // a 400 cap asks the browser for scale 0.5.
        await session.page.capture(const CaptureOptions(maxPx: 400));
        final params = server.screenshotParams.single;
        final clip = params['clip']! as Map<String, Object?>;
        expect(clip['width'], 800);
        expect(clip['height'], 600);
        expect(clip['scale'], closeTo(0.5, 1e-9));
      },
    );

    test('the cap accounts for the device pixel ratio', () async {
      // A HiDPI page: 800 CSS pixels are 1600 device pixels.
      server.layoutMetrics = {
        ...server.layoutMetrics,
        'contentSize': {'x': 0, 'y': 0, 'width': 1600, 'height': 1200},
        'cssContentSize': {'x': 0, 'y': 0, 'width': 800, 'height': 600},
      };
      await session.page.capture(const CaptureOptions(maxPx: 800));
      final clip =
          server.screenshotParams.single['clip']! as Map<String, Object?>;
      // 1600 device pixels onto an 800 cap is a factor of 0.5.
      expect(clip['scale'], closeTo(0.5, 1e-9));
    });

    test('a cap larger than the image never upscales', () async {
      await session.page.capture(const CaptureOptions(maxPx: 4000));
      final params = server.screenshotParams.single;
      expect(params.containsKey('clip'), isFalse);
    });

    test(
      'a scrolled page clips at the scroll offset, not the document top',
      () async {
        server.layoutMetrics = {
          ...server.layoutMetrics,
          'visualViewport': {
            ...(server.layoutMetrics['visualViewport']!
                as Map<String, Object?>),
            'pageX': 0,
            'pageY': 900,
          },
          'cssVisualViewport': {
            ...(server.layoutMetrics['cssVisualViewport']!
                as Map<String, Object?>),
            'pageX': 0,
            'pageY': 900,
          },
        };
        await session.page.capture(const CaptureOptions(maxPx: 400));
        final clip =
            server.screenshotParams.single['clip']! as Map<String, Object?>;
        expect(clip['y'], 900);
      },
    );

    test('jpeg is requested with its quality', () async {
      await session.page.capture(
        const CaptureOptions(format: CaptureFormat.jpeg, quality: 85),
      );
      final params = server.screenshotParams.single;
      expect(params['format'], 'jpeg');
      expect(params['quality'], 85);
    });

    test('an invalid option set refuses before the browser is asked', () async {
      await expectLater(
        session.page.capture(const CaptureOptions(maxPx: 0)),
        throwsA(isA<SpecViolationException>()),
      );
      expect(server.screenshotParams, isEmpty);
    });
  });

  group('CdpTargetSelector', () {
    test('matches by id, url, and title', () {
      const target = CdpTargetInfo(
        id: 'abc',
        type: 'page',
        url: 'https://example.com/checkout',
        title: 'Checkout',
        webSocketDebuggerUrl: 'ws://x',
      );
      expect(const CdpTargetSelector(id: 'abc').matches(target), isTrue);
      expect(const CdpTargetSelector(id: 'other').matches(target), isFalse);
      expect(
        const CdpTargetSelector(urlContains: 'example.com').matches(target),
        isTrue,
      );
      expect(
        const CdpTargetSelector(urlContains: 'other.com').matches(target),
        isFalse,
      );
      expect(
        const CdpTargetSelector(titleContains: 'Check').matches(target),
        isTrue,
      );
    });

    test('criteria combine as AND', () {
      const target = CdpTargetInfo(
        id: 'abc',
        type: 'page',
        url: 'https://example.com/checkout',
        title: 'Checkout',
        webSocketDebuggerUrl: 'ws://x',
      );
      expect(
        const CdpTargetSelector(
          id: 'abc',
          urlContains: 'example.com',
        ).matches(target),
        isTrue,
      );
      expect(
        const CdpTargetSelector(
          id: 'abc',
          urlContains: 'other.com',
        ).matches(target),
        isFalse,
      );
    });

    test('round-trips through a URI fragment', () {
      const selector = CdpTargetSelector(id: 'abc', urlContains: 'example.com');
      final uri = selector.applyTo(Uri.parse('http://127.0.0.1:9222'));
      final restored = CdpTargetSelector.fromUri(uri);
      expect(restored?.id, 'abc');
      expect(restored?.urlContains, 'example.com');
    });

    test('a URI without a selector yields null', () {
      expect(
        CdpTargetSelector.fromUri(Uri.parse('http://127.0.0.1:9222')),
        isNull,
      );
    });
  });

  group('target selection', () {
    test('attaches to the first page when nothing is specified', () async {
      final session = await CdpBrowserSession.attach(httpBase);
      expect(session.page.target.id, 'page-1');
      await session.close();
    });

    test('attaches to the tab the selector names', () async {
      server.pageTargets = [
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
      final session = await CdpBrowserSession.attach(
        httpBase,
        selector: const CdpTargetSelector(urlContains: '/two'),
      );
      expect(session.page.target.id, 'page-2');
      await session.close();
    });

    test('the selector may ride the endpoint URI fragment', () async {
      server.pageTargets = [
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
      final session = await CdpBrowserSession.attach(
        httpBase.replace(fragment: 'targetId=page-2'),
      );
      expect(session.page.target.id, 'page-2');
      await session.close();
    });

    test('a selector matching nothing refuses loudly', () async {
      server.pageTargets = [
        {'id': 'page-1', 'type': 'page', 'url': 'https://example.com/one'},
      ];
      await expectLater(
        CdpBrowserSession.attach(
          httpBase,
          selector: const CdpTargetSelector(urlContains: '/missing'),
        ),
        throwsA(
          isA<TargetSelectionException>().having(
            (error) => error.kind,
            'kind',
            'targetSelection',
          ),
        ),
      );
    });

    test(
      'a selector matching several tabs refuses rather than guessing',
      () async {
        server.pageTargets = [
          {'id': 'page-1', 'type': 'page', 'url': 'https://example.com/one'},
          {'id': 'page-2', 'type': 'page', 'url': 'https://example.com/two'},
        ];
        await expectLater(
          CdpBrowserSession.attach(
            httpBase,
            selector: const CdpTargetSelector(urlContains: 'example.com'),
          ),
          throwsA(
            isA<TargetSelectionException>().having(
              (error) => error.matches.length,
              'matches',
              2,
            ),
          ),
        );
      },
    );
  });
}
