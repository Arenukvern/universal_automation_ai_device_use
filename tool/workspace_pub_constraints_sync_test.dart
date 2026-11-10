import 'dart:io';

import 'package:test/test.dart';

import 'workspace_pub_constraints_sync.dart';

void main() {
  group('parsePubspecHeader', () {
    test('reads name and version at column 0 only', () {
      const content = '''
name: real_pkg
version: 1.0.0
description: nested name: fake
  version: 9.9.9
''';
      final h = parsePubspecHeader(content);
      expect(h.name, 'real_pkg');
      expect(h.version, '1.0.0');
    });
  });

  group('syncDependencyLine', () {
    const versions = {'universal_automation_interface': '0.4.0'};

    test('updates constraint', () {
      expect(
        syncDependencyLine(
          '  universal_automation_interface: ^0.3.0',
          versions,
        ),
        '  universal_automation_interface: ^0.4.0',
      );
    });

    test('preserves trailing comment', () {
      expect(
        syncDependencyLine(
          '  universal_automation_interface: ^0.3.0  # train pin',
          versions,
        ),
        '  universal_automation_interface: ^0.4.0  # train pin',
      );
    });

    test('leaves unknown packages unchanged', () {
      expect(
        syncDependencyLine('  meta: ^1.19.0', versions),
        '  meta: ^1.19.0',
      );
    });
  });

  group('sync entrypoint SDK-only invariant', () {
    // The release-please sync job invokes the tool with plain `dart` (no
    // `dart run`) so its success never depends on package resolution: it
    // repairs a tree whose sibling constraints do not resolve yet, and
    // `dart run`'s tolerance of failed implicit pub gets is an SDK-version
    // detail, not a contract. A `package:` import anywhere in the entry
    // chain would quietly reintroduce that dependency.
    test('entry chain has no package: imports', () {
      final root = findWorkspaceRepoRoot();
      const chain = [
        'sync_workspace_pub_constraints.dart',
        'tool_cli.dart',
        'workspace_pub_constraints_sync.dart',
      ];
      for (final name in chain) {
        final source = File('${root.path}/tool/$name').readAsStringSync();
        expect(
          RegExp(r"^\s*import\s+'package:").hasMatch(source),
          isFalse,
          reason:
              'tool/$name must stay SDK-only: the release-please sync job '
              'runs it with plain `dart` before pub resolution exists',
        );
      }
    });
  });
}
