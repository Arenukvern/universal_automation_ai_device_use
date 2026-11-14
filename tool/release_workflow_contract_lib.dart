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

const exactReleaseBinariesRunName = r'release-binaries ${{ inputs.release_tag }}';
const exactPublishIf = 'inputs.dry_run != true';
const exactPostflightIf = 'inputs.dry_run != true';
const exactDryRunBundleIf = 'inputs.dry_run == true';

const signStepName = 'Sign macOS bundle';

const requiredScriptSteps = <String, String>{
  'assert_release_assets_complete.sh': 'postflight',
  'verify_release_tarball_architecture.sh': 'build',
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

/// Structural validation for `.github/workflows/release_binaries.yml`.
List<String> validateReleaseBinariesWorkflowYaml(
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
  if (on is! Map) {
    errors.add('$label: on must be a mapping');
  } else {
    final onMap = Map<dynamic, dynamic>.from(on);
    if (!onMap.containsKey('workflow_dispatch')) {
      errors.add('$label: on.workflow_dispatch is required');
    }
    if (!onMap.containsKey('workflow_call')) {
      errors.add('$label: on.workflow_call is required');
    }
    const allowedOnKeys = {'workflow_dispatch', 'workflow_call'};
    for (final key in onMap.keys) {
      if (!allowedOnKeys.contains(key.toString())) {
        errors.add(
          '$label: forbidden on.$key trigger (workflow_dispatch + workflow_call only)',
        );
      }
    }
    for (final trigger in ['workflow_dispatch', 'workflow_call']) {
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
    }
  }

  final jobs = root['jobs'];
  if (jobs is! Map) {
    errors.add('$label: jobs must be a mapping');
    return errors;
  }
  final jobsMap = Map<dynamic, dynamic>.from(jobs);

  const requiredJobs = ['prepare', 'build', 'publish', 'postflight'];
  for (final id in requiredJobs) {
    if (!jobsMap.containsKey(id)) {
      errors.add('$label: missing job $id');
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

  requireExactJobIf('publish', exactPublishIf);
  requireExactJobIf('postflight', exactPostflightIf);
  requireExactJobIf('dry-run-bundle', exactDryRunBundleIf);

  for (final entry in jobsMap.entries) {
    final job = entry.value;
    if (job is Map && job['continue-on-error'] == true) {
      errors.add('$label: job ${entry.key} must not set continue-on-error');
    }
  }

  errors.addAll(_validateRequiredScriptSteps(jobsMap, label));
  errors.addAll(_validateRunBlocksBeforeScripts(jobsMap, label));

  final postflight = jobsMap['postflight'];
  if (postflight is Map) {
    final needs = postflight['needs'];
    final needsList =
        needs is List ? needs.map((e) => e.toString()).toList() : <String>[];
    if (!needsList.contains('prepare') || !needsList.contains('publish')) {
      errors.add('$label: postflight must need prepare and publish');
    }
  }

  final build = jobsMap['build'];
  if (build is Map) {
    final needs = build['needs'];
    if (needs?.toString() != 'prepare') {
      errors.add('$label: build must need prepare');
    }
    errors.addAll(_validateSigningSecretsScope(build, label));
  }

  if (!jobsMap.containsKey('dry-run-bundle')) {
    errors.add('$label: missing dry-run-bundle job for artifact-only dry runs');
  }

  final runName = root['run-name']?.toString().trim() ?? '';
  if (runName != exactReleaseBinariesRunName) {
    errors.add(
      '$label: run-name must be exactly `$exactReleaseBinariesRunName`',
    );
  }

  if (!_allCheckoutsPersistFalse(jobsMap)) {
    errors.add('$label: every actions/checkout must set persist-credentials: false');
  }

  if (!_publishUsesAppendBody(jobsMap['publish'])) {
    errors.add('$label: publish job must set append_body: true on action-gh-release');
  }

  errors.addAll(_workflowSecretsOutsideAllowlist(jobsMap, yamlText, label));
  errors.addAll(_validateBuildMatrix(jobsMap, label));
  errors.addAll(_validatePublishNeeds(jobsMap, label));
  errors.addAll(_validateGhReleaseAssets(jobsMap, label));
  errors.addAll(_validateContentsWriteScope(jobsMap, root, label));

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
    errors.add('$label: must define a reusable-workflow caller job');
    return errors;
  }
  final jobsMap = Map<dynamic, dynamic>.from(jobs);
  if (jobsMap.length != 1) {
    errors.add('$label: exactly one caller job expected');
  }
  for (final entry in jobsMap.entries) {
    final job = entry.value;
    if (job is! Map) {
      continue;
    }
    final uses = job['uses']?.toString() ?? '';
    if (!uses.contains('release_binaries.yml')) {
      errors.add('$label: job ${entry.key} must use release_binaries.yml');
    }
    if (!uses.contains('refs/heads/cursor/release-binaries-auto-99f0') &&
        !uses.contains('./.github/workflows/release_binaries.yml')) {
      errors.add(
        '$label: job ${entry.key} must reference release_binaries.yml '
        '(./ when on main, or refs/heads/cursor/… until merged)',
      );
    }
    final withMap = job['with'];
    if (withMap is! Map) {
      errors.add('$label: job ${entry.key} must pass with:');
      continue;
    }
    final dryRun = withMap['dry_run'];
    if (dryRun != true && dryRun?.toString() != 'true') {
      errors.add(
        '$label: job ${entry.key} must pass dry_run: true literally',
      );
    }
    final perms = job['permissions'];
    if (perms is Map && perms['contents']?.toString() != 'read') {
      errors.add('$label: caller job permissions.contents must be read');
    }
  }

  return errors;
}

/// Caller job in release-please.yml must invoke release_binaries with dry_run false.
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
  final caller = jobsMap['release-binaries'];
  if (caller is! Map) {
    return ['release-please.yml: missing release-binaries reusable-workflow job'];
  }
  final uses = caller['uses']?.toString() ?? '';
  if (!uses.contains('release_binaries.yml')) {
    errors.add('release-please.yml: release-binaries must use release_binaries.yml');
  }
  final withMap = caller['with'];
  if (withMap is! Map) {
    errors.add('release-please.yml: release-binaries must pass with:');
  } else {
    final dryRun = withMap['dry_run'];
    if (dryRun != false && dryRun?.toString() != 'false') {
      errors.add('release-please.yml: release-binaries must pass dry_run: false');
    }
  }
  final perms = caller['permissions'];
  if (perms is Map && perms['contents']?.toString() != 'write') {
    errors.add('release-please.yml: release-binaries job needs contents: write');
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

List<String> _validateRequiredScriptSteps(
  Map<dynamic, dynamic> jobsMap,
  String label,
) {
  final errors = <String>[];
  for (final entry in requiredScriptSteps.entries) {
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
) {
  final errors = <String>[];
  for (final script in requiredScriptSteps.keys) {
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