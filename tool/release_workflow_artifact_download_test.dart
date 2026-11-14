import 'dart:io';

import 'package:test/test.dart';

import 'release_workflow_contract_lib.dart';

void main() {
  test('release_binaries_build publish uses same-run artifact download', () {
    final path =
        '${Directory.current.path}/.github/workflows/release_binaries_build.yml';
    final text = File(path).readAsStringSync();
    final errors = validateReleaseBinariesBuildWorkflowYaml(text);
    expect(errors, isEmpty, reason: errors.join('; '));
    expect(text, isNot(contains('run-id:')));
    expect(text, isNot(contains('github-token:')));
  });

  test('release_binaries_publish fixture forbids cross-run download', () {
    final path =
        '${Directory.current.path}/tool/contracts/fixtures/release_workflow_publish/negative_publish_cross_run_download.yml';
    final text = File(path).readAsStringSync();
    final errors = validateReleaseBinariesPublishWorkflowYaml(text);
    expect(
      errors.any((e) => e.contains('must not set run-id or github-token')),
      isTrue,
      reason: errors.join('; '),
    );
  });
}