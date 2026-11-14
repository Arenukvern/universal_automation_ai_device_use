import 'dart:io';

import 'package:yaml/yaml.dart';

/// GitHub workflow permission scopes we model (see workflow syntax `permissions`).
const githubPermissionScopes = <String>[
  'actions',
  'attestations',
  'checks',
  'contents',
  'deployments',
  'id-token',
  'discussions',
  'issues',
  'packages',
  'pages',
  'pull-requests',
  'repository-projects',
  'security-events',
  'statuses',
  'vulnerability-alerts',
];

enum AccessLevel {
  none,
  read,
  write,
}

AccessLevel parseAccessLevel(String? raw) {
  switch (raw?.toString().trim()) {
    case 'write':
      return AccessLevel.write;
    case 'read':
      return AccessLevel.read;
    case 'none':
      return AccessLevel.none;
    default:
      return AccessLevel.none;
  }
}

int accessRank(AccessLevel level) => switch (level) {
      AccessLevel.write => 2,
      AccessLevel.read => 1,
      AccessLevel.none => 0,
    };

/// Resolved permissions for a workflow or job (`permissions:` block).
class PermissionMap {
  PermissionMap(this.scopes);

  final Map<String, AccessLevel> scopes;

  static PermissionMap allForLevel(AccessLevel level) => PermissionMap({
        for (final s in githubPermissionScopes) s: level,
      });

  static PermissionMap allNone() => allForLevel(AccessLevel.none);

  static PermissionMap allRead() => allForLevel(AccessLevel.read);

  static PermissionMap allWrite() => allForLevel(AccessLevel.write);

  /// [raw] null means inherit [inheritWhenMissing], or repository default (write-all).
  factory PermissionMap.parse(
    dynamic raw, {
    PermissionMap? inheritWhenMissing,
  }) {
    if (raw == null) {
      return inheritWhenMissing ?? PermissionMap.allWrite();
    }
    if (raw is String) {
      switch (raw.trim()) {
        case 'read-all':
          return PermissionMap.allRead();
        case 'write-all':
          return PermissionMap.allWrite();
        default:
          return PermissionMap.allNone();
      }
    }
    if (raw is! Map) {
      return PermissionMap.allNone();
    }
    final map = Map<dynamic, dynamic>.from(raw);
    if (map.isEmpty) {
      return PermissionMap.allNone();
    }
    final out = PermissionMap.allNone();
    for (final entry in map.entries) {
      out.scopes[entry.key.toString()] = parseAccessLevel(entry.value?.toString());
    }
    return out;
  }

  /// Caller job ceiling for a reusable `uses:` job.
  static PermissionMap callerJobCeiling(
    dynamic jobPerms,
    dynamic workflowPerms,
  ) {
    if (jobPerms != null) {
      return PermissionMap.parse(jobPerms);
    }
    if (workflowPerms != null) {
      return PermissionMap.parse(workflowPerms);
    }
    return PermissionMap.allWrite();
  }

  /// Effective permissions for one job inside a called reusable workflow.
  ///
  /// Missing callee workflow block inherits [callerCeiling]. Missing callee job
  /// block inherits the callee workflow default (or [callerCeiling] when that is
  /// also missing).
  static PermissionMap effectiveCalleeJob({
    required PermissionMap callerCeiling,
    required dynamic calleeWorkflowPerms,
    required dynamic calleeJobPerms,
  }) {
    final workflowBase = calleeWorkflowPerms != null
        ? PermissionMap.parse(calleeWorkflowPerms)
        : PermissionMap(Map.from(callerCeiling.scopes));
    return calleeJobPerms != null
        ? PermissionMap.parse(calleeJobPerms)
        : PermissionMap(Map.from(workflowBase.scopes));
  }

  /// Scopes where [requested] exceeds [ceiling] (GitHub refuses to start the run).
  List<String> scopesExceedingCeiling(PermissionMap ceiling) {
    final errors = <String>[];
    for (final entry in scopes.entries) {
      final max = ceiling.scopes[entry.key] ?? AccessLevel.none;
      if (accessRank(entry.value) > accessRank(max)) {
        errors.add('${entry.key}: ${entry.value.name} > ${max.name}');
      }
    }
    return errors;
  }

  List<String> validateAgainstCeiling(
    PermissionMap ceiling, {
    required String label,
  }) =>
      scopesExceedingCeiling(ceiling)
          .map((s) => '$label: permission over-request ($s)')
          .toList();

  Map<String, String> toScopeStrings() => {
        for (final e in scopes.entries)
          if (e.value != AccessLevel.none) e.key: e.value.name,
      };
}

/// One reusable-workflow call edge in a caller workflow file.
class ReusableCallEdge {
  ReusableCallEdge({
    required this.callerWorkflow,
    required this.callerJobId,
    required this.calleeWorkflowPath,
    required this.callerJobPermissions,
    required this.callerWorkflowPermissions,
  });

  final String callerWorkflow;
  final String callerJobId;
  final String calleeWorkflowPath;
  final dynamic callerJobPermissions;
  final dynamic callerWorkflowPermissions;
}

/// Local (non-reusable) job in a caller workflow.
class LocalCallerJob {
  LocalCallerJob({
    required this.callerWorkflow,
    required this.jobId,
    required this.jobPermissions,
    required this.workflowPermissions,
  });

  final String callerWorkflow;
  final String jobId;
  final dynamic jobPermissions;
  final dynamic workflowPermissions;
}

List<ReusableCallEdge> parseReusableCalls(
  String callerWorkflowLabel,
  String yamlText,
) {
  final doc = loadYaml(yamlText);
  if (doc is! Map) {
    return [];
  }
  final root = Map<dynamic, dynamic>.from(doc);
  final workflowPerms = root['permissions'];
  final jobs = root['jobs'];
  if (jobs is! Map) {
    return [];
  }
  final out = <ReusableCallEdge>[];
  for (final entry in jobs.entries) {
    final job = entry.value;
    if (job is! Map) {
      continue;
    }
    final uses = job['uses']?.toString() ?? '';
    if (!uses.contains('release_binaries_build.yml') &&
        !uses.contains('release_binaries_publish.yml')) {
      continue;
    }
    out.add(
      ReusableCallEdge(
        callerWorkflow: callerWorkflowLabel,
        callerJobId: entry.key.toString(),
        calleeWorkflowPath: uses,
        callerJobPermissions: job['permissions'],
        callerWorkflowPermissions: workflowPerms,
      ),
    );
  }
  return out;
}

List<LocalCallerJob> parseLocalJobs(
  String callerWorkflowLabel,
  String yamlText, {
  Set<String>? onlyJobIds,
}) {
  final doc = loadYaml(yamlText);
  if (doc is! Map) {
    return [];
  }
  final root = Map<dynamic, dynamic>.from(doc);
  final workflowPerms = root['permissions'];
  final jobs = root['jobs'];
  if (jobs is! Map) {
    return [];
  }
  final out = <LocalCallerJob>[];
  for (final entry in jobs.entries) {
    final jobId = entry.key.toString();
    if (onlyJobIds != null && !onlyJobIds.contains(jobId)) {
      continue;
    }
    final job = entry.value;
    if (job is! Map) {
      continue;
    }
    if (job.containsKey('uses')) {
      continue;
    }
    out.add(
      LocalCallerJob(
        callerWorkflow: callerWorkflowLabel,
        jobId: jobId,
        jobPermissions: job['permissions'],
        workflowPermissions: workflowPerms,
      ),
    );
  }
  return out;
}

List<Map<String, dynamic>> calleeJobsInWorkflow(String yamlText) {
  final doc = loadYaml(yamlText);
  if (doc is! Map) {
    return [];
  }
  final root = Map<dynamic, dynamic>.from(doc);
  final wfPerms = root['permissions'];
  final jobs = root['jobs'];
  if (jobs is! Map) {
    return [];
  }
  return jobs.entries.map((e) {
    final job = e.value;
    return {
      'id': e.key.toString(),
      'permissions': job is Map ? job['permissions'] : null,
      'workflowPermissions': wfPerms,
    };
  }).toList();
}

String? calleeFileForUses(String uses, String repoRoot) {
  if (uses.contains('release_binaries_build.yml')) {
    return '$repoRoot/.github/workflows/release_binaries_build.yml';
  }
  if (uses.contains('release_binaries_publish.yml')) {
    return '$repoRoot/.github/workflows/release_binaries_publish.yml';
  }
  return null;
}

/// Resolved permission row for tests and diagnostics.
class PermissionPathRow {
  PermissionPathRow({
    required this.path,
    required this.effective,
    required this.ceiling,
    required this.overRequestErrors,
  });

  final String path;
  final PermissionMap effective;
  final PermissionMap ceiling;
  final List<String> overRequestErrors;
}

List<PermissionPathRow> buildReusablePermissionPaths(String repoRoot) {
  final callers = <(String label, String path)>[
    ('release-please.yml', '$repoRoot/.github/workflows/release-please.yml'),
    ('release_binaries.yml', '$repoRoot/.github/workflows/release_binaries.yml'),
    ('release_binaries_pr.yml', '$repoRoot/.github/workflows/release_binaries_pr.yml'),
  ];
  final rows = <PermissionPathRow>[];
  for (final (label, path) in callers) {
    final text = File(path).readAsStringSync();
    for (final edge in parseReusableCalls(label, text)) {
      final calleePath = calleeFileForUses(edge.calleeWorkflowPath, repoRoot);
      if (calleePath == null) {
        continue;
      }
      final ceiling = PermissionMap.callerJobCeiling(
        edge.callerJobPermissions,
        edge.callerWorkflowPermissions,
      );
      final calleeName = edge.calleeWorkflowPath.contains('build')
          ? 'release_binaries_build.yml'
          : 'release_binaries_publish.yml';
      for (final cj in calleeJobsInWorkflow(File(calleePath).readAsStringSync())) {
        final wfPerms = cj['workflowPermissions'];
        final effective = PermissionMap.effectiveCalleeJob(
          callerCeiling: ceiling,
          calleeWorkflowPerms: wfPerms,
          calleeJobPerms: cj['permissions'],
        );
        final wfBase = wfPerms != null
            ? PermissionMap.parse(wfPerms)
            : PermissionMap(Map.from(ceiling.scopes));
        final over = <String>[
          ...wfBase.validateAgainstCeiling(
            ceiling,
            label: '$label → ${edge.callerJobId} → $calleeName (workflow)',
          ),
          ...effective.validateAgainstCeiling(
            ceiling,
            label: '$label → ${edge.callerJobId} → ${cj['id']}',
          ),
        ];
        rows.add(
          PermissionPathRow(
            path: '$label → ${edge.callerJobId} → $calleeName → ${cj['id']}',
            effective: effective,
            ceiling: ceiling,
            overRequestErrors: over,
          ),
        );
      }
    }
  }
  return rows;
}

List<PermissionPathRow> buildLocalCallerJobRows(String repoRoot) {
  final please = File('$repoRoot/.github/workflows/release-please.yml').readAsStringSync();
  final rows = <PermissionPathRow>[];
  for (final job in parseLocalJobs(
    'release-please.yml',
    please,
    onlyJobIds: {
      'audit-release-train',
      'dispatch-package-publish',
      'wait-package-publish',
    },
  )) {
    final ceiling = PermissionMap.callerJobCeiling(
      job.jobPermissions,
      job.workflowPermissions,
    );
    final effective = PermissionMap.parse(
      job.jobPermissions,
      inheritWhenMissing: PermissionMap.parse(job.workflowPermissions),
    );
    rows.add(
      PermissionPathRow(
        path: 'release-please.yml → ${job.jobId} (local)',
        effective: effective,
        ceiling: ceiling,
        overRequestErrors: effective.validateAgainstCeiling(
          ceiling,
          label: 'release-please.yml → ${job.jobId}',
        ),
      ),
    );
  }
  return rows;
}

List<String> validateProductionReusablePermissionChains(String repoRoot) {
  final errors = <String>[];
  for (final row in buildReusablePermissionPaths(repoRoot)) {
    errors.addAll(row.overRequestErrors);
  }
  return errors;
}

/// Negative fixture: callee job requests write under a read-only caller ceiling.
List<String> permissionChainErrors({
  required Map<String, String> callerJobScopes,
  required Map<String, String> calleeWorkflowScopes,
  required Map<String, Map<String, String>> calleeJobs,
}) {
  final ceiling = PermissionMap.parse(callerJobScopes);
  final errors = <String>[];
  final wf = PermissionMap.parse(calleeWorkflowScopes);
  errors.addAll(
    wf.validateAgainstCeiling(ceiling, label: 'callee-workflow'),
  );
  for (final entry in calleeJobs.entries) {
    final effective = PermissionMap.effectiveCalleeJob(
      callerCeiling: ceiling,
      calleeWorkflowPerms: calleeWorkflowScopes,
      calleeJobPerms: entry.value,
    );
    errors.addAll(
      effective.validateAgainstCeiling(ceiling, label: 'job ${entry.key}'),
    );
  }
  return errors;
}