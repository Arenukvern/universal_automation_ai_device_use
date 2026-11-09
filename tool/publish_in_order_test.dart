import 'package:test/test.dart';

import 'hosted_deps_resolve_lib.dart';

class _PollingPubDevGateway implements PubDevGateway {
  _PollingPubDevGateway({
    required this.packageName,
    required this.version,
    required this.appearAfterPolls,
    List<String>? initialVersions,
  }) : _versions = List<String>.from(initialVersions ?? []);

  final String packageName;
  final String version;
  final int appearAfterPolls;
  final List<String> _versions;
  var _polls = 0;

  @override
  Future<List<String>> versionsOnPubDev(String name) async {
    if (name != packageName) {
      return [];
    }
    _polls++;
    if (_polls >= appearAfterPolls) {
      if (!_versions.contains(version)) {
        _versions.add(version);
      }
    }
    return List<String>.from(_versions);
  }

  @override
  Future<Map<String, String>> latestPublishedWorkspaceDeps(String name) async => {};

  @override
  void close() {}
}

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
  group('waitForVersionOnPubDev', () {
    test('succeeds when exact version appears after growing backoff polls', () async {
      final gateway = _PollingPubDevGateway(
        packageName: 'universal_automation_interface',
        version: '0.4.0',
        appearAfterPolls: 3,
        initialVersions: ['0.3.0'],
      );
      await waitForVersionOnPubDev(
        catalog: gateway,
        packageName: 'universal_automation_interface',
        version: '0.4.0',
        timeout: const Duration(seconds: 30),
        initialPollInterval: const Duration(milliseconds: 50),
      );
      expect(gateway._polls, greaterThanOrEqualTo(3));
    });

    test('times out with package and version in error', () async {
      final gateway = _PollingPubDevGateway(
        packageName: 'universal_automation_interface',
        version: '0.4.0',
        appearAfterPolls: 1000,
        initialVersions: ['0.3.0'],
      );
      expect(
        () => waitForVersionOnPubDev(
          catalog: gateway,
          packageName: 'universal_automation_interface',
          version: '0.4.0',
          timeout: const Duration(milliseconds: 200),
          initialPollInterval: const Duration(milliseconds: 40),
        ),
        throwsA(
          predicate(
            (Object e) =>
                e is StateError &&
                e.message.contains('universal_automation_interface@0.4.0') &&
                e.message.contains('visibility timeout'),
          ),
        ),
      );
    });
  });

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
