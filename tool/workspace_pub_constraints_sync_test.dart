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

  group('caretConstraintAdmits', () {
    test('pre-1.0 caret range', () {
      expect(caretConstraintAdmits('0.6.1', '0.6.2'), isTrue);
      expect(caretConstraintAdmits('0.6.1', '0.6.9'), isTrue);
      expect(caretConstraintAdmits('0.6.1', '0.7.0'), isFalse);
      expect(caretConstraintAdmits('0.6.2', '0.6.1'), isFalse);
    });

    test('post-1.0 caret range', () {
      expect(caretConstraintAdmits('1.0.0', '1.1.0'), isTrue);
      expect(caretConstraintAdmits('1.0.0', '1.9.9'), isTrue);
      expect(caretConstraintAdmits('1.0.0', '2.0.0'), isFalse);
    });
  });

  group('syncDependencyLine', () {
    test('patch bump: no change when range still admits sibling', () {
      const versions = {'universal_automation_toolkit': '0.6.2'};
      expect(
        syncDependencyLine(
          '  universal_automation_toolkit: ^0.6.1',
          versions,
        ),
        '  universal_automation_toolkit: ^0.6.1',
      );
    });

    test('pre-1.0 minor bump: raise when sibling leaves range', () {
      const versions = {'universal_automation_toolkit': '0.7.0'};
      expect(
        syncDependencyLine(
          '  universal_automation_toolkit: ^0.6.2',
          versions,
        ),
        '  universal_automation_toolkit: ^0.7.0',
      );
    });

    test('post-1.0 minor bump: no change', () {
      const versions = {'universal_example': '1.1.0'};
      expect(
        syncDependencyLine(
          '  universal_example: ^1.0.0',
          versions,
        ),
        '  universal_example: ^1.0.0',
      );
    });

    test('major bump: raise', () {
      const versions = {'universal_automation_interface': '1.0.0'};
      expect(
        syncDependencyLine(
          '  universal_automation_interface: ^0.5.0',
          versions,
        ),
        '  universal_automation_interface: ^1.0.0',
      );
    });

    test('hand-raised floor preserved on write', () {
      const versions = {'universal_automation_toolkit': '0.6.2'};
      expect(
        syncDependencyLine(
          '  universal_automation_toolkit: ^0.6.9  # ahead of train',
          versions,
        ),
        '  universal_automation_toolkit: ^0.6.9  # ahead of train',
      );
    });

    test('preserves trailing comment when raising', () {
      const versions = {'universal_automation_toolkit': '0.7.0'};
      expect(
        syncDependencyLine(
          '  universal_automation_toolkit: ^0.6.2  # train pin',
          versions,
        ),
        '  universal_automation_toolkit: ^0.7.0  # train pin',
      );
    });

    test('leaves unknown packages unchanged', () {
      expect(
        syncDependencyLine('  meta: ^1.19.0', const {}),
        '  meta: ^1.19.0',
      );
    });
  });

  group('hand-raised floor drift', () {
    test('flags floor above workspace sibling version', () {
      expect(
        workspaceSiblingFloorAboveDriftMessage(
          depName: 'universal_automation_toolkit',
          constraintPart: '^0.6.9',
          siblingVersion: '0.6.2',
        ),
        'floor ^0.6.9 is above workspace universal_automation_toolkit 0.6.2',
      );
    });

    test('collectHandRaisedFloorDrifts finds dependency lines', () {
      const pubspec = '''
name: consumer
version: 1.0.0
dependencies:
  universal_automation_toolkit: ^0.6.9
''';
      expect(
        collectHandRaisedFloorDrifts(pubspec, const {
          'universal_automation_toolkit': '0.6.2',
        }),
        [
          'floor ^0.6.9 is above workspace universal_automation_toolkit 0.6.2',
        ],
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
