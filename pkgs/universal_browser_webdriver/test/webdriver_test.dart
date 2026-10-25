import 'dart:convert';

import 'package:test/test.dart';
import 'package:universal_automation_conformance/universal_automation_conformance.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_browser_webdriver/testing.dart';
import 'package:universal_browser_webdriver/universal_browser_webdriver.dart';

void main() {
  late FakeWebDriverServer server;
  late WebDriverClient client;

  setUp(() async {
    server = FakeWebDriverServer();
    final base = await server.start();
    client = WebDriverClient(base);
  });

  tearDown(() async {
    await client.deleteSession();
    await server.stop();
  });

  group('WebDriverClient', () {
    test('status works without a session', () async {
      final status = await client.status();
      expect(status['ready'], isTrue);
    });

    test('newSession stores the session id', () async {
      final id = await client.newSession(
        capabilities: {'browserName': 'safari'},
      );
      expect(id, startsWith('session-'));
      expect(client.sessionId, id);
      expect(server.sessions, hasLength(1));
    });

    test('navigate updates the remote url', () async {
      await client.newSession();
      await client.navigate(Uri.parse('https://example.test/page'));
      expect(server.currentUrl, 'https://example.test/page');
      expect(await client.currentUrl(), Uri.parse('https://example.test/page'));
      expect(await client.title(), 'Fake page');
    });

    test('find, click, and type flow', () async {
      await client.newSession();
      final element = await client.findElementByCss('#submit');
      expect(element.id, 'elem-1');
      await client.elementClick(element);
      await client.sendKeys(element, 'hello');
      expect(server.clicks, ['elem-1']);
      expect(server.typedTexts, ['hello']);
      expect(await client.elementText(element), 'fake element text');
    });

    test('key actions reach the remote end', () async {
      await client.newSession();
      await client.keyPress('');
      expect(server.keyPresses, ['']);
    });

    test('screenshot decodes', () async {
      await client.newSession();
      final bytes = await client.screenshot();
      expect(base64Encode(bytes), server.screenshotBase64);
    });

    test('error envelopes map to family exceptions', () async {
      await client.newSession();
      server.failNext = (
        error: 'no such element',
        message: '#missing',
        status: 404,
      );
      await expectLater(
        client.findElementByCss('#missing'),
        throwsA(
          isA<ElementNotFoundException>()
              .having((error) => error.locator, 'locator', 'unspecified')
              .having(
                (error) => error.locatorValue,
                'locatorValue',
                '#missing',
              ),
        ),
      );
    });

    test('deleteSession is idempotent', () async {
      await client.newSession();
      await client.deleteSession();
      await client.deleteSession();
      expect(client.sessionId, isNull);
    });

    test('KeyPressAction presses the W3C wire key', () async {
      final base = client.serverUri;
      final sessionClient = WebDriverClient(base);
      await sessionClient.newSession();
      final driver = WebDriverDriver(sessionClient);
      addTearDown(sessionClient.deleteSession);
      await driver.perform(const KeyPressAction('Enter'));
      expect(server.keyPresses, ['\uE007']);
      await expectLater(
        driver.perform(const KeyPressAction('F5')),
        throwsA(isA<DriverUnsupportedException>()),
      );
    });
  });

  group('WebDriverDriver capture', () {
    late WebDriverDriver driver;

    setUp(() async {
      final sessionClient = WebDriverClient(client.serverUri);
      await sessionClient.newSession();
      driver = WebDriverDriver(sessionClient);
      addTearDown(sessionClient.deleteSession);
    });

    test('the plain viewport PNG is served', () async {
      final bytes = await driver.capture(const CaptureOptions());
      expect(base64Encode(bytes), fakePngBase64);
    });

    test('a full-page capture refuses with the route out', () async {
      await expectLater(
        driver.capture(const CaptureOptions(fullPage: true)),
        throwsA(
          isA<DriverUnsupportedException>()
              .having(
                (error) => error.message,
                'message',
                contains('no full-page screenshot'),
              )
              .having(
                (error) => error.details['remedy'],
                'remedy',
                contains('--cdp'),
              ),
        ),
      );
    });

    test('a size cap refuses with the route out', () async {
      await expectLater(
        driver.capture(const CaptureOptions(maxPx: 800)),
        throwsA(
          isA<DriverUnsupportedException>()
              .having(
                (error) => error.message,
                'message',
                contains('cannot resize'),
              )
              .having(
                (error) => error.details['remedy'],
                'remedy',
                contains('--cdp'),
              ),
        ),
      );
    });

    test('a jpeg capture refuses with the route out', () async {
      await expectLater(
        driver.capture(
          const CaptureOptions(format: CaptureFormat.jpeg, quality: 80),
        ),
        throwsA(
          isA<DriverUnsupportedException>()
              .having(
                (error) => error.message,
                'message',
                contains('returns PNG only'),
              )
              .having(
                (error) => error.details['remedy'],
                'remedy',
                contains('--cdp'),
              ),
        ),
      );
    });

    test(
      'an invalid option set is rejected before anything is captured',
      () async {
        await expectLater(
          driver.capture(const CaptureOptions(quality: 80)),
          throwsA(isA<SpecViolationException>()),
        );
      },
    );
  });

  automationDriverConformanceTests(
    'WebDriverDriver over FakeWebDriverServer',
    createDriver: () async {
      final base = client.serverUri;
      final sessionClient = WebDriverClient(base);
      await sessionClient.newSession();
      return WebDriverDriver(sessionClient);
    },
  );
}
