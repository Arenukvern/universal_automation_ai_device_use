import 'package:test/test.dart';

import 'hosted_deps_resolve_lib.dart';
import 'workspace_pub_constraints_sync.dart';

void main() {
  group('constraintSatisfiedByAnyVersion', () {
    test('caret 0.4.0 allows 0.4.x not 0.3.0 or 0.5.0', () {
      expect(constraintSatisfiedByAnyVersion('^0.4.0', ['0.3.0']), isFalse);
      expect(constraintSatisfiedByAnyVersion('^0.4.0', ['0.4.1']), isTrue);
      expect(constraintSatisfiedByAnyVersion('^0.4.0', ['0.5.0']), isFalse);
    });

    test('manifest version can satisfy unreleased constraint', () {
      expect(
        constraintSatisfiedByAnyVersion('^0.4.0', ['0.3.0', '0.4.0']),
        isTrue,
      );
    });
  });

  group('topologicalPublishOrder', () {
    test('interface before semantics before toolkit', () {
      final packages = [
        WorkspacePackage(
          name: 'universal_automation_interface',
          version: '0.1.0',
          pubspecPath: 'x',
          workspaceDeps: {},
        ),
        WorkspacePackage(
          name: 'universal_automation_semantics',
          version: '0.1.0',
          pubspecPath: 'x',
          workspaceDeps: {'universal_automation_interface': '^0.1.0'},
        ),
        WorkspacePackage(
          name: 'universal_automation_toolkit',
          version: '0.1.0',
          pubspecPath: 'x',
          workspaceDeps: {
            'universal_automation_interface': '^0.1.0',
            'universal_automation_semantics': '^0.1.0',
          },
        ),
      ];
      final order = topologicalPublishOrder(
        workspaceDependencyGraph(packages),
      );
      expect(
        order.indexOf('universal_automation_interface'),
        lessThan(order.indexOf('universal_automation_semantics')),
      );
      expect(
        order.indexOf('universal_automation_semantics'),
        lessThan(order.indexOf('universal_automation_toolkit')),
      );
    });
  });

  group('resolveErrors with release manifest', () {
    test('interface 0.4.0 in manifest satisfies semantics ^0.4.0 on pub.dev 0.3.0', () {
      final packages = [
        WorkspacePackage(
          name: 'universal_automation_semantics',
          version: '0.5.0',
          pubspecPath: 'x',
          workspaceDeps: {'universal_automation_interface': '^0.4.0'},
        ),
      ];
      final errors = resolveErrors(
        packages: packages,
        workspaceNames: {'universal_automation_semantics', 'universal_automation_interface'},
        pubDevVersions: {
          'universal_automation_interface': ['0.3.0'],
        },
        releaseManifestByName: {
          'universal_automation_interface': '0.4.0',
        },
      );
      expect(errors, isEmpty);
    });
  });

  group('parseWorkspaceDependencies', () {
    test('reads dependencies section only', () {
      const yaml = '''
name: pkg
version: 1.0.0
dependencies:
  universal_automation_interface: ^0.4.0
  meta: ^1.0.0
dev_dependencies:
  universal_automation_conformance: ^0.1.0
''';
      final deps = parseWorkspaceDependencies(yaml);
      expect(deps, {'universal_automation_interface': '^0.4.0'});
    });
  });
}
