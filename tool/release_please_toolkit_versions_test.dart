import 'dart:io';

import 'package:test/test.dart';

import 'release_please_toolkit_versions_lib.dart';
import 'workspace_pub_constraints_sync.dart';

void main() {
  late Directory repoRoot;

  setUp(() {
    repoRoot = findWorkspaceRepoRoot();
  });

  test('toolkit version surfaces are listed in release-please extra-files', () {
    final errors = validateToolkitVersionSurfacesReleasePlease(repoRoot.path);
    expect(errors, isEmpty, reason: errors.join('\n'));
  });
}