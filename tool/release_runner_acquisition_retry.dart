// Classify a completed workflow run and optionally rerun failed jobs when
// every failure was a hosted runner acquisition loss.
//
// Env: GITHUB_REPOSITORY, RUN_ID, RUN_ATTEMPT, GH_TOKEN,
//      WORKFLOW_ID, HEAD_BRANCH, RUN_CREATED_AT
// Optional: RETRY_BACKOFF_SECONDS (default 180), MAX_RUN_ATTEMPT (default 3)

import 'dart:convert';
import 'dart:io';

import 'release_runner_acquisition_lib.dart';

Future<void> main(List<String> args) async {
  final repo = Platform.environment['GITHUB_REPOSITORY'] ?? '';
  final runIdRaw = Platform.environment['RUN_ID'] ?? '';
  final runAttemptRaw = Platform.environment['RUN_ATTEMPT'] ?? '';
  final token = Platform.environment['GH_TOKEN'] ?? '';
  final workflowId = Platform.environment['WORKFLOW_ID'] ?? '';
  final headBranch = Platform.environment['HEAD_BRANCH'] ?? '';
  final runCreatedAtRaw = Platform.environment['RUN_CREATED_AT'] ?? '';

  if (repo.isEmpty || runIdRaw.isEmpty || runAttemptRaw.isEmpty || token.isEmpty) {
    stderr.writeln(
      'release_runner_acquisition_retry: need GITHUB_REPOSITORY, RUN_ID, '
      'RUN_ATTEMPT, GH_TOKEN',
    );
    exit(2);
  }

  final runId = int.tryParse(runIdRaw);
  if (runId == null) {
    stderr.writeln('release_runner_acquisition_retry: invalid RUN_ID');
    exit(2);
  }

  final runAttempt = int.tryParse(runAttemptRaw);
  if (runAttempt == null) {
    stderr.writeln('release_runner_acquisition_retry: invalid RUN_ATTEMPT');
    exit(2);
  }

  final maxAttempt =
      int.tryParse(Platform.environment['MAX_RUN_ATTEMPT'] ?? '') ?? 3;
  final backoff = int.tryParse(Platform.environment['RETRY_BACKOFF_SECONDS'] ?? '') ?? 180;

  DateTime? runCreatedAt;
  if (runCreatedAtRaw.isNotEmpty) {
    try {
      runCreatedAt = DateTime.parse(runCreatedAtRaw).toUtc();
    } catch (_) {
      stderr.writeln('release_runner_acquisition_retry: invalid RUN_CREATED_AT');
      exit(2);
    }
  }

  final runMeta = await _fetchWorkflowRun(repo, runIdRaw, token);
  final releaseTag = await _resolveReleaseTag(repo, runMeta, token);
  ToolkitTagRecoveryEligibility? tagRecovery;
  if (releaseTag != null) {
    final releaseView = await _fetchReleaseView(repo, releaseTag, token);
    tagRecovery = toolkitTagRecoveryEligibility(
      releaseTag: releaseTag,
      releaseView: releaseView,
    );
  }

  final jobs = await _listJobs(repo, runIdRaw, token);
  final annotationsByJobId = await _loadAnnotations(repo, jobs, token);

  List<Map<String, dynamic>>? siblingRuns;
  if (workflowId.isNotEmpty && headBranch.isNotEmpty && runCreatedAt != null) {
    siblingRuns = await _listSiblingRuns(
      repo: repo,
      workflowId: workflowId,
      headBranch: headBranch,
      token: token,
    );
  }

  final decision = classifyRunnerAcquisitionRetry(
    jobs: jobs,
    annotationsByJobId: annotationsByJobId,
    runAttempt: runAttempt,
    maxRunAttempt: maxAttempt,
    triggerRunId: runCreatedAt != null ? runId : null,
    triggerRunCreatedAt: runCreatedAt,
    siblingRunsOnRef: siblingRuns,
    tagRecoveryEligibility: tagRecovery,
  );

  final summary = StringBuffer()
    ..writeln('## Release runner acquisition retry')
    ..writeln()
    ..writeln(retryDecisionSummary(decision))
    ..writeln()
    ..writeln('Workflow run: `$runIdRaw` attempt $runAttempt on `$repo`.')
    ..writeln(
      'Failed/cancelled jobs: '
      '${jobs.where(jobIsFailedOrCancelled).map((j) => j['name']).join(', ')}',
    );
  if (releaseTag != null) {
    summary.writeln('Toolkit release tag: `$releaseTag`.');
    if (tagRecovery != null) {
      summary.writeln('Tag recovery eligibility: `${tagRecovery.name}`.');
    }
  }
  if (siblingRuns != null) {
    summary.writeln(
      'Sibling runs on ref `$headBranch`: ${siblingRuns.length} listed.',
    );
  }

  await _writeStepSummary(summary.toString());
  stdout.writeln(summary.toString());

  if (decision != RunnerAcquisitionRetryDecision.rerunFailedJobs) {
    ok('no rerun');
    return;
  }

  stdout.writeln('Backing off ${backoff}s before rerun…');
  await Future<void>.delayed(Duration(seconds: backoff));

  final rerun = await Process.run(
    'gh',
    [
      'run',
      'rerun',
      runIdRaw,
      '--repo',
      repo,
      '--failed',
    ],
    environment: {'GH_TOKEN': token},
    runInShell: false,
  );
  if (rerun.exitCode != 0) {
    stderr.writeln(rerun.stderr);
    fail('gh run rerun failed (exit ${rerun.exitCode})');
  }
  ok('dispatched gh run rerun --failed for $runIdRaw');
}

Future<String?> _resolveReleaseTag(
  String repo,
  Map<String, dynamic>? run,
  String token,
) async {
  if (run == null) {
    return null;
  }
  final event = run['event']?.toString() ?? '';
  final headSha = run['head_sha']?.toString();
  if (event == 'workflow_dispatch') {
    return resolveReleaseTagFromWorkflowRun(run: run);
  }

  if (headSha != null && headSha.isNotEmpty) {
    final lookup = await _matchingToolkitTagRefs(repo, token);
    if (tagLookupFallsBackToPerRefSkip(
      event: event,
      headSha: headSha,
      lookupFailed: lookup.failed,
      matchingRefCount: lookup.refs.length,
    )) {
      stdout.writeln(toolkitTagLookupFallbackLogLine);
    }
    if (lookup.failed || lookup.refs.isEmpty) {
      return null;
    }
    final pushTag = await resolvePushToolkitTagWithPeel(
      headSha: headSha,
      matchingTagRefs: lookup.refs,
      peelAnnotatedTag: (tagSha) => _peelAnnotatedTag(repo, tagSha, token),
    );
    if (pushTag != null) {
      return pushTag;
    }
  }

  return resolveReleaseTagFromWorkflowRun(
    run: run,
    matchingToolkitTagRefs: const [],
  );
}

void ok(String message) => stdout.writeln('release_runner_acquisition_retry: $message');

void fail(String message) {
  stderr.writeln('release_runner_acquisition_retry: $message');
  exit(1);
}

Future<void> _writeStepSummary(String markdown) async {
  final path = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (path == null || path.isEmpty) {
    return;
  }
  await File(path).writeAsString(markdown, mode: FileMode.append);
}

Future<Map<String, dynamic>?> _fetchWorkflowRun(
  String repo,
  String runId,
  String token,
) async {
  final result = await Process.run(
    'gh',
    [
      'api',
      'repos/$repo/actions/runs/$runId',
    ],
    environment: {'GH_TOKEN': token},
    runInShell: false,
  );
  if (result.exitCode != 0) {
    stderr.writeln(result.stderr);
    return null;
  }
  final decoded = jsonDecode(result.stdout.toString());
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  return null;
}

/// With `contents: read` only, `gh release view` cannot see draft releases — the
/// call fails and we treat the tag as [ToolkitTagRecoveryEligibility.incomplete]
/// so the run is retried. That fail-open behavior is intentional because publish
/// is idempotent.
Future<Map<String, dynamic>?> _fetchReleaseView(
  String repo,
  String tag,
  String token,
) async {
  final result = await Process.run(
    'gh',
    [
      'release',
      'view',
      tag,
      '--repo',
      repo,
      '--json',
      'isDraft,assets',
    ],
    environment: {'GH_TOKEN': token},
    runInShell: false,
  );
  if (result.exitCode != 0) {
    return null;
  }
  final decoded = jsonDecode(result.stdout.toString());
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  return null;
}

class _ToolkitTagRefsLookup {
  const _ToolkitTagRefsLookup({required this.refs, required this.failed});

  final List<Map<String, dynamic>> refs;
  final bool failed;
}

Future<_ToolkitTagRefsLookup> _matchingToolkitTagRefs(
  String repo,
  String token,
) async {
  // `--slurp` merges paginated ref pages into one JSON array; without it each
  // page is a separate document and matching-refs would be truncated.
  final result = await Process.run(
    'gh',
    [
      'api',
      'repos/$repo/git/matching-refs/tags/universal_automation_toolkit-v',
      '--paginate',
      '--slurp',
    ],
    environment: {'GH_TOKEN': token},
    runInShell: false,
  );
  if (result.exitCode != 0) {
    stderr.writeln(result.stderr);
    return const _ToolkitTagRefsLookup(refs: [], failed: true);
  }
  final body = result.stdout.toString().trim();
  if (body.isEmpty) {
    return const _ToolkitTagRefsLookup(refs: [], failed: false);
  }
  final decoded = jsonDecode(body);
  final refs = parseMatchingToolkitTagRefsJson(decoded);
  return _ToolkitTagRefsLookup(refs: refs, failed: false);
}

Future<String?> _peelAnnotatedTag(
  String repo,
  String tagObjectSha,
  String token,
) async {
  final result = await Process.run(
    'gh',
    [
      'api',
      'repos/$repo/git/tags/$tagObjectSha',
    ],
    environment: {'GH_TOKEN': token},
    runInShell: false,
  );
  if (result.exitCode != 0) {
    return null;
  }
  final decoded = jsonDecode(result.stdout.toString());
  if (decoded is Map<String, dynamic>) {
    final target = decoded['object'];
    if (target is Map && target['sha'] is String) {
      return target['sha'] as String;
    }
  }
  return null;
}

Future<List<Map<String, dynamic>>> _listSiblingRuns({
  required String repo,
  required String workflowId,
  required String headBranch,
  required String token,
}) async {
  final result = await Process.run(
    'gh',
    [
      'api',
      'repos/$repo/actions/workflows/$workflowId/runs',
      '-f',
      'branch=$headBranch',
      '-f',
      'per_page=30',
    ],
    environment: {'GH_TOKEN': token},
    runInShell: false,
  );
  if (result.exitCode != 0) {
    stderr.writeln(result.stderr);
    fail('gh api list workflow runs failed (exit ${result.exitCode})');
  }

  final decoded = jsonDecode(result.stdout.toString());
  if (decoded is! Map<String, dynamic>) {
    return const [];
  }
  final runs = decoded['workflow_runs'];
  if (runs is! List) {
    return const [];
  }
  return runs
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

Future<List<Map<String, dynamic>>> _listJobs(
  String repo,
  String runId,
  String token,
) async {
  final result = await Process.run(
    'gh',
    [
      'api',
      'repos/$repo/actions/runs/$runId/jobs',
      '--paginate',
    ],
    environment: {'GH_TOKEN': token},
    runInShell: false,
  );
  if (result.exitCode != 0) {
    stderr.writeln(result.stderr);
    fail('gh api jobs failed (exit ${result.exitCode})');
  }

  final jobs = <Map<String, dynamic>>[];
  for (final line in result.stdout.toString().split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) {
      continue;
    }
    final batch = decoded['jobs'];
    if (batch is List) {
      for (final job in batch) {
        if (job is Map<String, dynamic>) {
          jobs.add(job);
        }
      }
    }
  }
  return jobs;
}

Future<Map<int, List<Map<String, dynamic>>>> _loadAnnotations(
  String repo,
  List<Map<String, dynamic>> jobs,
  String token,
) async {
  final out = <int, List<Map<String, dynamic>>>{};
  for (final job in jobs) {
    if (!jobIsFailedOrCancelled(job)) {
      continue;
    }
    final rawId = job['id'];
    if (rawId is! int) {
      continue;
    }
    final result = await Process.run(
      'gh',
      [
        'api',
        'repos/$repo/check-runs/$rawId/annotations',
      ],
      environment: {'GH_TOKEN': token},
      runInShell: false,
    );
    if (result.exitCode != 0) {
      stderr.writeln(result.stderr);
      fail('gh api annotations for job $rawId failed');
    }
    final decoded = jsonDecode(result.stdout.toString());
    if (decoded is List) {
      out[rawId] = decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } else {
      out[rawId] = const [];
    }
  }
  return out;
}