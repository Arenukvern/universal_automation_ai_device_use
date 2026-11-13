import 'package:test/test.dart';

import 'wait_publish_train_lib.dart';

void main() {
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
  });

  group('selectNewDispatchRun', () {
    final base = DateTime.utc(2026, 1, 1, 12);

    test('ignores stale run (created before dispatch)', () {
      final runs = [
        GhWorkflowRun(
          databaseId: 100,
          createdAt: base.subtract(const Duration(minutes: 5)),
          event: 'workflow_dispatch',
          conclusion: 'failure',
        ),
      ];
      expect(
        selectNewDispatchRun(
          runs: runs,
          dispatchedAfter: base,
        ),
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
