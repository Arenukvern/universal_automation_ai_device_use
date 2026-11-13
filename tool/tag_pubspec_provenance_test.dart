import 'dart:io';

import 'package:test/test.dart';

import 'hosted_deps_resolve_lib.dart';
import 'tag_pubspec_provenance_lib.dart';

void main() {
  group('evaluateTagSourcePubDevProvenance', () {
    test('allowlists harness 0.3.0 toolkit constraint history', () async {
      final pkg = WorkspacePackage(
        name: 'universal_automation_harness',
        version: '0.3.0',
        pubspecPath: '/tmp/pkgs/universal_automation_harness/pubspec.yaml',
        workspaceDeps: const {},
      );
      final result = await evaluateTagSourcePubDevProvenance(
        packages: [pkg],
        pubDevVersions: {
          'universal_automation_harness': ['0.3.0'],
        },
        publishedDepsAtExactVersion: {
          'universal_automation_harness@0.3.0': {
            'universal_automation_toolkit': '^0.5.1',
          },
        },
        repoRoot: Directory('/tmp'),
        tagPubspecReader: (tag, path) async => '''
name: universal_automation_harness
version: 0.3.0
dependencies:
  universal_automation_toolkit: ^0.5.0
''',
      );
      expect(result.errors, isEmpty);
      expect(
        result.warnings.single,
        contains('KNOWN HISTORY'),
      );
      expect(result.warnings.single, contains('^0.5.0'));
      expect(result.warnings.single, contains('^0.5.1'));
    });

    test('unknown drift is blocking', () async {
      final pkg = WorkspacePackage(
        name: 'universal_foo',
        version: '1.0.0',
        pubspecPath: '/tmp/pkgs/universal_foo/pubspec.yaml',
        workspaceDeps: const {},
      );
      final result = await evaluateTagSourcePubDevProvenance(
        packages: [pkg],
        pubDevVersions: {'universal_foo': ['1.0.0']},
        publishedDepsAtExactVersion: {
          'universal_foo@1.0.0': {'universal_bar': '^2.0.0'},
        },
        repoRoot: Directory('/tmp'),
        tagPubspecReader: (_, __) async => '''
dependencies:
  universal_bar: ^1.0.0
''',
      );
      expect(result.errors, hasLength(1));
      expect(result.warnings, isEmpty);
    });
  });
}
