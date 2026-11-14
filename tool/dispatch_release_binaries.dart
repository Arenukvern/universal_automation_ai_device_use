// Dispatches release_binaries.yml when universal_automation_toolkit is released.
//
// Env: RELEASE_PLEASE_OUTPUTS (JSON), GH_TOKEN, GH_REPO

import 'dart:convert';
import 'dart:io';

const toolkitPath = 'pkgs/universal_automation_toolkit';

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
  final created = outputs['$toolkitPath--release_created'];
  if (created != true && created != 'true') {
    stdout.writeln('Toolkit not released this train; skipping binary dispatch');
    exit(0);
  }
  final tag = outputs['$toolkitPath--tag_name'] as String?;
  if (tag == null || tag.isEmpty) {
    stderr.writeln('::error::Missing tag_name for $toolkitPath');
    exit(1);
  }

  stdout.writeln('Dispatching release_binaries.yml for $tag');
  final result = await Process.run(
    'gh',
    [
      'workflow',
      'run',
      'release_binaries.yml',
      '--repo',
      repo,
      '--ref',
      'main',
      '-f',
      'release_tag=$tag',
    ],
    environment: {...Platform.environment, 'GH_TOKEN': token},
  );
  if (result.exitCode != 0) {
    stderr.writeln('::error::gh workflow run failed for $tag');
    stderr.write(result.stdout);
    stderr.write(result.stderr);
    exit(1);
  }
  stdout.writeln('Dispatched release_binaries.yml for $tag.');
}