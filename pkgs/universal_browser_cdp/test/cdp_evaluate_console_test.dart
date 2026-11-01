import 'dart:async';

import 'package:test/test.dart';
import 'package:universal_browser_cdp/testing.dart';
import 'package:universal_browser_cdp/universal_browser_cdp.dart';

void main() {
  late FakeCdpServer server;

  setUp(() async {
    server = FakeCdpServer();
    await server.start();
  });

  tearDown(() async {
    await server.stop();
  });

  Future<CdpDriver> attachDriver() async {
    final session = await CdpBrowserSession.attach(server.httpBase);
    return session.driver;
  }

  /// Lets socket-delivered events land in the log's subscriptions.
  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 50));

  group('CdpPage.evaluateValue', () {
    test('returns the serializable value (primitive, object, null)', () async {
      final driver = await attachDriver();
      server.evaluateResult = {'type': 'number', 'value': 42};
      expect(await driver.evaluateExpression('21 * 2'), 42);
      server.evaluateResult = {
        'type': 'object',
        'value': {
          'a': 1,
          'b': ['x'],
        },
      };
      expect(await driver.evaluateExpression('({a: 1, b: ["x"]})'), {
        'a': 1,
        'b': ['x'],
      });
      server.evaluateResult = {
        'type': 'object',
        'subtype': 'null',
        'value': null,
      };
      expect(await driver.evaluateExpression('null'), isNull);
    });

    test(
      'reports an unserializable value as a type/description descriptor',
      () async {
        final driver = await attachDriver();
        server.evaluateResult = {'type': 'function', 'description': '() => 1'};
        final result = await driver.evaluateExpression('(() => 1)');
        expect(result, {'type': 'function', 'description': '() => 1'});
      },
    );

    test('renders undefined as null', () async {
      final driver = await attachDriver();
      server.evaluateResult = {'type': 'undefined'};
      expect(await driver.evaluateExpression('undefined'), isNull);
    });

    test('retries a protocol serialization refusal without returnByValue '
        'and still reports the descriptor', () async {
      final driver = await attachDriver();
      server
        ..failNextWithError = {
          'code': -32000,
          'message': 'Object reference chain is too long',
        }
        ..evaluateResult = {'type': 'object', 'description': 'Object'};
      final result = await driver.evaluateExpression('cyclic');
      expect(result, {'type': 'object', 'description': 'Object'});
      // The retry is visible on the wire: two Runtime.evaluate calls.
      expect(
        server.methods.where((method) => method == 'Runtime.evaluate'),
        hasLength(2),
      );
    });

    test('throws a typed exception carrying the exception details', () async {
      final driver = await attachDriver();
      server.evaluateException = 'TypeError: x is not a function';
      await expectLater(
        driver.evaluateExpression('x()'),
        throwsA(
          isA<ProtocolException>()
              .having(
                (error) => error.message,
                'message',
                contains('TypeError: x is not a function'),
              )
              .having(
                (error) =>
                    (error.details['exception'] as Map<String, Object?>?)?[
                      'description'
                    ],
                'details.exception.description',
                contains('TypeError: x is not a function'),
              ),
        ),
      );
    });
  });

  group('CdpConsoleLog', () {
    test('buffers console API calls, exceptions, and log entries', () async {
      final driver = await attachDriver();
      server
        ..emit('Runtime.consoleAPICalled', {
          'type': 'log',
          'args': [
            {'type': 'string', 'value': 'hello'},
            {'type': 'object', 'description': 'Object'},
          ],
        })
        ..emit('Runtime.exceptionThrown', {
          'exceptionDetails': {
            'text': 'Uncaught',
            'exception': {'type': 'object', 'description': 'Error: boom'},
            'lineNumber': 2,
          },
        })
        ..emit('Log.entryAdded', {
          'entry': {
            'source': 'network',
            'level': 'error',
            'text': 'Failed to load resource',
            'url': 'https://example.test/x.js',
            'lineNumber': 0,
          },
        });
      await pump();

      final entries = driver.consoleEntries();
      expect(entries, hasLength(3));
      expect(entries[0].source, 'console');
      expect(entries[0].level, 'log');
      expect(entries[0].text, 'hello Object');
      expect(entries[1].source, 'exception');
      expect(entries[1].level, 'error');
      expect(entries[1].text, contains('Error: boom'));
      expect(entries[1].text, contains('line 3'));
      expect(entries[2].source, 'log');
      expect(entries[2].text, contains('Failed to load resource'));
      expect(entries[2].text, contains('x.js:1'));
    });

    test('drain returns the entries and clears the buffer', () async {
      final driver = await attachDriver();
      server.emit('Runtime.consoleAPICalled', {
        'type': 'warning',
        'args': [
          {'type': 'string', 'value': 'watch out'},
        ],
      });
      await pump();

      final drained = driver.drainConsole();
      expect(drained, hasLength(1));
      expect(drained.single.level, 'warning');
      expect(driver.consoleEntries(), isEmpty);
      // The second drain is empty: the buffer was cleared.
      expect(driver.drainConsole(), isEmpty);
    });

    test('the ring buffer drops the oldest beyond the cap', () async {
      final driver = await attachDriver();
      for (var i = 0; i < 1002; i++) {
        server.emit('Runtime.consoleAPICalled', {
          'type': 'log',
          'args': [
            {'type': 'number', 'value': i},
          ],
        });
      }
      await pump();

      final entries = driver.consoleEntries();
      expect(entries, hasLength(1000));
      // 1002 events through a 1000-slot ring: the two oldest dropped.
      expect(entries.first.text, '2');
      expect(entries.last.text, '1001');
    });

    test('entries survive a navigation (preserve-log semantics)', () async {
      final driver = await attachDriver();
      server.emit('Runtime.consoleAPICalled', {
        'type': 'error',
        'args': [
          {'type': 'string', 'value': 'before nav'},
        ],
      });
      await pump();
      await driver.page.navigate(Uri.parse('https://example.test/next'));
      await pump();

      final entries = driver.consoleEntries();
      expect(entries.map((entry) => entry.text), contains('before nav'));
    });

    test('entry JSON shape is stable', () async {
      final driver = await attachDriver();
      server.emit('Runtime.consoleAPICalled', {
        'type': 'log',
        'args': [
          {'type': 'string', 'value': 'x'},
        ],
      });
      await pump();
      final json = driver.consoleEntries().single.toJson();
      expect(json.keys, ['source', 'level', 'text', 'at']);
      expect(json['source'], 'console');
      expect(json['text'], 'x');
    });
  });
}
