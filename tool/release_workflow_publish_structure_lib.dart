import 'dart:io';

/// Structural publish-job contract (allowlisted steps; no inline undraft escapes).

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

const scriptsForbiddenToUndraft = <String>[
  'upload_draft_github_release_assets.sh',
  'append_draft_release_binary_notes.sh',
  'append_binary_install_notes_to_draft_release.sh',
  'assert_github_release_is_draft.sh',
  'check_release_assets_conflict.sh',
  'validate_release_checksums_file.sh',
  'generate_release_checksums_in_dist.sh',
  'assert_release_assets_complete_on_draft.sh',
];

List<String> validatePublishJobStructure(
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

  final runScripts = <String>[];
  for (var i = 0; i < steps.length; i++) {
    final step = steps[i];
    if (step is! Map) {
      continue;
    }
    final uses = step['uses']?.toString() ?? '';
    final run = step['run']?.toString() ?? '';
    final name = step['name']?.toString() ?? 'step $i';

    if (uses.isNotEmpty) {
      if (!publishJobAllowedUses.contains(uses)) {
        errors.add(
          '$label: publish job step `$name` uses disallowed action: $uses',
        );
      }
      if (run.isNotEmpty) {
        errors.add(
          '$label: publish job step `$name` must not mix uses and run',
        );
      }
      continue;
    }

    if (run.isEmpty) {
      errors.add('$label: publish job step `$name` has no run block');
      continue;
    }

    final parsed = parseSingleReleaseScriptRun(run);
    if (parsed == null) {
      errors.add(
        '$label: publish job step `$name` must be exactly one '
        'bash tool/release/<script>.sh invocation',
      );
      continue;
    }
    if (runDeclaresInlineUndraftEscape(run)) {
      errors.add(
        '$label: publish job step `$name` must not undraft inline '
        '(only $undraftAllowedScript may publish the draft release)',
      );
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

  if (runScripts.last != undraftAllowedScript) {
    errors.add(
      '$label: publish job last step must invoke $undraftAllowedScript only',
    );
  }

  return errors;
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
  final contRe = RegExp(r'^"[^"]+"\s*(\\)?\s*$');
  final headMatch = headRe.firstMatch(lines.first.trim());
  if (headMatch == null) {
    return null;
  }
  for (var i = 1; i < lines.length; i++) {
    if (!contRe.hasMatch(lines[i].trim())) {
      return null;
    }
  }
  return headMatch.group(1);
}

bool releaseScriptDeclaresUndraft(String body) {
  if (RegExp(
    r'gh\s+release\s+edit\b',
    caseSensitive: false,
  ).hasMatch(body)) {
    if (RegExp(r'--draft\s*=\s*false', caseSensitive: false).hasMatch(body)) {
      return true;
    }
  }
  if (body.contains('repos.updateRelease') && body.contains('draft')) {
    return true;
  }
  if (RegExp(r'gh\s+api\b', caseSensitive: false).hasMatch(body) &&
      body.contains('draft')) {
    return true;
  }
  return false;
}

List<String> validateReleaseToolingScriptsUndraftPolicy(String repoRoot) {
  final errors = <String>[];
  final allScripts = <String>[
    ...scriptsForbiddenToUndraft,
    undraftAllowedScript,
  ];
  for (final name in allScripts) {
    final path = '$repoRoot/tool/release/$name';
    final file = File(path);
    if (!file.existsSync()) {
      errors.add('missing release script: $name');
      continue;
    }
    final body = file.readAsStringSync();
    errors.addAll(validateReleaseToolingScriptTextUndraftPolicy(name, body));
  }
  return errors;
}

List<String> validateReleaseToolingScriptTextUndraftPolicy(
  String scriptName,
  String body,
) {
  final errors = <String>[];
  final undraft = releaseScriptDeclaresUndraft(body);
  if (scriptName == undraftAllowedScript) {
    if (!undraft) {
      errors.add('$scriptName must undraft the GitHub release');
    }
    return errors;
  }
  if (undraft) {
    errors.add(
      'only $undraftAllowedScript may undraft (forbidden in $scriptName)',
    );
  }
  return errors;
}