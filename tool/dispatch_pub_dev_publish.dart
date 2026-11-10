// Dispatches publish_package.yml for each path in release-please paths_released.
//
// Env: RELEASE_PLEASE_OUTPUTS (JSON map of release-please step outputs)
//      GH_TOKEN, GH_REPO

import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final raw = Platform.environment['RELEASE_PLEASE_OUTPUTS'];
  final repo = Platform.environment['GH_REPO'];
  final token = Platform.environment['GH_TOKEN'];
  if (raw == null || raw.isEmpty) {
    stderr.writeln('RELEASE_PLEASE_OUTPUTS is empty');
    exit(2);
  }
  if (repo == null || token == null) {
    stderr.writeln('GH_REPO and GH_TOKEN required');
    exit(2);
  }

  final outputs = jsonDecode(raw) as Map<String, dynamic>;
  final pathsRaw = outputs['paths_released'];
  if (pathsRaw == null ||
      pathsRaw == '' ||
      pathsRaw == '[]' ||
      pathsRaw == false) {
    stdout.writeln('No paths_released; skipping publish dispatch');
    exit(0);
  }

  final paths = jsonDecode(pathsRaw as String) as List<dynamic>;
  if (paths.isEmpty) {
    stdout.writeln('No paths_released; skipping publish dispatch');
    exit(0);
  }

  var dispatched = 0;
  for (final path in paths) {
    final p = path as String;
    final created = outputs['$p--release_created'];
    if (created != true && created != 'true') {
      stdout.writeln('Skip $p (release_created=$created)');
      continue;
    }
    final tag = outputs['$p--tag_name'] as String?;
    if (tag == null || tag.isEmpty) {
      stderr.writeln('::error::Missing tag_name output for $p');
      exit(1);
    }
    stdout.writeln('Dispatching publish_package.yml for $tag ($p)');
    final result = await Process.run(
      'gh',
      [
        'workflow',
        'run',
        'publish_package.yml',
        '--repo',
        repo,
        '--ref',
        tag,
      ],
      environment: {...Platform.environment, 'GH_TOKEN': token},
    );
    if (result.exitCode != 0) {
      stderr.writeln('::error::gh workflow run failed for $tag');
      stderr.write(result.stdout);
      stderr.write(result.stderr);
      exit(1);
    }
    dispatched++;
  }
  stdout.writeln('Dispatched $dispatched publish workflow(s).');
}
