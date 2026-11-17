/// Classify GitHub Actions jobs that never acquired a hosted runner.
library;

/// GitHub annotation when hosted runner capacity blocks assignment.
const runnerNotAcquiredMessageSubstring = 'not acquired by Runner';

bool jobIsFailedOrCancelled(Map<String, dynamic> job) {
  final conclusion = job['conclusion'];
  return conclusion == 'failure' || conclusion == 'cancelled';
}

bool jobLooksLikeRunnerNotAcquired(
  Map<String, dynamic> job,
  List<Map<String, dynamic>> annotations,
) {
  final steps = job['steps'];
  final stepCount = steps is List ? steps.length : 0;
  final runnerId = job['runner_id'];
  final runnerName = job['runner_name'];

  final hasMsg = annotations.any((annotation) {
    final message = annotation['message'];
    return message is String &&
        message.contains(runnerNotAcquiredMessageSubstring);
  });

  final noRunnerId = runnerId == null || runnerId == 0;
  final noRunnerName = runnerName == null || (runnerName is String && runnerName.isEmpty);
  final zeroStepsUnassigned = stepCount == 0 && noRunnerId && noRunnerName;

  return hasMsg || zeroStepsUnassigned;
}

enum RunnerAcquisitionRetryDecision {
  noFailedJobs,
  attemptCapReached,
  nonAcquisitionFailure,
  rerunFailedJobs,
}

RunnerAcquisitionRetryDecision classifyRunnerAcquisitionRetry({
  required List<Map<String, dynamic>> jobs,
  required Map<int, List<Map<String, dynamic>>> annotationsByJobId,
  required int runAttempt,
  int maxRunAttempt = 3,
}) {
  if (runAttempt >= maxRunAttempt) {
    return RunnerAcquisitionRetryDecision.attemptCapReached;
  }

  final failed = jobs.where(jobIsFailedOrCancelled).toList();
  if (failed.isEmpty) {
    return RunnerAcquisitionRetryDecision.noFailedJobs;
  }

  for (final job in failed) {
    final rawId = job['id'];
    if (rawId is! int) {
      return RunnerAcquisitionRetryDecision.nonAcquisitionFailure;
    }
    final annotations = annotationsByJobId[rawId] ?? const [];
    if (!jobLooksLikeRunnerNotAcquired(job, annotations)) {
      return RunnerAcquisitionRetryDecision.nonAcquisitionFailure;
    }
  }

  return RunnerAcquisitionRetryDecision.rerunFailedJobs;
}

String retryDecisionSummary(RunnerAcquisitionRetryDecision decision) {
  switch (decision) {
    case RunnerAcquisitionRetryDecision.noFailedJobs:
      return 'No failed or cancelled jobs; skip retry.';
    case RunnerAcquisitionRetryDecision.attemptCapReached:
      return 'Run attempt is at or above the retry cap (3); skip auto-retry.';
    case RunnerAcquisitionRetryDecision.nonAcquisitionFailure:
      return 'Failed/cancelled jobs include a real failure or an ambiguous '
          'runner assignment; skip auto-retry.';
    case RunnerAcquisitionRetryDecision.rerunFailedJobs:
      return 'All failed/cancelled jobs look like hosted runner acquisition '
          'loss; eligible for `gh run rerun --failed`.';
  }
}