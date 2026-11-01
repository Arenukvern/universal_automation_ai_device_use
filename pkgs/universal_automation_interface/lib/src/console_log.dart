import 'package:meta/meta.dart';

/// One captured console line or page error from a live surface.
///
/// The shared vocabulary behind [ConsoleLogReader]: every transport that
/// captures console output reports entries in this shape, so verification
/// harnesses read one structure regardless of tier.
@immutable
final class ConsoleEntry {
  /// Creates an entry.
  const ConsoleEntry({
    required this.source,
    required this.level,
    required this.text,
    required this.at,
  });

  /// Where the entry came from: `console` (a console API call),
  /// `exception` (an uncaught page exception), or `log` (a browser log
  /// entry — network failures, parser errors).
  final String source;

  /// Severity as the source protocol reported it (`log`, `info`,
  /// `warning`, `error`, `debug`); no normalization beyond the name.
  final String level;

  /// The rendered message text (argument values joined, exception
  /// description, log entry text).
  final String text;

  /// Wall-clock time the entry was observed.
  final DateTime at;

  /// Canonical JSON shape.
  Map<String, Object?> toJson() => {
    'source': source,
    'level': level,
    'text': text,
    'at': at.toIso8601String(),
  };

  @override
  String toString() => 'ConsoleEntry($source/$level: $text)';
}

/// Reads buffered console output from a live surface.
///
/// A driver that captures console API calls and page errors (the CDP
/// tier today) implements this. Entries buffer per attached surface and
/// survive between calls until [drainConsole] clears them — session
/// reuse is what makes the buffer accumulate real page history.
abstract interface class ConsoleLogReader {
  /// The buffered entries, oldest first. A snapshot: the buffer keeps
  /// growing until [drainConsole].
  List<ConsoleEntry> consoleEntries();

  /// Returns the buffered entries, oldest first, and clears the buffer.
  List<ConsoleEntry> drainConsole();
}
