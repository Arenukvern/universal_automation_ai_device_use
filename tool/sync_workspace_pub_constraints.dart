// Syncs ^version constraints for dependencies on other workspace packages.
//
// Usage:
//   dart run tool/sync_workspace_pub_constraints.dart --check
//   dart run tool/sync_workspace_pub_constraints.dart --write

import 'dart:io';

import 'workspace_pub_constraints_sync.dart';

void main(List<String> args) {
  final write = args.contains('--write');
  if (!write && !args.contains('--check')) {
    stderr.writeln('Pass --check or --write');
    exit(64);
  }
  exit(runWorkspacePubConstraintSync(write: write));
}
