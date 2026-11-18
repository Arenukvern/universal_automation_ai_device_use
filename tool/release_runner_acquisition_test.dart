import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'release_runner_acquisition_lib.dart';

void main() {
  group('jobLooksLikeRunnerNotAcquired', () {
    test('annotation not acquired by Runner (primary signal)', () {
      final job = <String, dynamic>{
        'conclusion': 'cancelled',
        'steps': <dynamic>[],
        'runner_id': null,
        'runner_name': null,
        'created_at': '2026-01-01T00:00:00Z',
        'completed_at': '2026-01-01T00:01:00Z',
      };
      final annotations = [
        {
          'message':
              'The job was not acquired by Runner of type hosted even after multiple attempts',
        },
      ];
      expect(jobLooksLikeRunnerNotAcquired(job, annotations), isTrue);
    });

    test('zero steps without runner after long queue (no annotation)', () {
      final job = <String, dynamic>{
        'conclusion': 'failure',
        'steps': <dynamic>[],
        'runner_id': 0,
        'runner_name': '',
        'created_at': '2026-01-01T00:00:00Z',
        'completed_at': '2026-01-01T00:11:01Z',
      };
      expect(jobLooksLikeRunnerNotAcquired(job, const []), isTrue);
    });

    test('zero steps short queue without annotation is not acquisition loss', () {
      final job = <String, dynamic>{
        'conclusion': 'cancelled',
        'steps': <dynamic>[],
        'runner_id': 0,
        'runner_name': '',
        'created_at': '2026-01-01T00:00:00Z',
        'completed_at': '2026-01-01T00:02:00Z',
      };
      expect(jobLooksLikeRunnerNotAcquired(job, const []), isFalse);
    });

    test('real failure with steps', () {
      final job = <String, dynamic>{
        'conclusion': 'failure',
        'steps': [
          {'name': 'Run tests', 'conclusion': 'failure'},
        ],
        'runner_id': 42,
        'runner_name': 'GitHub Actions 1',
      };
      expect(jobLooksLikeRunnerNotAcquired(job, const []), isFalse);
    });
  });

  group('isRunSupersededOnRef', () {
    test('fixture: superseded_run', () {
      final fixture = _loadFixture('superseded_run.json');
      expect(
        isRunSupersededOnRef(
          triggerRunId: fixture.runId!,
          triggerRunCreatedAt: fixture.runCreatedAt!,
          siblingRunsOnRef: fixture.siblingRunsOnRef!,
        ),
        isTrue,
      );
    });
  });

  group('resolveReleaseTagFromWorkflowRun', () {
    test('dispatch run name yields toolkit tag', () {
      expect(
        resolveReleaseTagFromWorkflowRun(
          run: {
            'event': 'workflow_dispatch',
            'head_branch': 'main',
            'display_title': 'Release binaries',
            'name': 'release-binaries universal_automation_toolkit-v0.6.2',
          },
        ),
        'universal_automation_toolkit-v0.6.2',
      );
    });

    test('push resolves tag via head_sha and matching refs (annotated peel)', () {
      expect(
        resolveReleaseTagFromWorkflowRun(
          run: {
            'event': 'push',
            'head_branch': 'main',
            'head_sha': 'c476b70d8686d649922af477c8dcc56b2ef2477c',
            'display_title':
                'fix(universal_automation_toolkit): document 0.6.2+ GitHub binaries',
          },
          matchingToolkitTagRefs: [
            {
              'ref': 'refs/tags/universal_automation_toolkit-v0.6.2',
              'object': {
                'type': 'tag',
                'sha': 'annotated_tag_object_sha_062',
              },
            },
          ],
          peeledTagCommits: const {
            'annotated_tag_object_sha_062':
                'c476b70d8686d649922af477c8dcc56b2ef2477c',
          },
        ),
        'universal_automation_toolkit-v0.6.2',
      );
    });

    test('push ignores display_title when head_sha has no matching tag', () {
      expect(
        resolveReleaseTagFromWorkflowRun(
          run: {
            'event': 'push',
            'head_branch': 'main',
            'head_sha': 'deadbeef',
            'display_title': 'mentions universal_automation_toolkit-v9.9.9',
          },
          matchingToolkitTagRefs: const [],
        ),
        isNull,
      );
    });
  });

  group('binaryReleaseJobLegName', () {
    test('classifies reusable-workflow job legs', () {
      expect(
        jobIsBinaryReleaseLeg(
          'release-binaries-build / build (darwin-arm64, macos-15)',
        ),
        isTrue,
      );
      expect(
        jobIsBinaryReleaseLeg('release-binaries-build / prepare'),
        isTrue,
      );
      expect(
        jobIsBinaryReleaseLeg('release-binaries-publish / publish'),
        isTrue,
      );
      expect(
        jobIsBinaryReleaseLeg('release-runner-retry / maybe-retry'),
        isFalse,
      );
    });
  });

  group('toolkitTagRecoveryEligibility', () {
    test('draft release is incomplete', () {
      expect(
        toolkitTagRecoveryEligibility(
          releaseTag: 'universal_automation_toolkit-v0.6.2',
          releaseView: const {'isDraft': true, 'assets': []},
        ),
        ToolkitTagRecoveryEligibility.incomplete,
      );
    });

    test('published with all assets is complete', () {
      expect(
        toolkitTagRecoveryEligibility(
          releaseTag: 'universal_automation_toolkit-v0.6.2',
          releaseView: {
            'isDraft': false,
            'assets': [
              {'name': 'universal_automation_0.6.2_darwin-arm64.tar.gz'},
              {'name': 'universal_automation_0.6.2_darwin-x64.tar.gz'},
              {'name': 'universal_automation_0.6.2_linux-x64.tar.gz'},
              {'name': 'universal_automation_0.6.2_windows-x64.zip'},
              {'name': 'checksums.txt'},
            ],
          },
        ),
        ToolkitTagRecoveryEligibility.complete,
      );
    });
  });

  group('classifyRunnerAcquisitionRetry', () {
    RunnerAcquisitionRetryDecision classify(_Fixture fixture, {int attempt = 1}) {
      return classifyRunnerAcquisitionRetry(
        jobs: fixture.jobs,
        annotationsByJobId: fixture.annotationsByJobId,
        runAttempt: attempt,
        triggerRunId: fixture.runId,
        triggerRunCreatedAt: fixture.runCreatedAt,
        siblingRunsOnRef: fixture.siblingRunsOnRef,
        tagRecoveryEligibility: _tagRecoveryFromFixture(fixture),
      );
    }

    RunnerAcquisitionRetryDecision classifyWithResolvedTag(
      _Fixture fixture, {
      int attempt = 1,
    }) {
      final releaseTag = resolveReleaseTagFromWorkflowRun(
        run: fixture.workflowRun,
        matchingToolkitTagRefs: fixture.matchingToolkitTagRefs,
        peeledTagCommits: fixture.peeledTagCommits,
      );
      final recovery = toolkitTagRecoveryEligibility(
        releaseTag: releaseTag,
        releaseView: fixture.releaseView,
      );
      return classifyRunnerAcquisitionRetry(
        jobs: fixture.jobs,
        annotationsByJobId: fixture.annotationsByJobId,
        runAttempt: attempt,
        triggerRunId: fixture.runId,
        triggerRunCreatedAt: fixture.runCreatedAt,
        siblingRunsOnRef: fixture.siblingRunsOnRef,
        tagRecoveryEligibility: recovery,
      );
    }

    test('fixture: not-acquired cancelled', () {
      expect(classify(_loadFixture('not_acquired_cancelled.json')),
          RunnerAcquisitionRetryDecision.rerunFailedJobs);
    });

    test('fixture: zero-step unassigned (>=10m queue)', () {
      expect(classify(_loadFixture('zero_step_unassigned.json')),
          RunnerAcquisitionRetryDecision.rerunFailedJobs);
    });

    test('fixture: real build failure', () {
      expect(classify(_loadFixture('real_build_failure.json')),
          RunnerAcquisitionRetryDecision.nonAcquisitionFailure);
    });

    test('fixture: mixed acquisition and real failure', () {
      expect(classify(_loadFixture('mixed_failures.json')),
          RunnerAcquisitionRetryDecision.nonAcquisitionFailure);
    });

    test('fixture: concurrency cancel short queue', () {
      expect(classify(_loadFixture('concurrency_cancel_short.json')),
          RunnerAcquisitionRetryDecision.nonAcquisitionFailure);
    });

    test('fixture: manual cancel short queue', () {
      expect(classify(_loadFixture('manual_cancel_short.json')),
          RunnerAcquisitionRetryDecision.nonAcquisitionFailure);
    });

    test('fixture: superseded run with non-binary failed job', () {
      expect(classify(_loadFixture('superseded_run.json')),
          RunnerAcquisitionRetryDecision.supersededRun);
    });

    test('Release Please push: tag resolve + incomplete assets reruns', () {
      final fixture =
          _loadFixture('release_please_push_incomplete_superseded.json');
      final tag = resolveReleaseTagFromWorkflowRun(
        run: fixture.workflowRun,
        matchingToolkitTagRefs: fixture.matchingToolkitTagRefs,
        peeledTagCommits: fixture.peeledTagCommits,
      );
      expect(tag, 'universal_automation_toolkit-v0.6.2');
      expect(
        classifyWithResolvedTag(fixture),
        RunnerAcquisitionRetryDecision.rerunFailedJobs,
      );
    });

    test('tag-scoped: binaries-only + newer run + incomplete tag reruns', () {
      expect(
        classifyWithResolvedTag(
          _loadFixture('tag_scoped_binaries_incomplete_superseded.json'),
        ),
        RunnerAcquisitionRetryDecision.rerunFailedJobs,
      );
    });

    test('tag-scoped: binaries-only + complete published tag skips', () {
      expect(
        classifyWithResolvedTag(
          _loadFixture('tag_scoped_binaries_complete_superseded.json'),
        ),
        RunnerAcquisitionRetryDecision.releaseTagAlreadyComplete,
      );
    });

    test('mixed failure with newer run skips (non-acquisition)', () {
      expect(
        classifyWithResolvedTag(
          _loadFixture('mixed_failures_superseded.json'),
        ),
        RunnerAcquisitionRetryDecision.nonAcquisitionFailure,
      );
    });

    test('attempt cap blocks retry', () {
      final fixture = _loadFixture('not_acquired_cancelled.json');
      expect(
        classify(fixture, attempt: 3),
        RunnerAcquisitionRetryDecision.attemptCapReached,
      );
    });

    test('fixture: mcp_flutter run 44166682686 darwin-arm64 not acquired', () {
      final fixture = _loadFixture('run_44166682686.json');
      expect(fixture.runConclusion, 'failure');
      final darwin = fixture.jobs.firstWhere(
        (j) => (j['name'] as String?)?.contains('darwin-arm64') ?? false,
      );
      expect(darwin['id'], 134334621644);
      expect(darwin['conclusion'], 'cancelled');
      expect(darwin['steps'], isEmpty);
      expect(darwin['runner_id'], 0);
      expect(darwin['runner_name'], '');
      final queue = jobQueueDuration(darwin);
      expect(queue, isNotNull);
      expect(queue!.inSeconds, greaterThanOrEqualTo(minRunnerAcquisitionQueueSeconds));
      expect(classify(fixture), RunnerAcquisitionRetryDecision.rerunFailedJobs);
    });
  });
}

ToolkitTagRecoveryEligibility? _tagRecoveryFromFixture(_Fixture fixture) {
  if (fixture.tagRecoveryEligibility != null) {
    return fixture.tagRecoveryEligibility;
  }
  if (fixture.workflowRun != null) {
    final tag = resolveReleaseTagFromWorkflowRun(
      run: fixture.workflowRun,
      matchingToolkitTagRefs: fixture.matchingToolkitTagRefs,
      peeledTagCommits: fixture.peeledTagCommits,
    );
    return toolkitTagRecoveryEligibility(
      releaseTag: tag,
      releaseView: fixture.releaseView,
    );
  }
  return null;
}

class _Fixture {
  _Fixture(
    this.jobs,
    this.annotationsByJobId, {
    this.runConclusion,
    this.runId,
    this.runCreatedAt,
    this.siblingRunsOnRef,
    this.tagRecoveryEligibility,
    this.workflowRun,
    this.matchingToolkitTagRefs,
    this.peeledTagCommits = const {},
    this.releaseView,
  });
  final List<Map<String, dynamic>> jobs;
  final Map<int, List<Map<String, dynamic>>> annotationsByJobId;
  final String? runConclusion;
  final int? runId;
  final DateTime? runCreatedAt;
  final List<Map<String, dynamic>>? siblingRunsOnRef;
  final ToolkitTagRecoveryEligibility? tagRecoveryEligibility;
  final Map<String, dynamic>? workflowRun;
  final List<Map<String, dynamic>>? matchingToolkitTagRefs;
  final Map<String, String> peeledTagCommits;
  final Map<String, dynamic>? releaseView;
}

_Fixture _loadFixture(String name) {
  final path =
      '${Directory.current.path}/tool/contracts/fixtures/release_runner_acquisition/$name';
  final file = File(path);
  final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final jobs = (root['jobs'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  final ann = <int, List<Map<String, dynamic>>>{};
  final raw = root['annotations_by_job_id'] as Map<String, dynamic>? ?? {};
  for (final entry in raw.entries) {
    final id = int.parse(entry.key);
    final list = (entry.value as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    ann[id] = list;
  }
  DateTime? runCreatedAt;
  final createdRaw = root['run_created_at'] as String?;
  if (createdRaw != null) {
    runCreatedAt = DateTime.parse(createdRaw).toUtc();
  }
  List<Map<String, dynamic>>? siblings;
  final rawSiblings = root['sibling_runs_on_ref'];
  if (rawSiblings is List) {
    siblings = rawSiblings
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
  ToolkitTagRecoveryEligibility? tagRecovery;
  final tagRaw = root['tag_recovery_eligibility'] as String?;
  if (tagRaw == 'incomplete') {
    tagRecovery = ToolkitTagRecoveryEligibility.incomplete;
  } else if (tagRaw == 'complete') {
    tagRecovery = ToolkitTagRecoveryEligibility.complete;
  }
  Map<String, dynamic>? workflowRun;
  final rawRun = root['workflow_run'];
  if (rawRun is Map) {
    workflowRun = Map<String, dynamic>.from(rawRun);
  }
  List<Map<String, dynamic>>? matchingRefs;
  final rawRefs = root['matching_toolkit_tag_refs'];
  if (rawRefs is List) {
    matchingRefs =
        rawRefs.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  final peeled = <String, String>{};
  final rawPeeled = root['peeled_tag_commits'] as Map<String, dynamic>? ?? {};
  for (final entry in rawPeeled.entries) {
    peeled[entry.key] = entry.value.toString();
  }
  Map<String, dynamic>? releaseView;
  if (root.containsKey('release_view')) {
    final rawView = root['release_view'];
    if (rawView is Map) {
      releaseView = Map<String, dynamic>.from(rawView);
    }
  }
  return _Fixture(
    jobs,
    ann,
    runConclusion: root['run_conclusion'] as String?,
    runId: root['run_id'] as int?,
    runCreatedAt: runCreatedAt,
    siblingRunsOnRef: siblings,
    tagRecoveryEligibility: tagRecovery,
    workflowRun: workflowRun,
    matchingToolkitTagRefs: matchingRefs,
    peeledTagCommits: peeled,
    releaseView: releaseView,
  );
}