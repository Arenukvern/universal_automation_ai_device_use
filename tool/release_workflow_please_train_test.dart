import 'dart:io';

import 'package:test/test.dart';

import 'release_workflow_contract_lib.dart';

void main() {
  test('release-please.yml pub train is independent of binary jobs', () {
    final path =
        '${Directory.current.path}/.github/workflows/release-please.yml';
    final text = File(path).readAsStringSync();
    final errors = validateReleasePleaseBinariesCaller(text);
    expect(errors, isEmpty, reason: errors.join('; '));
  });
}