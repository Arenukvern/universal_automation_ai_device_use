import 'dart:io';

import 'package:test/test.dart';

import 'release_workflow_publish_structure_lib.dart';
import 'workspace_pub_constraints_sync.dart';

void main() {
  late Directory repoRoot;

  setUp(() {
    repoRoot = findWorkspaceRepoRoot();
  });

  test('live release tooling scripts: only publish-from-draft undrafts', () {
    final errors = validateReleaseToolingScriptsUndraftPolicy(repoRoot.path);
    expect(errors, isEmpty, reason: errors.join('\n'));
  });

  test('mutation: upload script undraft fixture is rejected', () {
    final path =
        '${repoRoot.path}/tool/contracts/fixtures/release_scripts/upload_draft_github_release_assets_undraft.sh';
    final body = File(path).readAsStringSync();
    final errors = validateReleaseToolingScriptTextUndraftPolicy(
      'upload_draft_github_release_assets.sh',
      body,
    );
    expect(errors, isNotEmpty);
    expect(errors.join('\n'), contains('only $undraftAllowedScript'));
  });
}