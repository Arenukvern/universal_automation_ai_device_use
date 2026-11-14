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

final binaryReusableCalleePattern = RegExp(
  r'release_binaries_(build|publish)\.yml',
);

enum AccessLevel {
  none,
  read,
  write,
}

class PermissionParseException implements Exception {
  PermissionParseException(this.message);
  final String message;
  @override
  String toString() => message;
}

AccessLevel? tryParseAccessLevel(String? raw) {
  switch (raw?.toString().trim()) {
    case 'write':
      return AccessLevel.write;
    case 'read':
      return AccessLevel.read;
    case 'none':
      return AccessLevel.none;
    default:
      return null;
  }
}

AccessLevel parseAccessLevel(String? raw) {
  return tryParseAccessLevel(raw) ?? AccessLevel.none;
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

  /// [raw] null only when [inheritWhenMissing] is provided (explicit inheritance).
  factory PermissionMap.parse(
    dynamic raw, {
    PermissionMap? inheritWhenMissing,
  }) {
    if (raw == null) {
      if (inheritWhenMissing != null) {
        return inheritWhenMissing;
      }
      throw PermissionParseException('missing permissions block');
    }
    if (raw is String) {
      final shorthand = raw.trim();
      switch (shorthand) {
        case 'read-all':
          return PermissionMap.allRead();
        case 'write-all':
          return PermissionMap.allWrite();
        default:
          throw PermissionParseException(
            'unknown permissions shorthand "$shorthand"',
          );
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
      final scope = entry.key.toString();
      final rawLevel = entry.value?.toString();
      final level = tryParseAccessLevel(rawLevel);
      if (level == null) {
        throw PermissionParseException(
          'unknown permission level "$rawLevel" for scope $scope',
        );
      }
      out.scopes[scope] = level;
    }
    return out;
  }

  static bool hasExplicitCallerPermissions(
    dynamic jobPerms,
    dynamic workflowPerms,
  ) =>
      jobPerms != null || workflowPerms != null;

  /// Caller job ceiling for a reusable `uses:` job (explicit job or workflow block only).
  static ({PermissionMap? ceiling, String? error}) resolveCallerJobCeiling({
    required dynamic jobPerms,
    required dynamic workflowPerms,
    required String label,
  }) {
    try {
      if (jobPerms != null) {
        return (ceiling: PermissionMap.parse(jobPerms), error: null);
      }
      if (workflowPerms != null) {
        return (ceiling: PermissionMap.parse(workflowPerms), error: null);
      }
      return (
        ceiling: null,
        error:
            '$label: reusable-workflow caller must set explicit permissions on the job or workflow',
      );
    } on PermissionParseException catch (e) {
      return (ceiling: null, error: '$label: $e');
    }
  }

  /// Effective permissions for one job inside a called reusable workflow.
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
    if (!binaryReusableCalleePattern.hasMatch(uses)) {
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

/// Every workflow file under `.github/workflows/` that contains a job `uses:` of
/// the binary release reusables (including nested calls inside callees).
List<(String label, String path)> discoverAllBinaryReusableCallSources(
  String repoRoot,
) {
  final dir = Directory('$repoRoot/.github/workflows');
  if (!dir.existsSync()) {
    return [];
  }
  final out = <(String, String)>[];
  for (final entity in dir.listSync(followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final name = entity.uri.pathSegments.last;
    if (!name.endsWith('.yml') && !name.endsWith('.yaml')) {
      continue;
    }
    final text = entity.readAsStringSync();
    if (parseReusableCalls(name, text).isEmpty) {
      continue;
    }
    out.add((name, entity.path));
  }
  out.sort((a, b) => a.$1.compareTo(b.$1));
  return out;
}

/// Top-level caller workflows (excludes the two reusable callee definitions).
List<(String label, String path)> discoverBinaryReusableCallerWorkflowFiles(
  String repoRoot,
) {
  const calleeOnly = {
    'release_binaries_build.yml',
    'release_binaries_publish.yml',
  };
  return discoverAllBinaryReusableCallSources(repoRoot)
      .where((e) => !calleeOnly.contains(e.$1))
      .toList();
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

List<PermissionPathRow> buildReusablePermissionPathsForYaml(
  String callerLabel,
  String yamlText,
  String repoRoot,
) {
  final rows = <PermissionPathRow>[];
  for (final edge in parseReusableCalls(callerLabel, yamlText)) {
    final resolved = PermissionMap.resolveCallerJobCeiling(
      jobPerms: edge.callerJobPermissions,
      workflowPerms: edge.callerWorkflowPermissions,
      label: '$callerLabel → ${edge.callerJobId}',
    );
    if (resolved.ceiling == null) {
      rows.add(
        PermissionPathRow(
          path: '$callerLabel → ${edge.callerJobId} (explicit permissions)',
          effective: PermissionMap.allNone(),
          ceiling: PermissionMap.allNone(),
          overRequestErrors: [resolved.error!],
        ),
      );
      continue;
    }
    final ceiling = resolved.ceiling!;
    final calleePath = calleeFileForUses(edge.calleeWorkflowPath, repoRoot);
    if (calleePath == null || !File(calleePath).existsSync()) {
      continue;
    }
    final calleeName = edge.calleeWorkflowPath.contains('build')
        ? 'release_binaries_build.yml'
        : 'release_binaries_publish.yml';
    for (final cj in calleeJobsInWorkflow(File(calleePath).readAsStringSync())) {
      final wfPerms = cj['workflowPermissions'];
      PermissionMap effective;
      PermissionMap wfBase;
      try {
        effective = PermissionMap.effectiveCalleeJob(
          callerCeiling: ceiling,
          calleeWorkflowPerms: wfPerms,
          calleeJobPerms: cj['permissions'],
        );
        wfBase = wfPerms != null
            ? PermissionMap.parse(wfPerms)
            : PermissionMap(Map.from(ceiling.scopes));
      } on PermissionParseException catch (e) {
        rows.add(
          PermissionPathRow(
            path: '$callerLabel → ${edge.callerJobId} → $calleeName → ${cj['id']}',
            effective: PermissionMap.allNone(),
            ceiling: ceiling,
            overRequestErrors: [
              '$callerLabel → ${edge.callerJobId} → ${cj['id']}: $e',
            ],
          ),
        );
        continue;
      }
      final over = <String>[
        ...wfBase.validateAgainstCeiling(
          ceiling,
          label: '$callerLabel → ${edge.callerJobId} → $calleeName (workflow)',
        ),
        ...effective.validateAgainstCeiling(
          ceiling,
          label: '$callerLabel → ${edge.callerJobId} → ${cj['id']}',
        ),
      ];
      rows.add(
        PermissionPathRow(
          path: '$callerLabel → ${edge.callerJobId} → $calleeName → ${cj['id']}',
          effective: effective,
          ceiling: ceiling,
          overRequestErrors: over,
        ),
      );
    }
  }
  return rows;
}

List<PermissionPathRow> buildReusablePermissionPaths(String repoRoot) {
  final rows = <PermissionPathRow>[];
  for (final (label, path) in discoverAllBinaryReusableCallSources(repoRoot)) {
    rows.addAll(
      buildReusablePermissionPathsForYaml(
        label,
        File(path).readAsStringSync(),
        repoRoot,
      ),
    );
  }
  return rows;
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

List<String> validateBinaryReusableCallerYaml(
  String yamlText,
  String label, {
  required String repoRoot,
}) {
  final errors = <String>[];
  final edges = parseReusableCalls(label, yamlText);
  if (edges.isEmpty) {
    return ['$label: no release_binaries_build/publish reusable calls found'];
  }
  for (final edge in edges) {
    final resolved = PermissionMap.resolveCallerJobCeiling(
      jobPerms: edge.callerJobPermissions,
      workflowPerms: edge.callerWorkflowPermissions,
      label: '$label → ${edge.callerJobId}',
    );
    if (resolved.error != null) {
      errors.add(resolved.error!);
    }
  }
  for (final row in buildReusablePermissionPathsForYaml(
    label,
    yamlText,
    repoRoot,
  )) {
    errors.addAll(row.overRequestErrors);
  }
  return errors;
}

List<String> validateDiscoveredProductionReusableCallers(String repoRoot) {
  final errors = <String>[];
  final topLevel = discoverBinaryReusableCallerWorkflowFiles(repoRoot);
  const expectedCallers = {
    'release-please.yml',
    'release_binaries.yml',
    'release_binaries_pr.yml',
  };
  for (final name in topLevel.map((e) => e.$1)) {
    if (!expectedCallers.contains(name)) {
      errors.add(
        '$name: unexpected workflow calls release_binaries_build/publish (add to contract or remove)',
      );
    }
  }
  for (final (label, path) in discoverAllBinaryReusableCallSources(repoRoot)) {
    errors.addAll(
      validateBinaryReusableCallerYaml(
        File(path).readAsStringSync(),
        label,
        repoRoot: repoRoot,
      ),
    );
  }
  return errors;
}

/// Explicit ceilings for selected local release-please jobs (not reusable callers).
final releasePleaseLocalJobCeilings = <String, PermissionMap>{
  'audit-release-train': PermissionMap.parse({'contents': 'read'}),
  'dispatch-package-publish': PermissionMap.parse({'actions': 'write'}),
  'wait-package-publish': PermissionMap.parse({
    'actions': 'write',
    'contents': 'read',
  }),
};

final releasePleaseLocalJobRequiredJobPermissions = <String, PermissionMap>{
  'audit-release-train': PermissionMap.parse({'contents': 'read'}),
};

List<String> validateReleasePleaseLocalJobPermissions(
  String repoRoot, {
  String? yamlText,
  String label = 'release-please.yml',
}) {
  final errors = <String>[];
  final text = yamlText ??
      File('$repoRoot/.github/workflows/release-please.yml').readAsStringSync();
  final doc = loadYaml(text);
  if (doc is! Map) {
    return ['$label: root must be a mapping'];
  }
  final jobs = doc['jobs'];
  if (jobs is! Map) {
    return ['$label: jobs missing'];
  }
  final workflowPerms = doc['permissions'];

  for (final entry in releasePleaseLocalJobCeilings.entries) {
    final jobId = entry.key;
    final ceiling = entry.value;
    final job = jobs[jobId];
    if (job is! Map) {
      errors.add('$label: missing local job $jobId');
      continue;
    }
    if (job.containsKey('uses')) {
      continue;
    }
    final required = releasePleaseLocalJobRequiredJobPermissions[jobId];
    if (required != null && job['permissions'] == null) {
      errors.add(
        '$label: $jobId must set explicit job permissions (required for audit)',
      );
      continue;
    }
    try {
      final effective = PermissionMap.parse(
        job['permissions'],
        inheritWhenMissing: workflowPerms != null
            ? PermissionMap.parse(workflowPerms)
            : null,
      );
      errors.addAll(
        effective.validateAgainstCeiling(
          ceiling,
          label: '$label → $jobId',
        ),
      );
    } on PermissionParseException catch (e) {
      errors.add('$label → $jobId: $e');
    }
  }
  return errors;
}

List<String> validateProductionReusablePermissionChains(String repoRoot) {
  return [
    ...validateDiscoveredProductionReusableCallers(repoRoot),
    ...validateReleasePleaseLocalJobPermissions(repoRoot),
  ];
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