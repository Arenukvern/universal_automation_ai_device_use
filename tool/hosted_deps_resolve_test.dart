import 'dart:io';

import 'package:test/test.dart';

import 'hosted_deps_resolve_lib.dart';

class _FakePubDevGateway implements PubDevGateway {
  _FakePubDevGateway({
    this.versions = const {},
    this.latestDeps = const {},
    this.failOnVersionsFor,
    this.failOnLatestFor,
  });

  final Map<String, List<String>> versions;
  final Map<String, Map<String, String>> latestDeps;
  final String? failOnVersionsFor;
  final String? failOnLatestFor;

  @override
  Future<List<String>> versionsOnPubDev(String packageName) async {
    if (failOnVersionsFor == packageName) {
      throw const SocketException('simulated unreachable pub.dev');
    }
    return versions[packageName] ?? [];
  }

  @override
  Future<Map<String, String>> latestPublishedWorkspaceDeps(
    String packageName,
  ) async {
    if (failOnLatestFor == packageName) {
      throw HttpException('simulated 503', uri: Uri.parse('https://pub.dev'));
    }
    return latestDeps[packageName] ?? {};
  }

  @override
  void close() {}
}

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

  group('resolveErrorsAlongPublishOrder', () {
    const workspaceNames = {
      'universal_automation_interface',
      'universal_automation_semantics',
    };

    final packages = [
      WorkspacePackage(
        name: 'universal_automation_interface',
        version: '0.4.0',
        pubspecPath: 'x',
        workspaceDeps: {},
      ),
      WorkspacePackage(
        name: 'universal_automation_semantics',
        version: '0.4.0',
        pubspecPath: 'x',
        workspaceDeps: {'universal_automation_interface': '^0.4.0'},
      ),
    ];

    final pubDev = <String, List<String>>{
      'universal_automation_interface': ['0.3.0'],
      'universal_automation_semantics': [],
    };

    const manifest = {
      'universal_automation_interface': '0.4.0',
      'universal_automation_semantics': '0.4.0',
    };

    test('accepts dependency before dependent in publish order', () {
      final errors = resolveErrorsAlongPublishOrder(
        packages: packages,
        workspaceNames: workspaceNames,
        pubDevVersions: pubDev,
        releaseManifestByName: manifest,
        publishOrder: const [
          'universal_automation_interface',
          'universal_automation_semantics',
        ],
      );
      expect(errors, isEmpty);
    });

    test('rejects dependent before dependency in publish order', () {
      final errors = resolveErrorsAlongPublishOrder(
        packages: packages,
        workspaceNames: workspaceNames,
        pubDevVersions: pubDev,
        releaseManifestByName: manifest,
        publishOrder: const [
          'universal_automation_semantics',
          'universal_automation_interface',
        ],
      );
      expect(errors, isNotEmpty);
      expect(errors.join('\n'), contains('universal_automation_interface'));
    });
  });

  group('runAuditPublished', () {
    test('fails closed when pub.dev is unreachable', () async {
      final packages = [
        WorkspacePackage(
          name: 'universal_automation_interface',
          version: '0.1.0',
          pubspecPath: 'x',
          workspaceDeps: {},
        ),
      ];
      final code = await runAuditPublished(
        packages: packages,
        workspaceNames: {'universal_automation_interface'},
        catalog: _FakePubDevGateway(
          failOnVersionsFor: 'universal_automation_interface',
        ),
      );
      expect(code, 1);
    });

    test('fails closed on HTTP error reading latest pubspec', () async {
      final packages = [
        WorkspacePackage(
          name: 'universal_automation_interface',
          version: '0.1.0',
          pubspecPath: 'x',
          workspaceDeps: {},
        ),
      ];
      final code = await runAuditPublished(
        packages: packages,
        workspaceNames: {'universal_automation_interface'},
        catalog: _FakePubDevGateway(
          versions: {'universal_automation_interface': ['0.3.0']},
          failOnLatestFor: 'universal_automation_interface',
        ),
      );
      expect(code, 1);
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
