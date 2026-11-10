// Waits until runtime universal_* sibling deps resolve on pub.dev.
//
// Usage: dart run tool/wait_pub_dev_runtime_deps.dart --package-dir pkgs/foo

import 'dart:io';

import 'hosted_deps_resolve_lib.dart';
import 'tool_cli.dart';
import 'wait_pub_dev_runtime_deps_lib.dart';
import 'workspace_pub_constraints_sync.dart';

void printUsage() {
  stdout.writeln('''
Wait for pub.dev to list versions satisfying runtime universal_* constraints.

Flags:
  --package-dir <path>  Package directory (required)
  --timeout-minutes <n>  Default 20
  --help                Show this text
''');
}

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    printUsage();
    exit(0);
  }
  requireOnlyKnownFlags(
    args,
    flags: {'--package-dir', '--timeout-minutes', '--help', '-h'},
    valueFlags: {'--package-dir', '--timeout-minutes'},
    onUsage: printUsage,
  );

  final dirIdx = args.indexOf('--package-dir');
  if (dirIdx < 0 || dirIdx + 1 >= args.length) {
    stderr.writeln('--package-dir is required');
    printUsage();
    exit(64);
  }
  final pkgDir = args[dirIdx + 1];
  var timeout = const Duration(minutes: 20);
  final tIdx = args.indexOf('--timeout-minutes');
  if (tIdx >= 0) {
    timeout = Duration(minutes: int.parse(args[tIdx + 1]));
  }

  final catalog = PubDevCatalog();
  try {
    await waitForRuntimeDepsOnPubDev(
      packageDir: Directory('${findWorkspaceRepoRoot().path}/$pkgDir'),
      catalog: catalog,
      timeout: timeout,
    );
    stdout.writeln('Runtime dependencies are satisfied on pub.dev.');
  } on StateError catch (e) {
    stderr.writeln('::error::${e.message}');
    exit(1);
  } on HttpException catch (e) {
    stderr.writeln('::error::pub.dev HTTP error: $e');
    exit(1);
  } on SocketException catch (e) {
    stderr.writeln('::error::pub.dev unreachable: $e');
    exit(1);
  } finally {
    catalog.close();
  }
}
