import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'release_runner_acquisition_lib.dart';

void main() {
  group('jobLooksLikeRunnerNotAcquired', () {
    test('annotation not acquired by Runner', () {
      final job = <String, dynamic>{
        'conclusion': 'cancelled',
        'steps': <dynamic>[],
        'runner_id': null,
        'runner_name': null,
      };
      final annotations = [
        {
          'message':
              'The job was not acquired by Runner of type hosted even after multiple attempts',
        },
      ];
      expect(jobLooksLikeRunnerNotAcquired(job, annotations), isTrue);
    });

    test('zero steps without runner assignment', () {
      final job = <String, dynamic>{
        'conclusion': 'failure',
        'steps': <dynamic>[],
        'runner_id': 0,
        'runner_name': '',
      };
      expect(jobLooksLikeRunnerNotAcquired(job, const []), isTrue);
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

  group('classifyRunnerAcquisitionRetry', () {
    test('fixture: not-acquired cancelled', () {
      final fixture = _loadFixture('not_acquired_cancelled.json');
      final decision = classifyRunnerAcquisitionRetry(
        jobs: fixture.jobs,
        annotationsByJobId: fixture.annotationsByJobId,
        runAttempt: 1,
      );
      expect(decision, RunnerAcquisitionRetryDecision.rerunFailedJobs);
    });

    test('fixture: zero-step unassigned', () {
      final fixture = _loadFixture('zero_step_unassigned.json');
      final decision = classifyRunnerAcquisitionRetry(
        jobs: fixture.jobs,
        annotationsByJobId: fixture.annotationsByJobId,
        runAttempt: 1,
      );
      expect(decision, RunnerAcquisitionRetryDecision.rerunFailedJobs);
    });

    test('fixture: real build failure', () {
      final fixture = _loadFixture('real_build_failure.json');
      final decision = classifyRunnerAcquisitionRetry(
        jobs: fixture.jobs,
        annotationsByJobId: fixture.annotationsByJobId,
        runAttempt: 1,
      );
      expect(decision, RunnerAcquisitionRetryDecision.nonAcquisitionFailure);
    });

    test('fixture: mixed acquisition and real failure', () {
      final fixture = _loadFixture('mixed_failures.json');
      final decision = classifyRunnerAcquisitionRetry(
        jobs: fixture.jobs,
        annotationsByJobId: fixture.annotationsByJobId,
        runAttempt: 1,
      );
      expect(decision, RunnerAcquisitionRetryDecision.nonAcquisitionFailure);
    });

    test('attempt cap blocks retry', () {
      final fixture = _loadFixture('not_acquired_cancelled.json');
      final decision = classifyRunnerAcquisitionRetry(
        jobs: fixture.jobs,
        annotationsByJobId: fixture.annotationsByJobId,
        runAttempt: 3,
      );
      expect(decision, RunnerAcquisitionRetryDecision.attemptCapReached);
    });
  });
}

class _Fixture {
  _Fixture(this.jobs, this.annotationsByJobId);
  final List<Map<String, dynamic>> jobs;
  final Map<int, List<Map<String, dynamic>>> annotationsByJobId;
}

_Fixture _loadFixture(String name) {
  final path = '${Directory.current.path}/tool/contracts/fixtures/release_runner_acquisition/$name';
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
  return _Fixture(jobs, ann);
}