import 'dart:io';

import 'package:test/test.dart';

import 'workspace_pub_constraints_sync.dart';

Future<ProcessResult> _runTool(String script, List<String> args) {
  final root = findWorkspaceRepoRoot();
  return Process.run(
    'dart',
    ['run', 'tool/$script', ...args],
    workingDirectory: root.path,
    runInShell: false,
  );
}

void main() {
  group('check_hosted_deps_resolve.dart flags', () {
    test('unknown flag exits 64 with usage', () async {
      final r = await _runTool(
        'check_hosted_deps_resolve.dart',
        ['--co-release', '--not-a-real-flag'],
      );
      expect(r.exitCode, 64);
      expect(r.stderr, contains('Unknown flag: --not-a-real-flag'));
      expect(r.stdout, contains('Hosted dependency resolve'));
    });

    test('--release-pr without manifest-drift or audit exits 64', () async {
      final r = await _runTool('check_hosted_deps_resolve.dart', ['--release-pr']);
      expect(r.exitCode, 64);
      expect(
        r.stderr,
        contains('--release-pr requires --check-manifest-drift or --audit-published'),
      );
    });

    test('--release-pr with --audit-published is allowed', () async {
      final r = await _runTool(
        'check_hosted_deps_resolve.dart',
        ['--audit-published', '--release-pr', '--help'],
      );
      expect(r.exitCode, 0);
    });
  });

  group('sync_workspace_pub_constraints.dart flags', () {
    test('unknown flag exits 64 with usage', () async {
      final r = await _runTool(
        'sync_workspace_pub_constraints.dart',
        ['--check', '--release-pr'],
      );
      expect(r.exitCode, 64);
      expect(r.stderr, contains('Unknown flag: --release-pr'));
      expect(r.stdout, contains('Syncs ^version constraints'));
    });

    test('missing --check/--write exits 64', () async {
      final r = await _runTool('sync_workspace_pub_constraints.dart', []);
      expect(r.exitCode, 64);
      expect(r.stderr, contains('Pass --check or --write'));
    });
  });
}
