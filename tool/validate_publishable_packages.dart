// Runs `dart analyze` and `dart test` for every package in publish_order.yaml
// (same surface publish_package.yml exercises before publish).
//
// Release-please CI also runs `dart pub publish --dry-run` per package (workspace
// resolution after root pub get) and fails on exit 65 warnings.

import 'dart:io';

import 'hosted_deps_resolve_lib.dart';
import 'publish_dry_run_lib.dart';
import 'workspace_pub_constraints_sync.dart';

Future<void> main(List<String> args) async {
  final dryRunGate = args.contains('--dry-run-gate');
  final repoRoot = findWorkspaceRepoRoot();
  final rootResolve = await Process.run(
    'dart',
    ['pub', 'get'],
    workingDirectory: repoRoot.path,
  );
  if (rootResolve.exitCode != 0) {
    stderr.write(rootResolve.stderr);
    exit(1);
  }
  final orderPath = '${repoRoot.path}/tool/publish_order.yaml';
  final names = loadPublishOrderYaml(orderPath);
  final packages = loadWorkspacePackages(repoRoot);
  final byName = {for (final p in packages) p.name: p};

  var failures = 0;
  for (final name in names) {
    final pkg = byName[name];
    if (pkg == null) {
      stderr.writeln('::error::publish_order references missing package $name');
      failures++;
      continue;
    }
    final dir = File(pkg.pubspecPath).parent;
    stdout.writeln('=== $name (${dir.path}) ===');
    final analyze = await Process.run(
      'dart',
      ['analyze'],
      workingDirectory: dir.path,
    );
    if (analyze.exitCode != 0) {
      stderr.write(analyze.stdout);
      stderr.write(analyze.stderr);
      failures++;
      continue;
    }
    final testDir = Directory('${dir.path}/test');
    if (!testDir.existsSync()) {
      stdout.writeln('No test/; skipping tests for $name');
    } else {
      final test = await Process.run(
        'dart',
        ['test', '--concurrency=1'],
        workingDirectory: dir.path,
      );
      if (test.exitCode != 0) {
        stderr.write(test.stdout);
        stderr.write(test.stderr);
        failures++;
        continue;
      }
    }
    if (dryRunGate) {
      final dryRun = await Process.run(
        'dart',
        ['pub', 'publish', '--dry-run'],
        workingDirectory: dir.path,
      );
      if (publishDryRunGateFailed(dryRun.exitCode)) {
        stderr.write(
          formatPublishDryRunGateFailure(
            packageName: name,
            exitCode: dryRun.exitCode,
            combinedOutput: '${dryRun.stdout}${dryRun.stderr}',
          ),
        );
        failures++;
      }
    }
  }
  if (failures > 0) {
    stderr.writeln('$failures publishable package(s) failed analyze/test/dry-run');
    exit(1);
  }
  final verbs = dryRunGate ? 'analyze/test/dry-run' : 'analyze/test';
  stdout.writeln('All ${names.length} publishable packages passed $verbs.');
}