import 'dart:async';
import 'dart:convert';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'cdp_connection.dart';

/// Observation-side console log for one page: console API calls,
/// uncaught page exceptions, and browser log entries, in arrival order.
///
/// Enabled by `CdpPage.attach` — the buffer is what makes web
/// verification honest ("the page logged an error") without the caller
/// scripting anything into the page. The `Runtime.*` events ride the
/// Runtime domain `CdpPage.attach` enables; the `Log` domain is enabled
/// best-effort (an endpoint without it still reports console API calls
/// and exceptions). Entries buffer in a ring (oldest drop) and survive
/// between tool calls until [drain] clears them.
final class CdpConsoleLog {
  CdpConsoleLog._(this._connection) {
    // Subscribe BEFORE any enable lands: the socket delivers events in
    // order, and a listener registered after the response would miss the
    // event on the broadcast stream (the CdpNetworkLog rule).
    _subscriptions = [
      _connection.on('Runtime.consoleAPICalled').listen(_onConsoleApi),
      _connection.on('Runtime.exceptionThrown').listen(_onException),
      _connection.on('Log.entryAdded').listen(_onLogEntry),
    ];
  }

  final CdpTransport _connection;
  late final List<StreamSubscription<CdpEvent>> _subscriptions;
  final List<ConsoleEntry> _entries = [];

  /// Ring-buffer cap; the oldest entries fall off beyond this.
  final int maxEntries = 1000;

  /// Attaches the log: subscribes to the console sources first, then
  /// enables the `Log` domain — no early event can be lost. A protocol
  /// refusal of `Log.enable` is tolerated: the Runtime sources keep the
  /// capture useful on embedded endpoints.
  static Future<CdpConsoleLog> attach(CdpTransport connection) async {
    final log = CdpConsoleLog._(connection);
    try {
      await connection.send('Log.enable');
    } on CdpProtocolException {
      // Log-domain-free endpoint (some embedded webviews): console API
      // calls and exceptions still land.
    }
    return log;
  }

  /// Cancels the event subscriptions (page teardown).
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }

  /// Buffered entries, oldest first.
  List<ConsoleEntry> get entries => List.unmodifiable(_entries);

  /// Returns the buffered entries, oldest first, and clears the buffer.
  List<ConsoleEntry> drain() {
    final drained = List<ConsoleEntry>.of(_entries);
    _entries.clear();
    return drained;
  }

  void _add(ConsoleEntry entry) {
    _entries.add(entry);
    while (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
  }

  /// `Runtime.consoleAPICalled`: `console.log('x', 1)` and friends.
  void _onConsoleApi(CdpEvent event) {
    final args = event.params['args'];
    if (args is! List<Object?>) return;
    final type = event.params['type'];
    _add(
      ConsoleEntry(
        source: 'console',
        level: type is String ? type : 'log',
        text: [for (final arg in args) _renderRemoteObject(arg)].join(' '),
        at: DateTime.now(),
      ),
    );
  }

  /// `Runtime.exceptionThrown`: an uncaught page exception.
  void _onException(CdpEvent event) {
    final details = event.params['exceptionDetails'] as Map<String, Object?>?;
    if (details == null) return;
    _add(
      ConsoleEntry(
        source: 'exception',
        level: 'error',
        text: _exceptionText(details),
        at: DateTime.now(),
      ),
    );
  }

  /// `Log.entryAdded`: browser-side log entries (network failures,
  /// parser and security errors).
  void _onLogEntry(CdpEvent event) {
    final entry = event.params['entry'] as Map<String, Object?>?;
    if (entry == null) return;
    final url = entry['url'];
    final line = entry['lineNumber'];
    final location = url is String && url.isNotEmpty
        ? ' ($url${line is num ? ':${line.toInt() + 1}' : ''})'
        : '';
    final level = entry['level'];
    _add(
      ConsoleEntry(
        source: 'log',
        level: level is String ? level : 'info',
        text: '${entry['text'] ?? ''}$location',
        at: DateTime.now(),
      ),
    );
  }

  /// One rendered RemoteObject argument: the value when serializable,
  /// else the description, else the type.
  static String _renderRemoteObject(Object? arg) {
    if (arg is! Map<String, Object?>) return '$arg';
    final value = arg['value'];
    if (value is String) return value;
    if (value != null) return jsonEncode(value);
    return '${arg['description'] ?? arg['type'] ?? 'undefined'}';
  }

  /// The one-line text of a CDP `exceptionDetails` object (line numbers
  /// arrive 0-based; the report is 1-based).
  static String _exceptionText(Map<String, Object?> details) {
    final exception = details['exception'] as Map<String, Object?>?;
    final description = exception?['description'] ?? details['text'];
    final line = details['lineNumber'];
    final location = line is int ? ' (line ${line + 1})' : '';
    return '${description ?? 'unknown exception'}$location';
  }
}
