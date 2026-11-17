/// Classify GitHub Actions jobs that never acquired a hosted runner.
library;

/// GitHub annotation when hosted runner capacity blocks assignment.
const runnerNotAcquiredMessageSubstring = 'not acquired by Runner';

/// Queue time before a zero-step unassigned job counts as acquisition loss.
const minRunnerAcquisitionQueueSeconds = 600;

bool jobIsFailedOrCancelled(Map<String, dynamic> job) {
  final conclusion = job['conclusion'];
  return conclusion == 'failure' || conclusion == 'cancelled';
}

Duration? jobQueueDuration(Map<String, dynamic> job) {
  final createdRaw = job['created_at'];
  final completedRaw = job['completed_at'];
  if (createdRaw is! String || completedRaw is! String) {
    return null;
  }
  try {
    final created = DateTime.parse(createdRaw).toUtc();
    final completed = DateTime.parse(completedRaw).toUtc();
    return completed.difference(created);
  } catch (_) {
    return null;
  }
}

bool jobHasRunnerNotAcquiredAnnotation(List<Map<String, dynamic>> annotations) {
  return annotations.any((annotation) {
    final message = annotation['message'];
    return message is String &&
        message.contains(runnerNotAcquiredMessageSubstring);
  });
}

bool jobLooksLikeRunnerNotAcquired(
  Map<String, dynamic> job,
  List<Map<String, dynamic>> annotations,
) {
  if (jobHasRunnerNotAcquiredAnnotation(annotations)) {
    return true;
  }

  final steps = job['steps'];
  final stepCount = steps is List ? steps.length : 0;
  final runnerId = job['runner_id'];
  final runnerName = job['runner_name'];

  final noRunnerId = runnerId == null || runnerId == 0;
  final noRunnerName =
      runnerName == null || (runnerName is String && runnerName.isEmpty);
  final zeroStepsUnassigned = stepCount == 0 && noRunnerId && noRunnerName;
  if (!zeroStepsUnassigned) {
    return false;
  }

  final queue = jobQueueDuration(job);
  if (queue == null) {
    return false;
  }
  return queue.inSeconds >= minRunnerAcquisitionQueueSeconds;
}

const _activeRunStatuses = <String>{
  'queued',
  'in_progress',
  'waiting',
  'requested',
  'pending',
};

bool isRunSupersededOnRef({
  required int triggerRunId,
  required DateTime triggerRunCreatedAt,
  required List<Map<String, dynamic>> siblingRunsOnRef,
}) {
  if (siblingRunsOnRef.isEmpty) {
    return false;
  }

  DateTime? newestCreated;
  int? newestId;
  for (final run in siblingRunsOnRef) {
    final id = _runId(run);
    final created = _runCreatedAt(run);
    if (id == null || created == null) {
      continue;
    }
    if (newestCreated == null || created.isAfter(newestCreated)) {
      newestCreated = created;
      newestId = id;
    }
    if (id == triggerRunId) {
      continue;
    }
    if (created.isAfter(triggerRunCreatedAt)) {
      final status = run['status']?.toString() ?? '';
      if (_activeRunStatuses.contains(status) || status == 'completed') {
        return true;
      }
    }
  }

  return newestId != null && newestId != triggerRunId;
}

int? _runId(Map<String, dynamic> run) {
  final id = run['id'] ?? run['databaseId'];
  if (id is int) {
    return id;
  }
  if (id is num) {
    return id.toInt();
  }
  return int.tryParse('$id');
}

DateTime? _runCreatedAt(Map<String, dynamic> run) {
  final raw = run['created_at'] ?? run['createdAt'];
  if (raw is! String) {
    return null;
  }
  try {
    return DateTime.parse(raw).toUtc();
  } catch (_) {
    return null;
  }
}

enum RunnerAcquisitionRetryDecision {
  noFailedJobs,
  attemptCapReached,
  supersededRun,
  nonAcquisitionFailure,
  rerunFailedJobs,
}

RunnerAcquisitionRetryDecision classifyRunnerAcquisitionRetry({
  required List<Map<String, dynamic>> jobs,
  required Map<int, List<Map<String, dynamic>>> annotationsByJobId,
  required int runAttempt,
  int maxRunAttempt = 3,
  int? triggerRunId,
  DateTime? triggerRunCreatedAt,
  List<Map<String, dynamic>>? siblingRunsOnRef,
}) {
  if (triggerRunId != null &&
      triggerRunCreatedAt != null &&
      siblingRunsOnRef != null &&
      isRunSupersededOnRef(
        triggerRunId: triggerRunId,
        triggerRunCreatedAt: triggerRunCreatedAt,
        siblingRunsOnRef: siblingRunsOnRef,
      )) {
    return RunnerAcquisitionRetryDecision.supersededRun;
  }

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
    case RunnerAcquisitionRetryDecision.supersededRun:
      return 'A newer workflow run exists (or is active) for the same ref; '
          'skip auto-retry.';
    case RunnerAcquisitionRetryDecision.nonAcquisitionFailure:
      return 'Failed/cancelled jobs include a real failure or an ambiguous '
          'runner assignment; skip auto-retry.';
    case RunnerAcquisitionRetryDecision.rerunFailedJobs:
      return 'All failed/cancelled jobs look like hosted runner acquisition '
          'loss; eligible for `gh run rerun --failed`.';
  }
}