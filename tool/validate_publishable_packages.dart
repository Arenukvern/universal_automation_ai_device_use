// Runs `dart analyze` and `dart test` for every package in publish_order.yaml
// (same surface publish_package.yml exercises before publish).

import 'dart:io';

import 'hosted_deps_resolve_lib.dart';
import 'workspace_pub_constraints_sync.dart';

Future<void> main(List<String> args) async {
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
      continue;
    }
    final test = await Process.run(
      'dart',
      ['test', '--concurrency=1'],
      workingDirectory: dir.path,
    );
    if (test.exitCode != 0) {
      stderr.write(test.stdout);
      stderr.write(test.stderr);
      failures++;
    }
  }
  if (failures > 0) {
    stderr.writeln('$failures publishable package(s) failed analyze/test');
    exit(1);
  }
  stdout.writeln('All ${names.length} publishable packages passed analyze/test.');
}
