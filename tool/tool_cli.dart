import 'dart:io';

/// Exits 64 when [args] include unknown flags or unexpected positional args.
void requireOnlyKnownFlags(
  List<String> args, {
  required Set<String> flags,
  Set<String> valueFlags = const {},
  void Function()? onUsage,
}) {
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('-')) {
      stderr.writeln('Unexpected argument: $a');
      onUsage?.call();
      exit(64);
    }
    if (valueFlags.contains(a)) {
      if (i + 1 >= args.length) {
        stderr.writeln('$a requires a value');
        onUsage?.call();
        exit(64);
      }
      i++;
      continue;
    }
    if (!flags.contains(a)) {
      stderr.writeln('Unknown flag: $a');
      onUsage?.call();
      exit(64);
    }
  }
}
