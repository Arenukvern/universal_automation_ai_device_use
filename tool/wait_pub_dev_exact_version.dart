// Waits until an exact package version appears on pub.dev (post-publish verify).
//
// Usage: dart run tool/wait_pub_dev_exact_version.dart --package NAME --version V

import 'dart:io';

import 'hosted_deps_resolve_lib.dart';
import 'tool_cli.dart';

void printUsage() {
  stdout.writeln('''
Wait until exact package@version is listed on pub.dev.

Flags:
  --package <name>   Package name (required)
  --version <semver> Version (required)
  --timeout-minutes <n>  Default 5
  --help             Show this text
''');
}

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    printUsage();
    exit(0);
  }
  requireOnlyKnownFlags(
    args,
    flags: {'--package', '--version', '--timeout-minutes', '--help', '-h'},
    valueFlags: {'--package', '--version', '--timeout-minutes'},
    onUsage: printUsage,
  );

  String? requireArg(String flag) {
    final i = args.indexOf(flag);
    if (i < 0 || i + 1 >= args.length) {
      stderr.writeln('$flag is required');
      printUsage();
      exit(64);
    }
    return args[i + 1];
  }

  final packageName = requireArg('--package')!;
  final version = requireArg('--version')!;
  var timeout = const Duration(minutes: 5);
  final tIdx = args.indexOf('--timeout-minutes');
  if (tIdx >= 0) {
    timeout = Duration(minutes: int.parse(args[tIdx + 1]));
  }

  final catalog = PubDevCatalog();
  try {
    await waitForVersionOnPubDev(
      catalog: catalog,
      packageName: packageName,
      version: version,
      timeout: timeout,
    );
  } on StateError catch (e) {
    stderr.writeln('::error::${e.message}');
    exit(1);
  } finally {
    catalog.close();
  }
}
