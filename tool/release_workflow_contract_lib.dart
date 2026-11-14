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

const exactReleaseBinariesRunName = 'release-binaries \${{ inputs.release_tag }}';
const exactPublishIf = 'inputs.dry_run != true';
const exactPostflightIf = 'inputs.dry_run != true';
const exactDryRunBundleIf = 'inputs.dry_run == true';

const signStepName = 'Sign macOS bundle';

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
    for (final key in onMap.keys) {
      if (key == 'workflow_dispatch') {
        continue;
      }
      errors.add('$label: forbidden on.$key trigger (dispatch only)');
    }
    final wd = onMap['workflow_dispatch'];
    if (wd is Map) {
      final inputs = Map<dynamic, dynamic>.from(
        (wd['inputs'] as Map?) ?? {},
      );
      if (!inputs.containsKey('release_tag')) {
        errors.add('$label: workflow_dispatch.inputs.release_tag required');
      }
      if (!inputs.containsKey('dry_run')) {
        errors.add('$label: workflow_dispatch.inputs.dry_run required');
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

  final postflight = jobsMap['postflight'];
  if (postflight is Map) {
    final needs = postflight['needs'];
    final needsList =
        needs is List ? needs.map((e) => e.toString()).toList() : <String>[];
    if (!needsList.contains('prepare') || !needsList.contains('publish')) {
      errors.add('$label: postflight must need prepare and publish');
    }
    if (!_stepRunsScriptAtCommandStart(
      postflight,
      'assert_release_assets_complete.sh',
    )) {
      errors.add(
        '$label: postflight must invoke assert_release_assets_complete.sh as a command',
      );
    }
    errors.addAll(
      _requiredRunStepViolations(
        postflight,
        label,
        stepNameHint: 'Assert release',
      ),
    );
  }

  final build = jobsMap['build'];
  if (build is Map) {
    final needs = build['needs'];
    if (needs?.toString() != 'prepare') {
      errors.add('$label: build must need prepare');
    }
    errors.addAll(_validateSigningSecretsScope(build, label));
    errors.addAll(
      _requiredRunStepViolations(
        build,
        label,
        scriptName: 'verify_release_tarball_architecture.sh',
        stepNameHint: 'Verify archive architecture',
      ),
    );
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

  errors.addAll(_workflowSecretsOutsideAllowlist(jobsMap, label));

  return errors;
}

List<String> _workflowSecretsOutsideAllowlist(
  Map<dynamic, dynamic> jobsMap,
  String label,
) {
  final errors = <String>[];

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
          if (key == 'HAS_SIGNING') {
            continue;
          }
          if (jobEnv[key].toString().contains('secrets.')) {
            errors.add(
              '$label: build job env may only reference secrets in HAS_SIGNING',
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
      final stepEnv = step['env'];
      if (stepEnv is! Map) {
        continue;
      }
      final referencesSecrets =
          stepEnv.values.any((v) => v.toString().contains('secrets.'));
      if (!referencesSecrets) {
        continue;
      }
      final allowed =
          jobId == 'build' && stepName == signStepName;
      if (!allowed) {
        errors.add(
          '$label: secrets in step env only allowed on build/$signStepName (got $jobId/$stepName)',
        );
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
    if (key == 'HAS_SIGNING') {
      continue;
    }
    final val = env[key].toString();
    if (val.contains('secrets.')) {
      errors.add('$label: build job env may only reference secrets in HAS_SIGNING');
    }
  }
  return errors;
}

List<String> _requiredRunStepViolations(
  Map<dynamic, dynamic> job,
  String label, {
  String? scriptName,
  String? stepNameHint,
}) {
  final errors = <String>[];
  final steps = job['steps'];
  if (steps is! List) {
    return errors;
  }
  for (final step in steps) {
    if (step is! Map) {
      continue;
    }
    final name = step['name']?.toString() ?? '';
    if (stepNameHint != null && !name.contains(stepNameHint)) {
      if (scriptName != null && !_stepRunsScriptAtCommandStart(step, scriptName)) {
        continue;
      }
    }
    if (scriptName != null) {
      final run = step['run'];
      if (run is! String || !run.contains(scriptName)) {
        continue;
      }
    } else if (stepNameHint != null && !name.contains(stepNameHint)) {
      continue;
    }

    if (step.containsKey('if')) {
      errors.add('$label: step `$name` must not use `if:`');
    }
    if (step['continue-on-error'] == true) {
      errors.add('$label: step `$name` must not set continue-on-error');
    }
    final run = step['run']?.toString() ?? '';
    if (run.contains('|| true') || run.contains('|| :')) {
      errors.add('$label: step `$name` must not use `|| true` or `|| :`');
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
bool _stepRunsScriptAtCommandStart(dynamic jobOrStep, String scriptName) {
  final steps = jobOrStep is Map && jobOrStep.containsKey('steps')
      ? jobOrStep['steps']
      : [jobOrStep];
  if (steps is! List) {
    return false;
  }
  final escaped = RegExp.escape(scriptName);
  final invokePattern = RegExp(r'^(bash|sh)\s+.*' + escaped);
  for (final step in steps) {
    if (step is! Map) {
      continue;
    }
    final run = step['run'];
    if (run is! String) {
      continue;
    }
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