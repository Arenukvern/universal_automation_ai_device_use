/// Structural publish-job contract (allowlists; no spelling scans).

const publishJobAllowedUses = <String>[
  'actions/checkout@v7',
  'actions/download-artifact@v4',
];

const publishJobRunScriptsInOrder = <String>[
  'generate_release_checksums_in_dist.sh',
  'check_release_assets_conflict.sh',
  'assert_github_release_is_draft.sh',
  'validate_release_checksums_file.sh',
  'append_binary_install_notes_to_draft_release.sh',
  'upload_draft_github_release_assets.sh',
  'assert_release_assets_complete_on_draft.sh',
  'publish_github_release_from_draft.sh',
];

const undraftAllowedScript = 'publish_github_release_from_draft.sh';

/// Closure scripts not invoked directly from the publish job YAML steps.
const publishScriptClosureExtras = <String>[
  'append_draft_release_binary_notes.sh',
  'assert_release_assets_complete.sh',
];

const publishWorkflowRootEnvPins = <String, String>{
  'TOOLING_CHECKOUT_PATH': '_tooling',
};

Set<String> releasePublishRequiredPinKeys() {
  final keys = <String>{};
  for (final name in publishJobRunScriptsInOrder) {
    keys.add('tool/release/$name');
  }
  for (final name in publishScriptClosureExtras) {
    keys.add('tool/release/$name');
  }
  return keys;
}

List<String> validatePublishWorkflowRoot(Map<dynamic, dynamic> root, String label) {
  final errors = <String>[];
  if (root.containsKey('defaults')) {
    errors.add('$label: must not set top-level defaults');
  }
  final env = root['env'];
  if (env is! Map) {
    errors.add('$label: workflow env block is required');
    return errors;
  }
  errors.addAll(
    _validateEnvPins(
      env,
      publishWorkflowRootEnvPins,
      label,
      'workflow env',
    ),
  );
  return errors;
}

const publishJobAllowedKeys = <String>{
  'permissions',
  'runs-on',
  'timeout-minutes',
  'env',
  'steps',
};

const publishJobForbiddenKeys = <String>{
  'if',
  'strategy',
  'continue-on-error',
  'defaults',
  'needs',
  'container',
  'services',
  'outputs',
  'concurrency',
};

const publishRunStepAllowedKeys = <String>{'name', 'env', 'run'};

const publishUsesStepAllowedKeys = <String>{'name', 'uses', 'with'};

const publishStepForbiddenKeys = <String>{
  'if',
  'shell',
  'working-directory',
  'continue-on-error',
  'timeout-minutes',
};

const publishJobEnvPins = <String, Object>{
  'RELEASE_TAG': r'${{ inputs.release_tag }}',
  'VERSION': r'${{ inputs.version }}',
};

const checkoutActionWithPins = <String, Object>{
  'ref': r'${{ inputs.tooling_ref }}',
  'path': r'${{ env.TOOLING_CHECKOUT_PATH }}',
  'persist-credentials': false,
};

const downloadArtifactWithPins = <String, Object>{
  'path': 'dist/release',
  'pattern': 'release-*',
  'merge-multiple': true,
};

const publishRunStepEnvPins = <String, Map<String, String>>{
  'generate_release_checksums_in_dist.sh': {
    'VERSION': r'${{ inputs.version }}',
  },
  'check_release_assets_conflict.sh': {
    'GH_TOKEN': r'${{ github.token }}',
    'GITHUB_REPOSITORY': r'${{ github.repository }}',
    'RELEASE_TAG': r'${{ inputs.release_tag }}',
    'VERSION': r'${{ inputs.version }}',
  },
  'assert_github_release_is_draft.sh': {
    'GH_TOKEN': r'${{ github.token }}',
    'GITHUB_REPOSITORY': r'${{ github.repository }}',
    'RELEASE_TAG': r'${{ inputs.release_tag }}',
  },
  'validate_release_checksums_file.sh': {
    'VERSION': r'${{ inputs.version }}',
  },
  'append_binary_install_notes_to_draft_release.sh': {
    'GH_TOKEN': r'${{ github.token }}',
    'GITHUB_REPOSITORY': r'${{ github.repository }}',
    'RELEASE_TAG': r'${{ inputs.release_tag }}',
    'VERSION': r'${{ inputs.version }}',
    'GITHUB_REPOSITORY_SLUG': r'${{ github.repository }}',
  },
  'upload_draft_github_release_assets.sh': {
    'GH_TOKEN': r'${{ github.token }}',
    'GITHUB_REPOSITORY': r'${{ github.repository }}',
    'RELEASE_TAG': r'${{ inputs.release_tag }}',
    'VERSION': r'${{ inputs.version }}',
  },
  'assert_release_assets_complete_on_draft.sh': {
    'GH_TOKEN': r'${{ github.token }}',
    'GITHUB_REPOSITORY': r'${{ github.repository }}',
    'RELEASE_TAG': r'${{ inputs.release_tag }}',
    'VERSION': r'${{ inputs.version }}',
  },
  'publish_github_release_from_draft.sh': {
    'GH_TOKEN': r'${{ github.token }}',
    'GITHUB_REPOSITORY': r'${{ github.repository }}',
    'RELEASE_TAG': r'${{ inputs.release_tag }}',
  },
};

const publishRunStepLiteralArgs = <String, List<String>>{
  'validate_release_checksums_file.sh': ['dist/release/checksums.txt'],
  'upload_draft_github_release_assets.sh': ['dist/release'],
};

const publishForbiddenStepEnvKeys = <String>{
  'BASH_ENV',
  'ENV',
  'TOOLING_CHECKOUT_PATH',
};

List<String> validatePublishJobStructure(
  Map<dynamic, dynamic> jobsMap,
  String label,
) {
  final errors = <String>[];
  final publish = jobsMap['publish'];
  if (publish is! Map) {
    return errors;
  }

  errors.addAll(_validatePublishJobKeys(publish, label));

  final jobEnv = publish['env'];
  if (jobEnv is Map) {
    errors.addAll(_validateEnvPins(jobEnv, publishJobEnvPins, label, 'publish job env'));
  } else {
    errors.add('$label: publish job must define env');
  }

  final steps = publish['steps'];
  if (steps is! List) {
    return errors;
  }

  final runScripts = <String>[];
  for (var i = 0; i < steps.length; i++) {
    final step = steps[i];
    if (step is! Map) {
      continue;
    }
    final name = step['name']?.toString() ?? 'step $i';
    errors.addAll(_validatePublishStepKeys(step, label, name));

    final uses = step['uses']?.toString() ?? '';
    final run = step['run']?.toString() ?? '';

    if (uses.isNotEmpty) {
      if (!publishJobAllowedUses.contains(uses)) {
        errors.add(
          '$label: publish job step `$name` uses disallowed action: $uses',
        );
      }
      if (run.isNotEmpty) {
        errors.add('$label: publish job step `$name` must not mix uses and run');
      }
      final withMap = step['with'];
      if (uses == 'actions/checkout@v7') {
        errors.addAll(
          _validateWithPins(withMap, checkoutActionWithPins, label, name),
        );
      } else if (uses == 'actions/download-artifact@v4') {
        errors.addAll(
          _validateWithPins(withMap, downloadArtifactWithPins, label, name),
        );
      }
      continue;
    }

    if (run.isEmpty) {
      errors.add('$label: publish job step `$name` has no run block');
      continue;
    }

    if (step['env'] is Map) {
      errors.addAll(_validatePublishRunStepEnv(step['env'] as Map, label, name));
    }

    final parsed = parseSingleReleaseScriptRun(run);
    if (parsed == null) {
      errors.add(
        '$label: publish job step `$name` must be exactly one '
        'bash tool/release/<script>.sh invocation',
      );
      continue;
    }
    errors.addAll(_validateRunScriptArgs(run, parsed, label, name));
    if (runDeclaresInlineUndraftEscape(run)) {
      errors.add(
        '$label: publish job step `$name` must not undraft inline '
        '(only $undraftAllowedScript may publish the draft release)',
      );
    }

    final envPins = publishRunStepEnvPins[parsed];
    if (envPins != null && step['env'] is Map) {
      errors.addAll(
        _validateEnvPins(step['env'] as Map, envPins, label, 'step `$name` env'),
      );
    } else if (envPins != null) {
      errors.add('$label: step `$name` missing required env block');
    }

    runScripts.add(parsed);
  }

  if (runScripts.length != publishJobRunScriptsInOrder.length) {
    errors.add(
      '$label: publish job must have exactly ${publishJobRunScriptsInOrder.length} '
      'tool/release run steps (got ${runScripts.length})',
    );
    return errors;
  }

  for (var i = 0; i < publishJobRunScriptsInOrder.length; i++) {
    if (runScripts[i] != publishJobRunScriptsInOrder[i]) {
      errors.add(
        '$label: publish run script #${i + 1} must be '
        '${publishJobRunScriptsInOrder[i]} (got ${runScripts[i]})',
      );
    }
  }

  if (runScripts.isNotEmpty && runScripts.last != undraftAllowedScript) {
    errors.add(
      '$label: publish job last step must invoke $undraftAllowedScript only',
    );
  }

  return errors;
}

List<String> _validatePublishJobKeys(Map publish, String label) {
  final errors = <String>[];
  for (final key in publish.keys) {
    final k = key.toString();
    if (publishJobForbiddenKeys.contains(k)) {
      errors.add('$label: publish job forbids key $k');
    } else if (!publishJobAllowedKeys.contains(k)) {
      errors.add('$label: publish job disallows unknown key $k');
    }
  }
  return errors;
}

List<String> _validatePublishStepKeys(Map step, String label, String name) {
  final errors = <String>[];
  for (final key in step.keys) {
    final k = key.toString();
    if (publishStepForbiddenKeys.contains(k)) {
      errors.add('$label: publish job step `$name` forbids key $k');
    }
  }
  final uses = step['uses']?.toString() ?? '';
  final allowed =
      uses.isNotEmpty ? publishUsesStepAllowedKeys : publishRunStepAllowedKeys;
  for (final key in step.keys) {
    final k = key.toString();
    if (!allowed.contains(k)) {
      errors.add('$label: publish job step `$name` disallows unknown key $k');
    }
  }
  return errors;
}

List<String> _validatePublishRunStepEnv(Map env, String label, String name) {
  final errors = <String>[];
  for (final key in env.keys) {
    if (publishForbiddenStepEnvKeys.contains(key.toString())) {
      errors.add(
        '$label: publish job step `$name` must not set env $key',
      );
    }
  }
  return errors;
}

List<String> _validateEnvPins(
  Map env,
  Map<String, Object> pins,
  String label,
  String ctx,
) {
  final errors = <String>[];
  for (final key in env.keys) {
    final k = key.toString();
    if (!pins.containsKey(k)) {
      errors.add('$label: $ctx has unknown env key $k');
    }
  }
  for (final entry in pins.entries) {
    final got = env[entry.key];
    if (got == null) {
      errors.add('$label: $ctx missing env ${entry.key}');
      continue;
    }
    if (!_envValueMatches(got, entry.value)) {
      errors.add(
        '$label: $ctx env ${entry.key} must be exactly `${entry.value}`',
      );
    }
  }
  return errors;
}

bool _envValueMatches(Object got, Object want) {
  if (want is bool) {
    return got == want;
  }
  return got.toString() == want.toString();
}

List<String> _validateWithPins(
  dynamic withMap,
  Map<String, Object> pins,
  String label,
  String stepName,
) {
  final errors = <String>[];
  if (withMap is! Map) {
    errors.add('$label: step `$stepName` missing action with: block');
    return errors;
  }
  for (final key in withMap.keys) {
    if (!pins.containsKey(key.toString())) {
      errors.add(
        '$label: step `$stepName` with: has unknown key $key',
      );
    }
  }
  for (final entry in pins.entries) {
    final got = withMap[entry.key];
    if (got == null) {
      errors.add('$label: step `$stepName` with: missing ${entry.key}');
      continue;
    }
    if (!_envValueMatches(got, entry.value)) {
      errors.add(
        '$label: step `$stepName` with.${entry.key} must be exactly '
        '`${entry.value}`',
      );
    }
  }
  return errors;
}

List<String> _validateRunScriptArgs(
  String run,
  String script,
  String label,
  String stepName,
) {
  final errors = <String>[];
  if (run.contains(r'$(') ||
      run.contains('`') ||
      run.contains(r'$"') ||
      RegExp(r'--dra""ft').hasMatch(run)) {
    errors.add(
      '$label: publish job step `$stepName` run args must not use '
      'command substitution or alternate quoting',
    );
  }
  final literals = publishRunStepLiteralArgs[script] ?? const <String>[];
  final allowedVars = _expectedEnvVarsForArgs(script);
  for (final line in run.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    if (trimmed.startsWith('bash ')) {
      continue;
    }
    final m = RegExp(r'^"([^"]+)"\s*(\\)?\s*$').firstMatch(trimmed);
    if (m == null) {
      errors.add(
        '$label: publish job step `$stepName` run arg must be '
        '"\$ENV_VAR" or a fixed literal path',
      );
      continue;
    }
    final arg = m.group(1)!;
    if (literals.contains(arg)) {
      continue;
    }
    if (arg.startsWith(r'$') && arg.length > 1) {
      final varName = arg.substring(1);
      if (!allowedVars.contains(varName)) {
        errors.add(
          '$label: publish job step `$stepName` run arg references '
          'unexpected env $varName',
        );
      }
      continue;
    }
    errors.add(
      '$label: publish job step `$stepName` disallowed run arg "$arg"',
    );
  }
  return errors;
}

List<String> _expectedEnvVarsForArgs(String script) {
  final pins = publishRunStepEnvPins[script];
  if (pins == null) {
    return const [];
  }
  return pins.keys.toList();
}

bool runDeclaresInlineUndraftEscape(String run) {
  final lower = run.toLowerCase();
  if (lower.contains('actions/github-script') ||
      lower.contains('repos.updaterelease') ||
      lower.contains('github-script')) {
    return true;
  }
  if (lower.contains('gh api') && lower.contains('draft')) {
    return true;
  }
  if (RegExp(r'gh\s+release\s+edit', caseSensitive: false).hasMatch(run) &&
      RegExp(r'--draft\s*=\s*false', caseSensitive: false).hasMatch(run)) {
    return true;
  }
  if (RegExp(r'--draft\s*=\s*"\$').hasMatch(run)) {
    return true;
  }
  return false;
}

String? parseSingleReleaseScriptRun(String run) {
  if (run.contains(r'$(') || run.contains('`')) {
    return null;
  }
  final lines = run
      .split('\n')
      .map((l) => l.trimRight())
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    return null;
  }
  final headRe = RegExp(
    r'^bash\s+"\$\{\{\s*env\.TOOLING_CHECKOUT_PATH\s*\}\}/tool/release/'
    r'([a-z0-9_]+\.sh)"\s*(\\)?\s*$',
  );
  final headMatch = headRe.firstMatch(lines.first.trim());
  if (headMatch == null) {
    return null;
  }
  final script = headMatch.group(1)!;
  final allowedLiterals = publishRunStepLiteralArgs[script] ?? const <String>[];
  final allowedVars = _expectedEnvVarsForArgs(script);
  final argRe = RegExp(r'^"([^"]+)"\s*(\\)?\s*$');
  for (var i = 1; i < lines.length; i++) {
    final trimmed = lines[i].trim();
    final m = argRe.firstMatch(trimmed);
    if (m == null) {
      return null;
    }
    final arg = m.group(1)!;
    if (allowedLiterals.contains(arg)) {
      continue;
    }
    if (arg.startsWith(r'$') && allowedVars.contains(arg.substring(1))) {
      continue;
    }
    return null;
  }
  return script;
}