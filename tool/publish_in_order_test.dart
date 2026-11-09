import 'package:test/test.dart';

import 'hosted_deps_resolve_lib.dart';

class _MutablePubDevGateway implements PubDevGateway {
  _MutablePubDevGateway({
    required Map<String, List<String>> versions,
    Map<String, Map<String, String>>? latestDeps,
  })  : _versions = versions,
        _latestDeps = latestDeps ?? {};

  final Map<String, List<String>> _versions;
  final Map<String, Map<String, String>> _latestDeps;

  @override
  Future<List<String>> versionsOnPubDev(String packageName) async {
    return List<String>.from(_versions[packageName] ?? []);
  }

  @override
  Future<Map<String, String>> latestPublishedWorkspaceDeps(
    String packageName,
  ) async {
    return Map<String, String>.from(_latestDeps[packageName] ?? {});
  }

  @override
  void close() {}
}

void main() {
  group('publish train pub.dev-only gate', () {
    test(
      'refuses semantics when interface 0.4.0 was never published to pub.dev',
      () {
        final semantics = WorkspacePackage(
          name: 'universal_automation_semantics',
          version: '0.5.0',
          pubspecPath: 'x',
          workspaceDeps: {'universal_automation_interface': '^0.4.0'},
        );
        final errors = siblingDepErrorsPubDevOnly(
          pkg: semantics,
          workspaceNames: {
            'universal_automation_semantics',
            'universal_automation_interface',
          },
          pubDevVersions: {
            'universal_automation_interface': ['0.3.0'],
          },
        );
        expect(errors, isNotEmpty);
        expect(errors.single, contains('^0.4.0'));
      },
    );
  });

  group('release-path audit regression', () {
    test('audit fails for pub.dev semantics 0.5.0 with interface ^0.4.0', () async {
      final gateway = _MutablePubDevGateway(
        versions: {
          'universal_automation_interface': ['0.3.0'],
          'universal_automation_semantics': ['0.5.0'],
        },
        latestDeps: {
          'universal_automation_semantics': {
            'universal_automation_interface': '^0.4.0',
          },
        },
      );
      final code = await runAuditPublished(
        packages: [
          WorkspacePackage(
            name: 'universal_automation_interface',
            version: '0.4.0',
            pubspecPath: 'x',
            workspaceDeps: {},
          ),
          WorkspacePackage(
            name: 'universal_automation_semantics',
            version: '0.5.0',
            pubspecPath: 'x',
            workspaceDeps: {'universal_automation_interface': '^0.4.0'},
          ),
        ],
        workspaceNames: {
          'universal_automation_interface',
          'universal_automation_semantics',
        },
        catalog: gateway,
      );
      expect(code, 1);
    });
  });
}
