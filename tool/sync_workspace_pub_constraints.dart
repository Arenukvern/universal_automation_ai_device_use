// Syncs ^version constraints for dependencies on other workspace packages.
//
// Must stay SDK-only (no `package:` imports, directly or transitively): the
// release-please sync job invokes it with plain `dart` — not `dart run` — so
// success never depends on package resolution (it repairs a tree whose
// constraints do not resolve yet). tool/workspace_pub_constraints_sync_test.dart
// guards it.
//
// Usage:
//   dart tool/sync_workspace_pub_constraints.dart --check
//   dart tool/sync_workspace_pub_constraints.dart --write

import 'dart:io';

import 'tool_cli.dart';
import 'workspace_pub_constraints_sync.dart';

void printUsage() {
  stdout.writeln('''
Syncs ^version constraints for dependencies on other workspace packages.

Flags:
  --check    Fail if any pkgs/*/pubspec.yaml constraint is out of sync
  --write    Rewrite constraints to match sibling pubspec versions
  --help     Show this text
''');
}

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    printUsage();
    exit(0);
  }

  requireOnlyKnownFlags(
    args,
    flags: {'--check', '--write', '--help', '-h'},
    onUsage: printUsage,
  );

  final write = args.contains('--write');
  final check = args.contains('--check');
  if (!write && !check) {
    stderr.writeln('Pass --check or --write');
    printUsage();
    exit(64);
  }
  if (write && check) {
    stderr.writeln('Pass only one of --check or --write');
    printUsage();
    exit(64);
  }
  exit(runWorkspacePubConstraintSync(write: write));
}
