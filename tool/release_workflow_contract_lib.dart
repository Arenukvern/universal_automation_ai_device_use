import 'package:yaml/yaml.dart';

/// gh 2.103.0 `gh run list --json` fields (from `gh help run list`, JSON FIELDS).
const ghRunListJsonFieldsGh21030 = <String>[
  'attempt',
  'conclusion',
  'createdAt',
  'databaseId',
  'displayTitle',
  'event',
  'headBranch',
  'headSha',
  'name',
  'number',
  'startedAt',
  'status',
  'updatedAt',
  'url',
  'workflowDatabaseId',
  'workflowName',
];

const exactReleaseBinariesBuildRunName =
    "release-binaries-build \${{ inputs.dry_run == true && 'dry-run' || inputs.release_tag }}";
const exactReleaseBinariesDispatchRunName =
    r'release-binaries ${{ inputs.release_tag }}';
const releaseBinariesBuildWorkflowPath =
    './.github/workflows/release_binaries_build.yml';
const exactDryRunBundleIf = 'inputs.dry_run == true';
const releaseBinariesPublishWorkflowPath =
    './.github/workflows/release_binaries_publish.yml';

const signStepName = 'Sign macOS bundle';

const requiredScriptStepsBuild = <String, String>{
  'verify_release_tarball_architecture.sh': 'build',
};

const requiredScriptStepsPublish = <String, String>{
  'assert_release_assets_complete.sh': 'postflight',
  'check_release_assets_conflict.sh': 'publish',
};

const allowedBuildJobEnvSecretKeys = <String>{
  'HAS_SIGNING',
  'HAS_CERT_P12',
  'HAS_CERT_PASSWORD',
};

const requiredBuildMatrixTriples = <String>[
  'darwin-arm64',
  'darwin-x64',
  'linux-x64',
  'windows-x64',
];

const requiredGhReleaseAssetSuffixes = <String>[
  '_darwin-arm64.tar.gz',
  '_darwin-x64.tar.gz',
  '_linux-x64.tar.gz',
  '_windows-x64.zip',
  'checksums.txt',
];

const requiredReleaseBinariesSigningSecretNames = <String>[
  'MACOS_CERT_P12',
  'MACOS_CERT_PASSWORD',
  'MACOS_CODESIGN_IDENTITY',
  'APPLE_ID',
  'APPLE_TEAM_ID',
  'APPLE_APP_PASSWORD',
];

/// Structural validation for `.github/workflows/release_binaries_build.yml`.
List<String> validateReleaseBinariesBuildWorkflowYaml(
  String yamlText, {
  String label = 'release_binaries_build.yml',
}) {
  final errors = <String>[];
  final dynamic doc;
  try {
    doc = loadYaml(yamlText);
  } catch (e) {
    return ['$label: invalid YAML: $e'];
  }
  if (doc is! Map) {
    return ['$label: root must be a mapping'];
  }
  final root = Map<dynamic, dynamic>.from(doc);

  final on = root['on'];
  if (on is! Map) {
    errors.add('$label: on must be a mapping');
  } else {
    final onMap = Map<dynamic, dynamic>.from(on);
    if (!onMap.containsKey('workflow_call')) {
      errors.add('$label: on.workflow_call is required');
    }
    if (onMap.containsKey('workflow_dispatch')) {
      errors.add('$label: on.workflow_dispatch is forbidden (manual dispatch uses release_binaries.yml)');
    }
    const allowedOnKeys = {'workflow_call'};
    for (final key in onMap.keys) {
      if (!allowedOnKeys.contains(key.toString())) {
        errors.add(
          '$label: forbidden on.$key trigger (workflow_call only)',
        );
      }
    }
    for (final trigger in ['workflow_call']) {
      final block = onMap[trigger];
      if (block is! Map) {
        continue;
      }
      final inputs = Map<dynamic, dynamic>.from((block['inputs'] as Map?) ?? {});
      if (!inputs.containsKey('release_tag')) {
        errors.add('$label: on.$trigger.inputs.release_tag required');
      }
      if (!inputs.containsKey('dry_run')) {
        errors.add('$label: on.$trigger.inputs.dry_run required');
      }
      if (!inputs.containsKey('tooling_ref')) {
        errors.add('$label: on.$trigger.inputs.tooling_ref required');
      }
    }
  }

  final jobs = root['jobs'];
  if (jobs is! Map) {
    errors.add('$label: jobs must be a mapping');
    return errors;
  }
  final jobsMap = Map<dynamic, dynamic>.from(jobs);

  const requiredJobs = ['prepare', 'build', 'dry-run-bundle'];
  for (final id in requiredJobs) {
    if (!jobsMap.containsKey(id)) {
      errors.add('$label: missing job $id');
    }
  }

  for (final forbidden in ['publish', 'postflight']) {
    if (jobsMap.containsKey(forbidden)) {
      errors.add(
        '$label: must not define $forbidden (use release_binaries_publish.yml reusable)',
      );
    }
  }

  void requireExactJobIf(String jobId, String exact) {
    final job = jobsMap[jobId];
    if (job is! Map) {
      return;
    }
    final raw = job['if']?.toString().trim() ?? '';
    if (raw != exact) {
      errors.add('$label: job $jobId if must be exactly `$exact` (got `$raw`)');
    }
  }

  requireExactJobIf('dry-run-bundle', exactDryRunBundleIf);

  for (final entry in jobsMap.entries) {
    final job = entry.value;
    if (job is Map && job['continue-on-error'] == true) {
      errors.add('$label: job ${entry.key} must not set continue-on-error');
    }
  }

  errors.addAll(
    _validateRequiredScriptSteps(jobsMap, label, requiredScriptStepsBuild),
  );
  errors.addAll(
    _validateRunBlocksBeforeScripts(jobsMap, label, requiredScriptStepsBuild),
  );
  final build = jobsMap['build'];
  if (build is Map) {
    final needs = build['needs'];
    if (needs?.toString() != 'prepare') {
      errors.add('$label: build must need prepare');
    }
    errors.addAll(_validateSigningSecretsScope(build, label));
  }

  final runName = root['run-name']?.toString().trim() ?? '';
  if (runName != exactReleaseBinariesBuildRunName) {
    errors.add(
      '$label: run-name must be exactly `$exactReleaseBinariesBuildRunName`',
    );
  }

  if (!_allCheckoutsPersistFalse(jobsMap)) {
    errors.add('$label: every actions/checkout must set persist-credentials: false');
  }

  errors.addAll(_workflowSecretsOutsideAllowlist(jobsMap, yamlText, label));
  errors.addAll(_validateBuildMatrix(jobsMap, label));
  errors.addAll(_validateReadOnlyPermissions(jobsMap, root, label));
  errors.addAll(_validateBuildHasNoReleasePublishSteps(yamlText, label));
  errors.addAll(_validateNoInlineWorkflowExprsInRun(jobsMap, label));

  return errors;
}

/// Alias for negative fixtures targeting the build reusable workflow.
List<String> validateReleaseBinariesWorkflowYaml(
  String yamlText, {
  String label = 'release_binaries.yml',
}) =>
    validateReleaseBinariesBuildWorkflowYaml(yamlText, label: label);

/// `.github/workflows/release_binaries_publish.yml` — publish + postflight only.
List<String> validateReleaseBinariesPublishWorkflowYaml(
  String yamlText, {
  String label = 'release_binaries_publish.yml',
}) {
  final errors = <String>[];
  final dynamic doc;
  try {
    doc = loadYaml(yamlText);
  } catch (e) {
    return ['$label: invalid YAML: $e'];
  }
  if (doc is! Map) {
    return ['$label: root must be a mapping'];
  }
  final root = Map<dynamic, dynamic>.from(doc);
  final on = root['on'];
  if (on is! Map || !Map.from(on).containsKey('workflow_call')) {
    errors.add('$label: on.workflow_call is required');
  }
  final jobs = root['jobs'];
  if (jobs is! Map) {
    errors.add('$label: jobs must be a mapping');
    return errors;
  }
  final jobsMap = Map<dynamic, dynamic>.from(jobs);
  if (!jobsMap.containsKey('publish') || !jobsMap.containsKey('postflight')) {
    errors.add('$label: must define publish and postflight jobs');
  }
  errors.addAll(
    _validateRequiredScriptSteps(jobsMap, label, requiredScriptStepsPublish),
  );
  errors.addAll(
    _validateRunBlocksBeforeScripts(jobsMap, label, requiredScriptStepsPublish),
  );
  errors.addAll(_validateGhReleaseAssets(jobsMap, label));
  errors.addAll(_validateContentsWriteScope(jobsMap, root, label));
  errors.addAll(_validateSplitPublishNeeds(jobsMap, label));
  errors.addAll(_validateSameRunArtifactDownload(jobsMap, label));
  errors.addAll(_validateNoInlineWorkflowExprsInRun(jobsMap, label));
  if (!_publishUsesAppendBody(jobsMap['publish'])) {
    errors.add('$label: publish job must set append_body: true on action-gh-release');
  }
  final postflight = jobsMap['postflight'];
  if (postflight is Map) {
    final needs = postflight['needs'];
    final needsList =
        needs is List ? needs.map((e) => e.toString()).toList() : <String>[];
    if (!needsList.contains('publish')) {
      errors.add('$label: postflight must need publish');
    }
  }
  return errors;
}

/// Manual `release_binaries.yml` dispatcher (workflow_dispatch → build reusable).
List<String> validateReleaseBinariesDispatchWorkflowYaml(
  String yamlText, {
  String label = 'release_binaries.yml',
}) {
  final errors = <String>[];
  final dynamic doc;
  try {
    doc = loadYaml(yamlText);
  } catch (e) {
    return ['$label: invalid YAML: $e'];
  }
  if (doc is! Map) {
    return ['$label: root must be a mapping'];
  }
  final root = Map<dynamic, dynamic>.from(doc);
  final on = root['on'];
  if (on is! Map || !Map.from(on).containsKey('workflow_dispatch')) {
    errors.add('$label: on.workflow_dispatch is required');
  }
  if (on is Map && Map.from(on).containsKey('workflow_call')) {
    errors.add('$label: must not define workflow_call on dispatch wrapper');
  }
  final runName = root['run-name']?.toString().trim() ?? '';
  if (runName != exactReleaseBinariesDispatchRunName) {
    errors.add(
      '$label: run-name must be exactly `$exactReleaseBinariesDispatchRunName`',
    );
  }
  errors.addAll(_forbidSecretsInherit(yamlText, label));
  final jobs = root['jobs'];
  if (jobs is! Map) {
    errors.add('$label: jobs missing');
    return errors;
  }
  final jobsMap = Map<dynamic, dynamic>.from(jobs);
  final build = jobsMap['build'];
  if (build is! Map ||
      !build['uses'].toString().contains('release_binaries_build.yml')) {
    errors.add('$label: build job must use release_binaries_build.yml');
  }
  final workflowPerms = root['permissions'];
  if (build is Map) {
    errors.addAll(_validateExplicitSigningSecretsMap(build['secrets'], label));
    final withMap = build['with'];
    if (withMap is! Map) {
      errors.add('$label: build job must pass with:');
    }
    errors.addAll(
      _requireExplicitReusableJobPermissions(build, workflowPerms, '$label: build job'),
    );
    final perms = build['permissions'];
    if (perms is! Map || perms['contents']?.toString() != 'read') {
      errors.add('$label: build job must set permissions.contents: read');
    }
  }
  final publish = jobsMap['publish'];
  if (publish is! Map ||
      !publish['uses'].toString().contains('release_binaries_publish.yml')) {
    errors.add('$label: publish job must use release_binaries_publish.yml');
  }
  if (publish is Map) {
    if (publish.containsKey('secrets')) {
      errors.add('$label: publish reusable call must not pass secrets');
    }
    errors.addAll(
      _requireExplicitReusableJobPermissions(
        publish,
        workflowPerms,
        '$label: publish job',
      ),
    );
    final perms = publish['permissions'];
    if (perms is! Map || perms['contents']?.toString() != 'write') {
      errors.add('$label: publish job must set permissions.contents: write');
    }
    final needs = _jobNeedsList(publish);
    if (!needs.contains('build')) {
      errors.add('$label: publish job must need build');
    }
    final pubIf = publish['if']?.toString().trim() ?? '';
    if (pubIf != 'inputs.dry_run != true') {
      errors.add('$label: publish job if must be exactly `inputs.dry_run != true`');
    }
  }
  if (jobsMap.length != 2) {
    errors.add('$label: exactly build and publish reusable-workflow caller jobs expected');
  }
  return errors;
}

List<String> _forbidSecretsInherit(String yamlText, String label) {
  if (RegExp(r'secrets:\s*inherit\b').hasMatch(yamlText)) {
    return ['$label: secrets: inherit is forbidden (pass signing secrets by name)'];
  }
  return [];
}

List<String> _requireExplicitReusableJobPermissions(
  Map<dynamic, dynamic> job,
  dynamic workflowPerms,
  String label,
) {
  if (job['permissions'] != null || workflowPerms != null) {
    return [];
  }
  return [
    '$label: reusable-workflow caller must set explicit permissions on the job or workflow',
  ];
}

List<String> _validateReadOnlyPermissions(
  Map<dynamic, dynamic> jobsMap,
  Map<dynamic, dynamic> root,
  String label,
) {
  final errors = <String>[];
  final workflowPerms = root['permissions'];
  if (workflowPerms is Map) {
    for (final entry in workflowPerms.entries) {
      if (entry.value?.toString() == 'write') {
        errors.add('$label: workflow permissions must not include write scopes');
      }
    }
  }
  for (final entry in jobsMap.entries) {
    final job = entry.value;
    if (job is! Map) {
      continue;
    }
    final perms = job['permissions'];
    if (perms is Map) {
      for (final v in perms.values) {
        if (v?.toString() == 'write') {
          errors.add('$label: job ${entry.key} must not request contents: write');
        }
      }
    }
  }
  return errors;
}

/// Structural validation for `.github/workflows/release_binaries_pr.yml`.
List<String> validateReleaseBinariesPrWorkflowYaml(
  String yamlText, {
  String label = 'release_binaries_pr.yml',
}) {
  final errors = <String>[];
  final dynamic doc;
  try {
    doc = loadYaml(yamlText);
  } catch (e) {
    return ['$label: invalid YAML: $e'];
  }
  if (doc is! Map) {
    return ['$label: root must be a mapping'];
  }
  final root = Map<dynamic, dynamic>.from(doc);

  final on = root['on'];
  if (on is! Map) {
    errors.add('$label: on must be a mapping');
  } else {
    final onMap = Map<dynamic, dynamic>.from(on);
    const allowed = {'pull_request', 'push'};
    for (final key in onMap.keys) {
      if (!allowed.contains(key.toString())) {
        errors.add('$label: forbidden on.$key (pull_request + push only)');
      }
    }
    if (!onMap.containsKey('pull_request')) {
      errors.add('$label: on.pull_request required');
    }
    if (!onMap.containsKey('push')) {
      errors.add('$label: on.push required');
    }
  }

  final workflowPerms = root['permissions'];
  if (workflowPerms is! Map ||
      workflowPerms['contents']?.toString() != 'read') {
    errors.add('$label: workflow permissions must set contents: read');
  }

  final jobs = root['jobs'];
  if (jobs is! Map || jobs.isEmpty) {
    errors.add('$label: jobs must be defined');
    return errors;
  }
  final jobsMap = Map<dynamic, dynamic>.from(jobs);
  if (jobsMap.length != 1) {
    errors.add('$label: exactly one reusable-workflow caller job expected');
  }
  final smoke = jobsMap['smoke'];
  if (smoke is! Map) {
    errors.add('$label: missing smoke caller job');
    return errors;
  }
  final uses = smoke['uses']?.toString() ?? '';
  if (uses != releaseBinariesBuildWorkflowPath) {
    errors.add(
      '$label: smoke must use $releaseBinariesBuildWorkflowPath (got `$uses`)',
    );
  }
  final withMap = smoke['with'];
  if (withMap is! Map) {
    errors.add('$label: smoke must pass with:');
  } else {
    final dryRun = withMap['dry_run'];
    if (dryRun != true && dryRun?.toString() != 'true') {
      errors.add('$label: smoke must pass dry_run: true literally');
    }
  }
  if (smoke.containsKey('secrets')) {
    errors.add('$label: smoke must not pass signing secrets');
  }
  errors.addAll(_forbidSecretsInherit(yamlText, label));
  errors.addAll(
    _requireExplicitReusableJobPermissions(smoke, workflowPerms, '$label: smoke'),
  );
  final perms = smoke['permissions'];
  if (perms is Map && perms['contents']?.toString() != 'read') {
    errors.add('$label: smoke permissions.contents must be read');
  }
  return errors;
}

/// `dispatch-package-publish` must not depend on toolkit binary jobs.
const releasePleaseDispatchPublishJob = 'dispatch-package-publish';
const releasePleaseWaitPublishJob = 'wait-package-publish';
const releasePleaseAuditTrainJob = 'audit-release-train';
const releasePleaseBinariesBuildJob = 'release-binaries-build';
const releasePleaseBinariesPublishJob = 'release-binaries-publish';

/// Release-please train: binaries, pub.dev dispatch/wait independence, final audit.
List<String> validateReleasePleaseBinariesCaller(String yamlText) {
  final errors = <String>[];
  final dynamic doc;
  try {
    doc = loadYaml(yamlText);
  } catch (e) {
    return ['release-please.yml: invalid YAML: $e'];
  }
  if (doc is! Map) {
    return ['release-please.yml: root must be a mapping'];
  }
  final jobs = doc['jobs'];
  if (jobs is! Map) {
    return ['release-please.yml: jobs missing'];
  }
  final jobsMap = Map<dynamic, dynamic>.from(jobs);
  errors.addAll(_forbidSecretsInherit(yamlText, 'release-please.yml'));

  final build = jobsMap['release-binaries-build'];
  if (build is! Map) {
    errors.add('release-please.yml: missing release-binaries-build job');
  } else {
    if (build['uses']?.toString() != releaseBinariesBuildWorkflowPath) {
      errors.add(
        'release-please.yml: release-binaries-build must use $releaseBinariesBuildWorkflowPath',
      );
    }
    final withMap = build['with'];
    if (withMap is! Map) {
      errors.add('release-please.yml: release-binaries-build must pass with:');
    } else if (withMap['dry_run'] != false && withMap['dry_run']?.toString() != 'false') {
      errors.add('release-please.yml: release-binaries-build must pass dry_run: false');
    }
    errors.addAll(
      _requireExplicitReusableJobPermissions(
        build,
        null,
        'release-please.yml: release-binaries-build',
      ),
    );
    final perms = build['permissions'];
    if (perms is Map && perms['contents']?.toString() != 'read') {
      errors.add('release-please.yml: release-binaries-build needs contents: read');
    }
    errors.addAll(
      _validateExplicitSigningSecretsMap(
        build['secrets'],
        'release-please.yml: release-binaries-build',
      ),
    );
  }

  final publish = jobsMap[releasePleaseBinariesPublishJob];
  if (publish is! Map) {
    errors.add('release-please.yml: missing $releasePleaseBinariesPublishJob job');
  } else {
    if (publish['uses']?.toString() != releaseBinariesPublishWorkflowPath) {
      errors.add(
        'release-please.yml: $releasePleaseBinariesPublishJob must use $releaseBinariesPublishWorkflowPath',
      );
    }
    errors.addAll(
      _requireExplicitReusableJobPermissions(
        publish,
        null,
        'release-please.yml: $releasePleaseBinariesPublishJob',
      ),
    );
    final perms = publish['permissions'];
    if (perms is! Map || perms['contents']?.toString() != 'write') {
      errors.add(
        'release-please.yml: $releasePleaseBinariesPublishJob needs contents: write',
      );
    }
    if (publish.containsKey('secrets')) {
      errors.add(
        'release-please.yml: $releasePleaseBinariesPublishJob must not pass secrets',
      );
    }
    final needs = _jobNeedsList(publish);
    if (!needs.contains(releasePleaseBinariesBuildJob)) {
      errors.add(
        'release-please.yml: $releasePleaseBinariesPublishJob must need $releasePleaseBinariesBuildJob',
      );
    }
  }

  errors.addAll(_validateReleasePleasePubTrainIndependence(jobsMap));
  errors.addAll(_validateReleasePleaseFinalBinaryAudit(jobsMap));

  final audit = jobsMap[releasePleaseAuditTrainJob];
  if (audit is Map) {
    final p = audit['permissions'];
    if (p.toString().trim() == 'write-all') {
      errors.add(
        'release-please.yml: $releasePleaseAuditTrainJob must use read-only permissions',
      );
    } else if (p is Map) {
      for (final entry in p.entries) {
        if (entry.value?.toString() == 'write') {
          errors.add(
            'release-please.yml: $releasePleaseAuditTrainJob must not request '
            '${entry.key}: write',
          );
        }
      }
    }
  }

  return errors;
}

List<String> _validateReleasePleasePubTrainIndependence(
  Map<dynamic, dynamic> jobsMap,
) {
  final errors = <String>[];
  final dispatch = jobsMap[releasePleaseDispatchPublishJob];
  if (dispatch is Map) {
    final needs = _jobNeedsList(dispatch);
    const forbidden = {'release-binaries-build'};
    for (final n in needs) {
      if (forbidden.contains(n)) {
        errors.add(
          'release-please.yml: $releasePleaseDispatchPublishJob must not need $n',
        );
      }
    }
    if (!needs.contains('release-please')) {
      errors.add(
        'release-please.yml: $releasePleaseDispatchPublishJob must need release-please',
      );
    }
  }

  final wait = jobsMap[releasePleaseWaitPublishJob];
  if (wait is! Map) {
    errors.add('release-please.yml: missing $releasePleaseWaitPublishJob job');
    return errors;
  }
  final waitNeeds = _jobNeedsList(wait);
  for (final n in waitNeeds) {
    if (n == releasePleaseBinariesBuildJob) {
      errors.add(
        'release-please.yml: $releasePleaseWaitPublishJob must not need $n (pub.dev train is independent)',
      );
    }
  }
  if (!waitNeeds.contains('release-please') ||
      !waitNeeds.contains(releasePleaseDispatchPublishJob)) {
    errors.add(
      'release-please.yml: $releasePleaseWaitPublishJob must need release-please and $releasePleaseDispatchPublishJob',
    );
  }
  final waitIf = wait['if']?.toString() ?? '';
  if (!waitIf.contains('always()')) {
    errors.add(
      'release-please.yml: $releasePleaseWaitPublishJob if must include always()',
    );
  }
  if (waitIf.contains('release-binaries-build.result') ||
      waitIf.contains('release-binaries-publish.result')) {
    errors.add(
      'release-please.yml: $releasePleaseWaitPublishJob if must not gate on binary job results',
    );
  }
  return errors;
}

List<String> _validateReleasePleaseFinalBinaryAudit(
  Map<dynamic, dynamic> jobsMap,
) {
  final errors = <String>[];
  final audit = jobsMap[releasePleaseAuditTrainJob];
  if (audit is! Map) {
    errors.add('release-please.yml: missing $releasePleaseAuditTrainJob job');
    return errors;
  }
  final needs = _jobNeedsList(audit);
  for (final required in [
    'release-please',
    releasePleaseDispatchPublishJob,
    releasePleaseWaitPublishJob,
    releasePleaseBinariesBuildJob,
    releasePleaseBinariesPublishJob,
  ]) {
    if (!needs.contains(required)) {
      errors.add(
        'release-please.yml: $releasePleaseAuditTrainJob must need $required',
      );
    }
  }
  final auditIf = audit['if']?.toString() ?? '';
  if (!auditIf.contains('always()')) {
    errors.add(
      'release-please.yml: $releasePleaseAuditTrainJob if must include always()',
    );
  }
  if (!auditIf.contains('wait-package-publish.result == \'success\'') ||
      !auditIf.contains('wait-package-publish.result == \'failure\'')) {
    errors.add(
      'release-please.yml: $releasePleaseAuditTrainJob if must run when wait-package-publish succeeds or fails',
    );
  }
  final steps = audit['steps'];
  if (steps is! List) {
    return errors;
  }
  var sawAuditScript = false;
  for (final step in steps) {
    if (step is! Map) {
      continue;
    }
    final run = step['run']?.toString() ?? '';
    if (run.contains('audit_release_binaries_train.sh')) {
      sawAuditScript = true;
      final env = step['env'];
      if (env is! Map) {
        errors.add(
          'release-please.yml: audit step must pass toolkit/binary results via env:',
        );
      } else {
        for (final key in [
          'TOOLKIT_RELEASE_CREATED',
          'RELEASE_BINARIES_BUILD_RESULT',
          'RELEASE_BINARIES_PUBLISH_RESULT',
        ]) {
          if (!env.containsKey(key)) {
            errors.add(
              'release-please.yml: audit step env must define $key',
            );
          }
        }
      }
      if (run.contains('fromJSON(needs.') || run.contains('\${{ needs.')) {
        errors.add(
          'release-please.yml: audit step run must not inline needs/context expressions',
        );
      }
    }
  }
  if (!sawAuditScript) {
    errors.add(
      'release-please.yml: $releasePleaseAuditTrainJob must run audit_release_binaries_train.sh',
    );
  }
  return errors;
}

List<String> _jobNeedsList(Map<dynamic, dynamic> job) {
  final needs = job['needs'];
  if (needs is List) {
    return needs.map((e) => e.toString()).toList();
  }
  if (needs != null) {
    return [needs.toString()];
  }
  return [];
}

List<String> _validateExplicitSigningSecretsMap(
  dynamic secrets,
  String label,
) {
  final errors = <String>[];
  if (secrets is! Map) {
    errors.add('$label: build job must pass explicit signing secrets map');
    return errors;
  }
  final keys = secrets.keys.map((e) => e.toString()).toSet();
  final expected = requiredReleaseBinariesSigningSecretNames.toSet();
  if (keys.length != expected.length || !keys.containsAll(expected)) {
    errors.add('$label: build job must pass exactly 6 signing secrets by name');
  }
  return errors;
}

List<String> _validateSplitPublishNeeds(
  Map<dynamic, dynamic> jobsMap,
  String label,
) {
  final errors = <String>[];
  final publish = jobsMap['publish'];
  if (publish is! Map) {
    return errors;
  }
  final needs = publish['needs'];
  if (needs == null) {
    return errors;
  }
  final needsList = needs is List
      ? needs.map((e) => e.toString()).toList()
      : [needs.toString()];
  if (needsList.contains('postflight')) {
    errors.add('$label: publish must not need postflight');
  }
  return errors;
}

List<String> _validateSameRunArtifactDownload(
  Map<dynamic, dynamic> jobsMap,
  String label,
) {
  final errors = <String>[];
  final publish = jobsMap['publish'];
  if (publish is! Map) {
    return errors;
  }
  final steps = publish['steps'];
  if (steps is! List) {
    errors.add('$label: publish job must download artifacts from this workflow run');
    return errors;
  }
  var sawDownload = false;
  for (final step in steps) {
    if (step is! Map) {
      continue;
    }
    final uses = step['uses']?.toString() ?? '';
    if (!uses.contains('download-artifact')) {
      continue;
    }
    sawDownload = true;
    final withMap = step['with'];
    if (withMap is Map) {
      if (withMap['run-id'] != null || withMap['github-token'] != null) {
        errors.add(
          '$label: publish download-artifact must not set run-id or github-token (same-run download only)',
        );
      }
    }
  }
  if (!sawDownload) {
    errors.add('$label: publish job must download artifacts from this workflow run');
  }
  return errors;
}

List<String> _validateNoInlineWorkflowExprsInRun(
  Map<dynamic, dynamic> jobsMap,
  String label,
) {
  final errors = <String>[];
  final pattern = RegExp(r'\$\{\{\s*(inputs\.|needs\.|steps\.)');
  for (final job in jobsMap.values) {
    if (job is! Map) {
      continue;
    }
    final steps = job['steps'];
    if (steps is! List) {
      continue;
    }
    for (final step in steps) {
      if (step is! Map) {
        continue;
      }
      final run = step['run']?.toString() ?? '';
      if (pattern.hasMatch(run)) {
        final name = step['name']?.toString() ?? '';
        errors.add(
          '$label: step `$name` must pass inputs/needs via env, not inline in run:',
        );
      }
    }
  }
  return errors;
}

List<String> _validateBuildMatrix(
  Map<dynamic, dynamic> jobsMap,
  String label,
) {
  final errors = <String>[];
  final build = jobsMap['build'];
  if (build is! Map) {
    return errors;
  }
  final strategy = build['strategy'];
  if (strategy is! Map) {
    errors.add('$label: build must define strategy.matrix');
    return errors;
  }
  final matrix = strategy['matrix'];
  if (matrix is! Map) {
    errors.add('$label: build must define strategy.matrix');
    return errors;
  }
  final include = matrix['include'];
  if (include is! List) {
    errors.add('$label: build matrix must use include list');
    return errors;
  }
  final triples = <String>[];
  for (final row in include) {
    if (row is Map && row['triple'] != null) {
      triples.add(row['triple'].toString());
    }
  }
  triples.sort();
  final expected = [...requiredBuildMatrixTriples]..sort();
  if (triples.length != 4 || !triples.every(expected.contains)) {
    errors.add(
      '$label: build matrix must include exactly ${requiredBuildMatrixTriples.join(", ")} '
      '(got ${triples.join(", ")})',
    );
  }
  return errors;
}

List<String> _validatePublishNeeds(
  Map<dynamic, dynamic> jobsMap,
  String label,
) {
  final errors = <String>[];
  final publish = jobsMap['publish'];
  if (publish is! Map) {
    return errors;
  }
  final needs = publish['needs'];
  final needsList = needs is List
      ? needs.map((e) => e.toString()).toList()
      : needs != null
          ? [needs.toString()]
          : <String>[];
  needsList.sort();
  final expected = ['build', 'prepare']..sort();
  final sorted = [...needsList]..sort();
  if (sorted.length != 2 || !sorted.every(expected.contains)) {
    errors.add(
      '$label: publish needs must be exactly [prepare, build] (got $needsList)',
    );
  }
  return errors;
}

List<String> _validateGhReleaseAssets(
  Map<dynamic, dynamic> jobsMap,
  String label,
) {
  final errors = <String>[];
  final publish = jobsMap['publish'];
  if (publish is! Map) {
    return errors;
  }
  final steps = publish['steps'];
  if (steps is! List) {
    return errors;
  }
  for (final step in steps) {
    if (step is! Map) {
      continue;
    }
    final uses = step['uses']?.toString() ?? '';
    if (!uses.contains('action-gh-release')) {
      continue;
    }
    final withMap = step['with'];
    if (withMap is! Map) {
      errors.add('$label: action-gh-release step missing with:');
      return errors;
    }
    if (withMap['fail_on_unmatched_files'] != true) {
      errors.add('$label: action-gh-release must set fail_on_unmatched_files: true');
    }
    final files = withMap['files']?.toString() ?? '';
    for (final suffix in requiredGhReleaseAssetSuffixes) {
      if (!files.contains(suffix)) {
        errors.add(
          '$label: action-gh-release files must include *$suffix',
        );
      }
    }
  }
  return errors;
}

List<String> _validateContentsWriteScope(
  Map<dynamic, dynamic> jobsMap,
  Map<dynamic, dynamic> root,
  String label,
) {
  final errors = <String>[];
  final workflowPerms = root['permissions'];
  if (workflowPerms is Map && workflowPerms['contents']?.toString() == 'write') {
    errors.add('$label: workflow-level permissions must not set contents: write');
  }
  for (final entry in jobsMap.entries) {
    final jobId = entry.key.toString();
    final job = entry.value;
    if (job is! Map) {
      continue;
    }
    final perms = job['permissions'];
    if (perms is! Map) {
      continue;
    }
    if (perms['contents']?.toString() == 'write' && jobId != 'publish') {
      errors.add(
        '$label: only publish job may set contents: write (got $jobId)',
      );
    }
  }
  final publish = jobsMap['publish'];
  if (publish is Map) {
    final perms = publish['permissions'];
    if (perms is! Map || perms['contents']?.toString() != 'write') {
      errors.add('$label: publish job must set permissions.contents: write');
    }
  }
  return errors;
}

List<String> _validateBuildHasNoReleasePublishSteps(String yamlText, String label) {
  final errors = <String>[];
  if (yamlText.contains('action-gh-release')) {
    errors.add('$label: must not use action-gh-release (publish is a separate reusable)');
  }
  if (RegExp(r'assert_release_assets_complete\.sh').hasMatch(yamlText)) {
    errors.add(
      '$label: must not run assert_release_assets_complete.sh (postflight is publish reusable)',
    );
  }
  return errors;
}

List<String> _validateRequiredScriptSteps(
  Map<dynamic, dynamic> jobsMap,
  String label,
  Map<String, String> scripts,
) {
  final errors = <String>[];
  for (final entry in scripts.entries) {
    final script = entry.key;
    final jobId = entry.value;
    final job = jobsMap[jobId];
    if (job is! Map) {
      errors.add('$label: missing job $jobId for required script $script');
      continue;
    }
    final unconditional =
        _unconditionalScriptSteps(job).where((s) => _stepInvokesScript(s, script)).toList();
    final conditional =
        _conditionalScriptSteps(job).where((s) => _stepInvokesScript(s, script)).toList();

    if (unconditional.length != 1) {
      errors.add(
        '$label: job $jobId must have exactly one unconditional step running $script '
        '(found ${unconditional.length})',
      );
    }
    if (conditional.isNotEmpty) {
      errors.add(
        '$label: job $jobId must not run $script in conditional steps '
        '(found ${conditional.length} with if:)',
      );
    }
  }
  return errors;
}

List<String> _validateRunBlocksBeforeScripts(
  Map<dynamic, dynamic> jobsMap,
  String label,
  Map<String, String> scripts,
) {
  final errors = <String>[];
  for (final script in scripts.keys) {
    for (final job in jobsMap.values) {
      if (job is! Map) {
        continue;
      }
      final steps = job['steps'];
      if (steps is! List) {
        continue;
      }
      for (final step in steps) {
        if (step is! Map) {
          continue;
        }
        if (!_stepInvokesScript(step, script)) {
          continue;
        }
        final run = step['run']?.toString() ?? '';
        if (_runDisablesEerrexitBeforeScript(run, script)) {
          errors.add(
            '$label: step `${step['name']}` must not use exit 0/set +e before $script',
          );
        }
        if (step.containsKey('if')) {
          errors.add(
            '$label: required script $script must not run under step if: '
            '(step `${step['name']}`)',
          );
        }
        if (step['continue-on-error'] == true) {
          errors.add(
            '$label: step running $script must not set continue-on-error',
          );
        }
        final trimmedRun = run.trim();
        if (trimmedRun.contains('|| true') || trimmedRun.contains('|| :')) {
          errors.add('$label: step running $script must not use || true/|| :');
        }
      }
    }
  }
  return errors;
}

bool _runDisablesEerrexitBeforeScript(String run, String script) {
  final escaped = RegExp.escape(script);
  final invoke = RegExp(r'(bash|sh)\s+.*' + escaped);
  var seenScript = false;
  for (final line in run.split('\n')) {
    final command = _stripInlineComment(line).trim();
    if (command.isEmpty) {
      continue;
    }
    if (!seenScript) {
      if (RegExp(r'^(exit\s+0|set\s+\+e)\b').hasMatch(command)) {
        return true;
      }
      if (invoke.hasMatch(command)) {
        seenScript = true;
      }
    }
  }
  return false;
}

List<Map<dynamic, dynamic>> _unconditionalScriptSteps(Map<dynamic, dynamic> job) {
  final steps = job['steps'];
  if (steps is! List) {
    return [];
  }
  return steps
      .whereType<Map>()
      .where((s) => !s.containsKey('if'))
      .toList();
}

List<Map<dynamic, dynamic>> _conditionalScriptSteps(Map<dynamic, dynamic> job) {
  final steps = job['steps'];
  if (steps is! List) {
    return [];
  }
  return steps.whereType<Map>().where((s) => s.containsKey('if')).toList();
}

bool _stepInvokesScript(Map<dynamic, dynamic> step, String scriptName) {
  return _stepRunsScriptAtCommandStart(step, scriptName);
}

List<String> _workflowSecretsOutsideAllowlist(
  Map<dynamic, dynamic> jobsMap,
  String yamlText,
  String label,
) {
  final errors = <String>[];
  final secretPattern = RegExp(r'\$\{\{\s*secrets\.\w+');

  for (final entry in jobsMap.entries) {
    final jobId = entry.key.toString();
    final job = entry.value;
    if (job is! Map) {
      continue;
    }
    final jobEnv = job['env'];
    if (jobEnv is Map) {
      if (jobId == 'build') {
        for (final key in jobEnv.keys) {
          final k = key.toString();
          if (allowedBuildJobEnvSecretKeys.contains(k)) {
            continue;
          }
          if (jobEnv[key].toString().contains('secrets.')) {
            errors.add(
              '$label: build job env may only reference secrets in '
              '${allowedBuildJobEnvSecretKeys.join(", ")}',
            );
          }
        }
      } else {
        for (final v in jobEnv.values) {
          if (v.toString().contains('secrets.')) {
            errors.add('$label: job $jobId must not set secrets in job-level env');
          }
        }
      }
    }

    final steps = job['steps'];
    if (steps is! List) {
      continue;
    }
    for (final step in steps) {
      if (step is! Map) {
        continue;
      }
      final stepName = step['name']?.toString() ?? '';
      if (step.containsKey('if')) {
        final ifExpr = step['if'].toString();
        if (secretPattern.hasMatch(ifExpr) ||
            RegExp(r'\bsecrets\.\w+').hasMatch(ifExpr)) {
          errors.add(
            '$label: step `$stepName` must not reference secrets in if:',
          );
        }
      }
      final stepEnv = step['env'];
      if (stepEnv is Map) {
        final referencesSecrets =
            stepEnv.values.any((v) => v.toString().contains('secrets.'));
        if (referencesSecrets &&
            !(jobId == 'build' && stepName == signStepName)) {
          errors.add(
            '$label: secrets in step env only allowed on build/$signStepName '
            '(got $jobId/$stepName)',
          );
        }
      }
      final withMap = step['with'];
      if (withMap is Map) {
        for (final v in withMap.values) {
          if (v.toString().contains('secrets.')) {
            errors.add('$label: step `$stepName` must not reference secrets in with:');
          }
        }
      }
      final run = step['run']?.toString() ?? '';
      if (run.contains('secrets.') && !(jobId == 'build' && stepName == signStepName)) {
        errors.add('$label: step `$stepName` must not reference secrets in run:');
      }
    }
  }

  return errors;
}

List<String> _validateSigningSecretsScope(
  Map<dynamic, dynamic> buildJob,
  String label,
) {
  final errors = <String>[];
  final env = buildJob['env'];
  if (env is! Map) {
    return errors;
  }
  for (final key in env.keys) {
    if (allowedBuildJobEnvSecretKeys.contains(key.toString())) {
      continue;
    }
    final val = env[key].toString();
    if (val.contains('secrets.')) {
      errors.add('$label: build job env may only reference secrets in HAS_* keys');
    }
  }
  return errors;
}

bool _publishUsesAppendBody(dynamic publishJob) {
  if (publishJob is! Map) {
    return false;
  }
  final steps = publishJob['steps'];
  if (steps is! List) {
    return false;
  }
  for (final step in steps) {
    if (step is! Map) {
      continue;
    }
    final uses = step['uses']?.toString() ?? '';
    if (!uses.contains('action-gh-release')) {
      continue;
    }
    final withMap = step['with'];
    if (withMap is Map && withMap['append_body'] == true) {
      return true;
    }
  }
  return false;
}

bool _allCheckoutsPersistFalse(Map<dynamic, dynamic> jobsMap) {
  var sawCheckout = false;
  for (final job in jobsMap.values) {
    if (job is! Map) {
      continue;
    }
    final steps = job['steps'];
    if (steps is! List) {
      continue;
    }
    for (final step in steps) {
      if (step is! Map) {
        continue;
      }
      final uses = step['uses']?.toString() ?? '';
      if (!uses.startsWith('actions/checkout')) {
        continue;
      }
      sawCheckout = true;
      final withMap = step['with'];
      if (withMap is! Map || withMap['persist-credentials'] != false) {
        return false;
      }
    }
  }
  return sawCheckout;
}

/// True when [scriptName] is invoked via `bash …/scriptName` on a real command line.
bool _stepRunsScriptAtCommandStart(dynamic step, String scriptName) {
  if (step is! Map) {
    return false;
  }
  final run = step['run'];
  if (run is! String) {
    return false;
  }
  final escaped = RegExp.escape(scriptName);
  final invokePattern = RegExp(r'^(bash|sh)\s+.*' + escaped);
  for (final line in run.split('\n')) {
    final command = _stripInlineComment(line).trim();
    if (command.isEmpty || command.startsWith('#')) {
      continue;
    }
    if (RegExp(r'^true\b').hasMatch(command)) {
      continue;
    }
    if (invokePattern.hasMatch(command)) {
      return true;
    }
  }
  return false;
}

String _stripInlineComment(String line) {
  var inSingle = false;
  var inDouble = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == "'" && !inDouble) {
      inSingle = !inSingle;
      continue;
    }
    if (c == '"' && !inSingle) {
      inDouble = !inDouble;
      continue;
    }
    if (c == '#' && !inSingle && !inDouble) {
      return line.substring(0, i);
    }
  }
  return line;
}

/// Validates [releaseBinariesRunListJsonFields] ⊆ gh documented fields.
List<String> validateGhRunListJsonFieldAllowlist(
  String commaSeparatedFields, {
  List<String> allowlist = ghRunListJsonFieldsGh21030,
}) {
  final errors = <String>[];
  final requested = commaSeparatedFields
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final allow = allowlist.toSet();
  for (final field in requested) {
    if (!allow.contains(field)) {
      errors.add(
        'gh run list --json field "$field" is not in gh 2.103.0 allowlist',
      );
    }
  }
  return errors;
}