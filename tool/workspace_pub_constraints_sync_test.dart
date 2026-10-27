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
}
