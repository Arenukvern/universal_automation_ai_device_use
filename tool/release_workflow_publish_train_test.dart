import 'dart:io';

import 'package:test/test.dart';

import 'release_workflow_contract_lib.dart';

void main() {
  test('publish.yml chains dart_changesets publish with toolkit binaries', () {
    final path =
        '${Directory.current.path}/.github/workflows/publish.yml';
    final text = File(path).readAsStringSync();
    final errors = validateChangesetsPublishBinariesCaller(text);
    expect(errors, isEmpty, reason: errors.join('; '));
  });
}