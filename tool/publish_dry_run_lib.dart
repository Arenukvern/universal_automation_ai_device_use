/// `dart pub publish --dry-run` exits 65 when the package has warnings
/// (still publishable, but should block release-PR gates).
const pubPublishDryRunWarningsExitCode = 65;

/// Release-PR gate: fail on warnings (65) or errors (any other non-zero).
bool publishDryRunGateFailed(int exitCode) => exitCode != 0;

/// Human-readable gate message for CI logs.
String formatPublishDryRunGateFailure({
  required String packageName,
  required int exitCode,
  required String combinedOutput,
}) {
  final kind = exitCode == pubPublishDryRunWarningsExitCode
      ? 'warnings (exit 65)'
      : 'errors (exit $exitCode)';
  final summary = 'pub publish --dry-run failed: $kind';
  final buffer = StringBuffer()
    ..writeln('::error title=$packageName::$summary');
  for (final line in combinedOutput.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final lower = trimmed.toLowerCase();
    if (lower.contains('warning') ||
        lower.contains('error') ||
        lower.contains('pub publish')) {
      buffer.writeln('  $trimmed');
    }
  }
  return buffer.toString();
}