// Waits for publish_package.yml runs dispatched for a release train, retries
// once per failed tag when retryable, then blocks on post-publish audit.
//
// Env: RELEASE_PLEASE_OUTPUTS (JSON), GH_TOKEN, GH_REPO

import 'dart:convert';
import 'dart:io';

import 'wait_publish_train_lib.dart';

Future<void> main() async {
  final raw = Platform.environment['RELEASE_PLEASE_OUTPUTS'];
  final repo = Platform.environment['GH_REPO'];
  final token = Platform.environment['GH_TOKEN'];
  if (raw == null || repo == null || token == null) {
    stderr.writeln('RELEASE_PLEASE_OUTPUTS, GH_REPO, GH_TOKEN required');
    exit(2);
  }

  final outputs = jsonDecode(raw) as Map<String, dynamic>;
  final tags = releasePleasePublishTags(outputs: outputs);
  if (tags.isEmpty) {
    stdout.writeln('No release tags; skipping publish train wait');
    exit(0);
  }

  final env = {...Platform.environment, 'GH_TOKEN': token};
  final results = <String, String>{};

  for (final tag in tags) {
    stdout.writeln('Waiting for publish_package.yml on $tag …');
    var conclusion = await _waitLatestRun(repo, tag, env);
  if (isRetryablePublishFailure(conclusion, 'completed')) {
      stdout.writeln('Retrying publish for $tag (conclusion=$conclusion)');
      final redispatch = await Process.run(
        'gh',
        ['workflow', 'run', 'publish_package.yml', '--repo', repo, '--ref', tag],
        environment: env,
      );
      if (redispatch.exitCode != 0) {
        stderr.writeln('::error::re-dispatch failed for $tag');
        exit(1);
      }
      conclusion = await _waitLatestRun(repo, tag, env);
    }
    results[tag] = conclusion ?? 'unknown';
    if (conclusion != 'success') {
      stderr.writeln('::error::publish failed for $tag (conclusion=$conclusion)');
    }
  }

  stdout.writeln('Per-package publish results:');
  for (final entry in results.entries) {
    stdout.writeln('  ${entry.key}: ${entry.value}');
  }

  if (results.values.any((c) => c != 'success')) {
    exit(1);
  }

  stdout.writeln('Running post-publish audit …');
  final audit = await Process.run(
    'dart',
    ['run', 'tool/check_hosted_deps_resolve.dart', '--audit-published'],
  );
  stdout.write(audit.stdout);
  stderr.write(audit.stderr);
  exit(audit.exitCode);
}

Future<String?> _waitLatestRun(
  String repo,
  String tag,
  Map<String, String> env,
) async {
  final list = await Process.run(
    'gh',
    [
      'run',
      'list',
      '--repo',
      repo,
      '--workflow',
      'publish_package.yml',
      '--branch',
      tag,
      '--limit',
      '1',
      '--json',
      'databaseId,conclusion,status',
    ],
    environment: env,
  );
  if (list.exitCode != 0) {
    stderr.write(list.stderr);
    return null;
  }
  final runs = jsonDecode(list.stdout as String) as List<dynamic>;
  if (runs.isEmpty) {
    stderr.writeln('No publish run found yet for $tag; waiting briefly …');
    await Future<void>.delayed(const Duration(seconds: 15));
    return _waitLatestRun(repo, tag, env);
  }
  final id = (runs.first as Map<String, dynamic>)['databaseId'];
  final watch = await Process.run(
    'gh',
    ['run', 'watch', '$id', '--repo', repo, '--exit-status'],
    environment: env,
  );
  final after = await Process.run(
    'gh',
    [
      'run',
      'view',
      '$id',
      '--repo',
      repo,
      '--json',
      'conclusion',
    ],
    environment: env,
  );
  if (after.exitCode != 0) {
    return watch.exitCode == 0 ? 'success' : 'failure';
  }
  final decoded = jsonDecode(after.stdout as String) as Map<String, dynamic>;
  return decoded['conclusion'] as String?;
}
