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

const toolkitPackagePath = 'pkgs/universal_automation_toolkit';

const releaseBinariesWorkflowFile = 'release_binaries.yml';

/// Must match `run-name:` in `.github/workflows/release_binaries.yml`.
const releaseBinariesRunNamePrefix = 'release-binaries ';

/// `gh run list --json` field names for release-binaries discovery.
const releaseBinariesRunListJsonFields =
    'databaseId,createdAt,status,conclusion,event,displayTitle';

/// Parses toolkit tag from workflow run display title (`run-name`).
String? releaseTagFromDisplayTitle(String? displayTitle) {
  if (displayTitle == null || displayTitle.isEmpty) {
    return null;
  }
  if (!displayTitle.startsWith(releaseBinariesRunNamePrefix)) {
    return null;
  }
  final tag = displayTitle.substring(releaseBinariesRunNamePrefix.length).trim();
  if (tag.isEmpty) {
    return null;
  }
  final pattern = RegExp(r'^universal_automation_toolkit-v\d+\.\d+\.\d+$');
  if (!pattern.hasMatch(tag)) {
    return null;
  }
  return tag;
}

/// Toolkit tag from release-please outputs when the toolkit was released.
String? toolkitReleaseTag({required Map<String, dynamic> outputs}) {
  final created = outputs['$toolkitPackagePath--release_created'];
  if (created != true && created != 'true') {
    return null;
  }
  final tag = outputs['$toolkitPackagePath--tag_name'] as String?;
  if (tag == null || tag.isEmpty) {
    return null;
  }
  return tag;
}

const defaultDispatchRunDiscoveryTimeout = Duration(minutes: 10);

/// Strict main-mode post-publish audit (`--release-pr` omitted; errors block).
const strictPostPublishAuditArgs = <String>[
  'run',
  'tool/check_hosted_deps_resolve.dart',
  '--audit-published',
];

/// Clock-skew margin when matching a re-dispatch to a new workflow run.
const dispatchRunDiscoveryClockSkew = Duration(seconds: 60);

final class GhWorkflowRun {
  GhWorkflowRun({
    required this.databaseId,
    required this.createdAt,
    this.event,
    this.status,
    this.conclusion,
    this.displayTitle,
  });

  final int databaseId;
  final DateTime createdAt;
  final String? event;
  final String? status;
  final String? conclusion;
  final String? displayTitle;

  factory GhWorkflowRun.fromJson(Map<String, dynamic> json) {
    return GhWorkflowRun(
      databaseId: json['databaseId'] as int,
      createdAt: parseGhRunCreatedAt(json['createdAt'] as String),
      event: json['event'] as String?,
      status: json['status'] as String?,
      conclusion: json['conclusion'] as String?,
      displayTitle: json['displayTitle'] as String?,
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

/// Newest `workflow_dispatch` run on a tag ref (first wait — dispatch already
/// happened in the prior job).
GhWorkflowRun? selectLatestDispatchRun({
  required List<GhWorkflowRun> runs,
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
    if (best == null || run.databaseId > best.databaseId) {
      best = run;
    }
  }
  return best;
}

/// After a re-dispatch, pick the newest `workflow_dispatch` run at or after
/// [dispatchedAfter] minus [clockSkew], excluding [excludeRunId].
GhWorkflowRun? selectNewDispatchRun({
  required List<GhWorkflowRun> runs,
  required DateTime dispatchedAfter,
  int? excludeRunId,
  Duration clockSkew = dispatchRunDiscoveryClockSkew,
}) {
  final cutoff = dispatchedAfter.subtract(clockSkew);
  GhWorkflowRun? best;
  for (final run in runs) {
    if (run.event != null && run.event != 'workflow_dispatch') {
      continue;
    }
    if (excludeRunId != null && run.databaseId == excludeRunId) {
      continue;
    }
    if (run.createdAt.isBefore(cutoff)) {
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
