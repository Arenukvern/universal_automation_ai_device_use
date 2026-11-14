import 'package:test/test.dart';

import 'release_workflow_contract_lib.dart';
import 'wait_publish_train_lib.dart';

void main() {
  group('releaseBinariesRunDiscovery', () {
    test('releaseBinariesRunListJsonFields omits inputs', () {
      expect(releaseBinariesRunListJsonFields, isNot(contains('inputs')));
      expect(releaseBinariesRunListJsonFields, contains('displayTitle'));
    });

    test('fields are subset of gh 2.103.0 allowlist', () {
      final errors = validateGhRunListJsonFieldAllowlist(
        releaseBinariesRunListJsonFields,
      );
      expect(errors, isEmpty, reason: errors.join('; '));
    });

    test('releaseTagFromDisplayTitle parses run-name', () {
      expect(
        releaseTagFromDisplayTitle(
          'release-binaries universal_automation_toolkit-v0.5.1',
        ),
        'universal_automation_toolkit-v0.5.1',
      );
      expect(releaseTagFromDisplayTitle('release-binaries '), isNull);
      expect(releaseTagFromDisplayTitle('other title'), isNull);
    });

    test('fixture list matches displayTitle filter', () {
      const json = '''
[
  {"databaseId": 10, "createdAt": "2026-01-01T12:00:00Z", "event": "workflow_dispatch", "displayTitle": "release-binaries universal_automation_toolkit-v1.0.0"},
  {"databaseId": 11, "createdAt": "2026-01-01T12:01:00Z", "event": "workflow_dispatch", "displayTitle": "release-binaries universal_automation_toolkit-v2.0.0"}
]
''';
      final runs = parseGhWorkflowRunList(json);
      final tag = 'universal_automation_toolkit-v2.0.0';
      GhWorkflowRun? match;
      for (final run in runs) {
        if (releaseTagFromDisplayTitle(run.displayTitle) == tag) {
          match = run;
          break;
        }
      }
      expect(match?.databaseId, 11);
    });
  });

  group('strictPostPublishAuditArgs', () {
    test('uses main-mode audit without --release-pr', () {
      expect(strictPostPublishAuditArgs, contains('--audit-published'));
      expect(strictPostPublishAuditArgs, isNot(contains('--release-pr')));
    });
  });

  group('releasePleasePublishTags', () {
    test('reads paths_released', () {
      final tags = releasePleasePublishTags(
        outputs: {
          'paths_released': '["pkgs/universal_foo"]',
          'pkgs/universal_foo--release_created': 'true',
          'pkgs/universal_foo--tag_name': 'universal_foo-v1.2.3',
        },
      );
      expect(tags, ['universal_foo-v1.2.3']);
    });

    test('multi-package train lists every release tag', () {
      final tags = releasePleasePublishTags(
        outputs: {
          'paths_released':
              '["pkgs/universal_foo","pkgs/universal_bar"]',
          'pkgs/universal_foo--release_created': 'true',
          'pkgs/universal_foo--tag_name': 'universal_foo-v1.0.0',
          'pkgs/universal_bar--release_created': 'true',
          'pkgs/universal_bar--tag_name': 'universal_bar-v2.0.0',
        },
      );
      expect(tags, ['universal_foo-v1.0.0', 'universal_bar-v2.0.0']);
    });
  });

  group('selectLatestDispatchRun', () {
    test('picks pre-existing run before waiter started (no time filter)', () {
      final beforeWaiter = DateTime.utc(2026, 1, 1, 10);
      final runs = [
        GhWorkflowRun(
          databaseId: 42,
          createdAt: beforeWaiter,
          event: 'workflow_dispatch',
          status: 'in_progress',
        ),
      ];
      expect(selectLatestDispatchRun(runs: runs)?.databaseId, 42);
    });

    test('newest id wins when multiple dispatch runs share a tag ref', () {
      final runs = [
        GhWorkflowRun(
          databaseId: 1,
          createdAt: DateTime.utc(2026, 1, 1, 9),
          event: 'workflow_dispatch',
        ),
        GhWorkflowRun(
          databaseId: 99,
          createdAt: DateTime.utc(2026, 1, 1, 8),
          event: 'workflow_dispatch',
        ),
      ];
      expect(selectLatestDispatchRun(runs: runs)?.databaseId, 99);
    });
  });

  group('selectNewDispatchRun', () {
    final base = DateTime.utc(2026, 1, 1, 12);

    test('retry cutoff accepts run within 60s skew before redispatchAt', () {
      final runs = [
        GhWorkflowRun(
          databaseId: 100,
          createdAt: base.subtract(const Duration(minutes: 1)),
          event: 'workflow_dispatch',
          conclusion: 'failure',
        ),
        GhWorkflowRun(
          databaseId: 200,
          createdAt: base.subtract(const Duration(seconds: 30)),
          event: 'workflow_dispatch',
          conclusion: 'success',
        ),
      ];
      final picked = selectNewDispatchRun(
        runs: runs,
        dispatchedAfter: base,
        excludeRunId: 100,
      );
      expect(picked?.databaseId, 200);
    });

    test('ignores stale run outside skew window on retry', () {
      final runs = [
        GhWorkflowRun(
          databaseId: 100,
          createdAt: base.subtract(const Duration(minutes: 5)),
          event: 'workflow_dispatch',
        ),
      ];
      expect(
        selectNewDispatchRun(runs: runs, dispatchedAfter: base),
        isNull,
      );
    });

    test('old failed run listed first; picks newer dispatch after timestamp', () {
      final runs = [
        GhWorkflowRun(
          databaseId: 100,
          createdAt: base.subtract(const Duration(minutes: 1)),
          event: 'workflow_dispatch',
          conclusion: 'failure',
        ),
        GhWorkflowRun(
          databaseId: 200,
          createdAt: base.add(const Duration(seconds: 30)),
          event: 'workflow_dispatch',
          conclusion: 'success',
        ),
      ];
      final picked = selectNewDispatchRun(
        runs: runs,
        dispatchedAfter: base,
        excludeRunId: 100,
      );
      expect(picked?.databaseId, 200);
    });

    test('excludes explicit failed run id even when newest', () {
      final runs = [
        GhWorkflowRun(
          databaseId: 300,
          createdAt: base.add(const Duration(minutes: 2)),
          event: 'workflow_dispatch',
        ),
      ];
      expect(
        selectNewDispatchRun(
          runs: runs,
          dispatchedAfter: base,
          excludeRunId: 300,
        ),
        isNull,
      );
    });

    test('ignores non-workflow_dispatch events', () {
      final runs = [
        GhWorkflowRun(
          databaseId: 400,
          createdAt: base.add(const Duration(minutes: 1)),
          event: 'push',
        ),
      ];
      expect(
        selectNewDispatchRun(runs: runs, dispatchedAfter: base),
        isNull,
      );
    });

    test('parseGhWorkflowRunList preserves list order from gh (stale first)', () {
      const json = '''
[
  {"databaseId": 1, "createdAt": "2026-01-01T11:00:00Z", "event": "workflow_dispatch", "status": "completed", "conclusion": "failure"},
  {"databaseId": 2, "createdAt": "2026-01-01T12:05:00Z", "event": "workflow_dispatch", "status": "completed", "conclusion": "success"}
]
''';
      final runs = parseGhWorkflowRunList(json);
      final picked = selectNewDispatchRun(
        runs: runs,
        dispatchedAfter: DateTime.utc(2026, 1, 1, 12),
        excludeRunId: 1,
      );
      expect(picked?.databaseId, 2);
    });
  });

  group('train discovery integration (fixture)', () {
    test('each tag resolves without retry time filter on first pass', () {
      const jsonA = '''
[{"databaseId": 501, "createdAt": "2026-01-01T09:00:00Z", "event": "workflow_dispatch", "conclusion": "success"}]
''';
      const jsonB = '''
[{"databaseId": 502, "createdAt": "2026-01-01T09:00:05Z", "event": "workflow_dispatch", "conclusion": "success"}]
''';
      final tags = ['universal_foo-v1.0.0', 'universal_bar-v2.0.0'];
      final lists = [jsonA, jsonB];
      final picked = <int>[];
      for (var i = 0; i < tags.length; i++) {
        final run = selectLatestDispatchRun(
          runs: parseGhWorkflowRunList(lists[i]),
        );
        expect(run, isNotNull, reason: tags[i]);
        picked.add(run!.databaseId);
      }
      expect(picked, [501, 502]);
    });
  });

  group('shouldRetryPublishWorkflow', () {
    List<GhWorkflowJob> jobs({String? publishConclusion, String? publishStatus}) =>
        [
          GhWorkflowJob(
            name: 'Publish to pub.dev (OIDC)',
            status: publishStatus ?? 'completed',
            conclusion: publishConclusion,
          ),
        ];

    test('never retries cancelled workflow', () {
      expect(
        shouldRetryPublishWorkflow(
          workflowConclusion: 'cancelled',
          workflowStatus: 'completed',
          jobs: jobs(publishConclusion: 'failure'),
        ),
        isFalse,
      );
    });

    test('retries when publish job failed', () {
      expect(
        shouldRetryPublishWorkflow(
          workflowConclusion: 'failure',
          workflowStatus: 'completed',
          jobs: jobs(publishConclusion: 'failure'),
        ),
        isTrue,
      );
    });

    test('does not retry when publish job skipped', () {
      expect(
        shouldRetryPublishWorkflow(
          workflowConclusion: 'failure',
          workflowStatus: 'completed',
          jobs: jobs(publishConclusion: 'skipped'),
        ),
        isFalse,
      );
    });

    test('does not retry when publish job still waiting', () {
      expect(
        shouldRetryPublishWorkflow(
          workflowConclusion: 'failure',
          workflowStatus: 'completed',
          jobs: jobs(publishConclusion: null, publishStatus: 'waiting'),
        ),
        isFalse,
      );
    });

    test('does not retry when publish job missing', () {
      expect(
        shouldRetryPublishWorkflow(
          workflowConclusion: 'failure',
          workflowStatus: 'completed',
          jobs: [GhWorkflowJob(name: 'ci', conclusion: 'failure')],
        ),
        isFalse,
      );
    });
  });
}
