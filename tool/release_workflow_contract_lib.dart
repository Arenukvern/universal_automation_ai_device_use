import 'package:yaml/yaml.dart';

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

  void requireJobIf(String jobId, String substr) {
    final job = jobsMap[jobId];
    if (job is! Map) {
      return;
    }
    final raw = job['if'];
    if (raw == null) {
      errors.add('$label: job $jobId must declare `if: $substr`');
      return;
    }
    final cond = raw.toString();
    if (!cond.contains('dry_run') || !cond.contains('!= true')) {
      errors.add('$label: job $jobId if must gate on inputs.dry_run != true');
    }
  }

  requireJobIf('publish', 'inputs.dry_run != true');
  requireJobIf('postflight', 'inputs.dry_run != true');

  final postflight = jobsMap['postflight'];
  if (postflight is Map) {
    final needs = postflight['needs'];
    final needsList = needs is List ? needs.map((e) => e.toString()).toList() : <String>[];
    if (!needsList.contains('prepare') || !needsList.contains('publish')) {
      errors.add('$label: postflight must need prepare and publish');
    }
    if (!_stepRunsScript(postflight, 'assert_release_assets_complete.sh')) {
      errors.add(
        '$label: postflight must run assert_release_assets_complete.sh in a step `run`',
      );
    }
  }

  final build = jobsMap['build'];
  if (build is Map) {
    final needs = build['needs'];
    if (needs?.toString() != 'prepare') {
      errors.add('$label: build must need prepare');
    }
  }

  if (jobsMap.containsKey('dry-run-bundle')) {
    final dr = jobsMap['dry-run-bundle'];
    if (dr is Map) {
      final rawIf = dr['if']?.toString() ?? '';
      if (!rawIf.contains('dry_run == true')) {
        errors.add('$label: dry-run-bundle must run when dry_run == true');
      }
    }
  } else {
    errors.add('$label: missing dry-run-bundle job for artifact-only dry runs');
  }

  final runName = root['run-name']?.toString() ?? '';
  if (!runName.contains('release-binaries')) {
    errors.add('$label: run-name must include release-binaries prefix');
  }
  if (!runName.contains('inputs.release_tag')) {
    errors.add('$label: run-name must reference inputs.release_tag');
  }

  if (!_allCheckoutsPersistFalse(jobsMap)) {
    errors.add('$label: every actions/checkout must set persist-credentials: false');
  }

  if (!_publishUsesAppendBody(jobsMap['publish'])) {
    errors.add('$label: publish job must set append_body: true on action-gh-release');
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

bool _stepRunsScript(Map<dynamic, dynamic> job, String scriptName) {
  final steps = job['steps'];
  if (steps is! List) {
    return false;
  }
  for (final step in steps) {
    if (step is! Map) {
      continue;
    }
    final run = step['run'];
    if (run is! String) {
      continue;
    }
  for (final line in run.split('\n')) {
      final trimmed = line.trimLeft();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      if (line.contains(scriptName)) {
        return true;
      }
    }
  }
  return false;
}