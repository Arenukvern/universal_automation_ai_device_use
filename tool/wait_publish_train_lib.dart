import 'dart:convert';

/// Tags to watch from release-please `paths_released` outputs.
List<String> releasePleasePublishTags({
  required Map<String, dynamic> outputs,
}) {
  final pathsRaw = outputs['paths_released'];
  if (pathsRaw == null ||
      pathsRaw == '' ||
      pathsRaw == '[]' ||
      pathsRaw == false) {
    return [];
  }
  final paths = jsonDecode(pathsRaw as String) as List<dynamic>;
  final tags = <String>[];
  for (final path in paths) {
    final p = path as String;
    final created = outputs['$p--release_created'];
    if (created != true && created != 'true') {
      continue;
    }
    final tag = outputs['$p--tag_name'] as String?;
    if (tag != null && tag.isNotEmpty) {
      tags.add(tag);
    }
  }
  return tags;
}

const publishWorkflowJobName = 'Publish to pub.dev (OIDC)';

const defaultDispatchRunDiscoveryTimeout = Duration(minutes: 10);

final class GhWorkflowRun {
  GhWorkflowRun({
    required this.databaseId,
    required this.createdAt,
    this.event,
    this.status,
    this.conclusion,
  });

  final int databaseId;
  final DateTime createdAt;
  final String? event;
  final String? status;
  final String? conclusion;

  factory GhWorkflowRun.fromJson(Map<String, dynamic> json) {
    return GhWorkflowRun(
      databaseId: json['databaseId'] as int,
      createdAt: parseGhRunCreatedAt(json['createdAt'] as String),
      event: json['event'] as String?,
      status: json['status'] as String?,
      conclusion: json['conclusion'] as String?,
    );
  }
}

final class GhWorkflowJob {
  GhWorkflowJob({required this.name, this.status, this.conclusion});

  final String name;
  final String? status;
  final String? conclusion;

  factory GhWorkflowJob.fromJson(Map<String, dynamic> json) {
    return GhWorkflowJob(
      name: json['name'] as String,
      status: json['status'] as String?,
      conclusion: json['conclusion'] as String?,
    );
  }
}

DateTime parseGhRunCreatedAt(String iso) {
  return DateTime.parse(iso).toUtc();
}

List<GhWorkflowRun> parseGhWorkflowRunList(String stdout) {
  final decoded = jsonDecode(stdout) as List<dynamic>;
  return decoded
      .map((e) => GhWorkflowRun.fromJson(e as Map<String, dynamic>))
      .toList();
}

List<GhWorkflowJob> parseGhWorkflowJobs(String stdout) {
  final decoded = jsonDecode(stdout) as Map<String, dynamic>;
  final jobs = decoded['jobs'] as List<dynamic>? ?? [];
  return jobs
      .map((e) => GhWorkflowJob.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// After a dispatch, pick the newest `workflow_dispatch` run created strictly
/// after [dispatchedAfter], excluding [excludeRunId] when set.
GhWorkflowRun? selectNewDispatchRun({
  required List<GhWorkflowRun> runs,
  required DateTime dispatchedAfter,
  int? excludeRunId,
}) {
  GhWorkflowRun? best;
  for (final run in runs) {
    if (run.event != null && run.event != 'workflow_dispatch') {
      continue;
    }
    if (excludeRunId != null && run.databaseId == excludeRunId) {
      continue;
    }
    if (!run.createdAt.isAfter(dispatchedAfter)) {
      continue;
    }
    if (best == null || run.databaseId > best.databaseId) {
      best = run;
    }
  }
  return best;
}

/// Never retry cancelled runs; only retry completed failures where the publish
/// job itself failed (not skipped / waiting / never started).
bool shouldRetryPublishWorkflow({
  required String? workflowConclusion,
  required String? workflowStatus,
  required List<GhWorkflowJob> jobs,
}) {
  if (workflowConclusion == 'cancelled') {
    return false;
  }
  if (workflowStatus != 'completed') {
    return false;
  }
  if (workflowConclusion != 'failure') {
    return false;
  }
  return publishJobFailed(jobs);
}

bool publishJobFailed(List<GhWorkflowJob> jobs) {
  GhWorkflowJob? publish;
  for (final job in jobs) {
    if (job.name == publishWorkflowJobName) {
      publish = job;
      break;
    }
  }
  if (publish == null) {
    return false;
  }
  final status = publish.status;
  if (status == 'waiting' ||
      status == 'queued' ||
      status == 'pending' ||
      status == 'requested' ||
      status == 'in_progress') {
    return false;
  }
  if (publish.conclusion == 'skipped' ||
      publish.conclusion == null ||
      publish.conclusion == '') {
    return false;
  }
  return publish.conclusion == 'failure';
}
