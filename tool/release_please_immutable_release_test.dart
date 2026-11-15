import 'dart:io';

import 'package:test/test.dart';

import 'release_please_immutable_release_lib.dart';
import 'workspace_pub_constraints_sync.dart';

void main() {
  late Directory repoRoot;

  setUp(() {
    repoRoot = findWorkspaceRepoRoot();
  });

  test('live release-please config satisfies draft + force-tag-creation', () {
    final errors =
        validateToolkitImmutableReleaseReleasePleaseConfig(repoRoot.path);
    expect(errors, isEmpty, reason: errors.join('\n'));
  });

  test('mutation: toolkit missing draft fails', () {
    final live =
        File('${repoRoot.path}/release-please-config.json').readAsStringSync();
    final broken = live.replaceFirst('"draft": true,', '');
    final errors = validateToolkitImmutableReleaseReleasePleaseConfig(
      repoRoot.path,
      configText: broken,
    );
    expect(errors, isNotEmpty);
    expect(errors.join('\n'), contains('draft'));
  });

  test('mutation: top-level draft fails', () {
    final live =
        File('${repoRoot.path}/release-please-config.json').readAsStringSync();
    final broken = live.replaceFirst(
      '"packages": {',
      '"draft": true,\n  "packages": {',
    );
    final errors = validateToolkitImmutableReleaseReleasePleaseConfig(
      repoRoot.path,
      configText: broken,
    );
    expect(errors, isNotEmpty);
    expect(errors.join('\n'), contains('top-level'));
  });

  test('mutation: toolkit missing force-tag-creation fails', () {
    final live =
        File('${repoRoot.path}/release-please-config.json').readAsStringSync();
    final broken = live.replaceFirst('"force-tag-creation": true,', '');
    final errors = validateToolkitImmutableReleaseReleasePleaseConfig(
      repoRoot.path,
      configText: broken,
    );
    expect(errors, isNotEmpty);
    expect(errors.join('\n'), contains('force-tag-creation'));
  });
}