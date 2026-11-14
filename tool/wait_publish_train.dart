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
    stdout.writeln('No release tags; skipping publish waits');
    exit(await _runStrictPostPublishAudit());
  }

  final env = {...Platform.environment, 'GH_TOKEN': token};
  final results = <String, String>{};

  for (final tag in tags) {
    stdout.writeln('Waiting for publish_package.yml on $tag …');
    var watched = await _waitForDispatchRun(
      repo: repo,
      tag: tag,
      env: env,
      afterRedispatch: false,
    );
    if (watched == null) {
      results[tag] = 'unknown';
      continue;
    }

    var conclusion = await _conclusionForRun(repo, watched.databaseId, env);
    var jobs = await _jobsForRun(repo, watched.databaseId, env);

    if (shouldRetryPublishWorkflow(
      workflowConclusion: conclusion,
      workflowStatus: 'completed',
      jobs: jobs,
    )) {
      stdout.writeln(
        'Retrying publish for $tag (publish job failed, run=${watched.databaseId})',
      );
      final failedRunId = watched.databaseId;
      final redispatchAt = DateTime.now().toUtc();
      final redispatch = await Process.run(
        'gh',
        [
          'workflow',
          'run',
          'publish_package.yml',
          '--repo',
          repo,
          '--ref',
          tag,
        ],
        environment: env,
      );
      if (redispatch.exitCode != 0) {
        stderr.writeln('::error::re-dispatch failed for $tag');
        stderr.write(redispatch.stderr);
        exit(1);
      }
      watched = await _waitForDispatchRun(
        repo: repo,
        tag: tag,
        env: env,
        afterRedispatch: true,
        dispatchedAfter: redispatchAt,
        excludeRunId: failedRunId,
      );
      if (watched == null) {
        results[tag] = 'unknown';
        continue;
      }
      conclusion = await _conclusionForRun(repo, watched.databaseId, env);
    }

    results[tag] = conclusion ?? 'unknown';
    if (conclusion != 'success') {
      stderr.writeln(
        '::error::publish failed for $tag (conclusion=$conclusion)',
      );
    }
  }

  stdout.writeln('Per-package publish results:');
  for (final entry in results.entries) {
    stdout.writeln('  ${entry.key}: ${entry.value}');
  }

  if (results.values.any((c) => c != 'success')) {
    exit(1);
  }

  exit(await _runStrictPostPublishAudit());
}

Future<int> _runStrictPostPublishAudit() async {
  stdout.writeln(
    'Running strict post-publish audit (main mode; broken pub.dev latest = error) …',
  );
  final audit = await Process.run('dart', strictPostPublishAuditArgs);
  stdout.write(audit.stdout);
  stderr.write(audit.stderr);
  return audit.exitCode;
}

Future<GhWorkflowRun?> _waitForDispatchRun({
  required String repo,
  required String tag,
  required Map<String, String> env,
  required bool afterRedispatch,
  DateTime? dispatchedAfter,
  int? excludeRunId,
}) async {
  final deadline = DateTime.now().add(defaultDispatchRunDiscoveryTimeout);
  while (DateTime.now().isBefore(deadline)) {
    final list = await _listDispatchRuns(repo, tag, env);
    if (list.exitCode != 0) {
      stderr.write(list.stderr);
      return null;
    }
    final runs = parseGhWorkflowRunList(list.stdout as String);
    final GhWorkflowRun? selected = afterRedispatch
        ? selectNewDispatchRun(
            runs: runs,
            dispatchedAfter: dispatchedAfter!,
            excludeRunId: excludeRunId,
          )
        : selectLatestDispatchRun(runs: runs);
    if (selected != null) {
      await Process.run(
        'gh',
        [
          'run',
          'watch',
          '${selected.databaseId}',
          '--repo',
          repo,
          '--exit-status',
        ],
        environment: env,
      );
      return selected;
    }
    await Future<void>.delayed(const Duration(seconds: 15));
  }
  stderr.writeln(
    '::error::No workflow_dispatch publish run for $tag within '
    '${defaultDispatchRunDiscoveryTimeout.inMinutes} minutes '
    '(afterRedispatch=$afterRedispatch, excluded run: ${excludeRunId ?? 'none'})',
  );
  return null;
}

Future<ProcessResult> _listDispatchRuns(
  String repo,
  String tag,
  Map<String, String> env,
) {
  return Process.run(
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
      '--event',
      'workflow_dispatch',
      '--json',
      'databaseId,createdAt,status,conclusion,event',
      '--limit',
      '20',
    ],
    environment: env,
  );
}

Future<String?> _conclusionForRun(
  String repo,
  int runId,
  Map<String, String> env,
) async {
  final view = await Process.run(
    'gh',
    [
      'run',
      'view',
      '$runId',
      '--repo',
      repo,
      '--json',
      'conclusion,status',
    ],
    environment: env,
  );
  if (view.exitCode != 0) {
    return null;
  }
  final decoded = jsonDecode(view.stdout as String) as Map<String, dynamic>;
  return decoded['conclusion'] as String?;
}

Future<List<GhWorkflowJob>> _jobsForRun(
  String repo,
  int runId,
  Map<String, String> env,
) async {
  final view = await Process.run(
    'gh',
    [
      'run',
      'view',
      '$runId',
      '--repo',
      repo,
      '--json',
      'jobs',
    ],
    environment: env,
  );
  if (view.exitCode != 0) {
    return [];
  }
  return parseGhWorkflowJobs(view.stdout as String);
}
