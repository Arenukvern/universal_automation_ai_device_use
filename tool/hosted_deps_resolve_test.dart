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
  });

  group('computeReleaseSet', () {
    final packages = [
      WorkspacePackage(
        name: 'universal_automation_interface',
        version: '0.4.0',
        pubspecPath: 'x',
        workspaceDeps: {},
      ),
    ];

    test('empty when co-release disabled', () {
      expect(
        computeReleaseSet(
          packages: packages,
          pubDevVersions: {
            'universal_automation_interface': ['0.3.0'],
          },
          coReleaseEnabled: false,
        ),
        isEmpty,
      );
    });

    test('includes package when version bumps above pub.dev', () {
      expect(
        computeReleaseSet(
          packages: packages,
          pubDevVersions: {
            'universal_automation_interface': ['0.3.0'],
          },
          coReleaseEnabled: true,
        ),
        {'universal_automation_interface'},
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

    const publishOrder = [
      'universal_automation_interface',
      'universal_automation_semantics',
    ];

    test(
      'regression: semantics train without interface in release set fails',
      () {
        final errors = resolveErrorsAlongPublishOrder(
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
          workspaceNames: workspaceNames,
          pubDevVersions: pubDev,
          releaseSet: {'universal_automation_semantics'},
          publishOrder: publishOrder,
        );
        expect(errors, isNotEmpty);
        expect(errors.join('\n'), contains('^0.4.0'));
      },
    );

    test(
      'co-release plans interface 0.4.0 before semantics (releasable monorepo)',
      () {
        final errors = resolveErrorsAlongPublishOrder(
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
          workspaceNames: workspaceNames,
          pubDevVersions: pubDev,
          releaseSet: {'universal_automation_interface'},
          publishOrder: publishOrder,
        );
        expect(errors, isEmpty);
      },
    );

    test('co-release: accepts dependency before dependent in publish order', () {
      final errors = resolveErrorsAlongPublishOrder(
        packages: packages,
        workspaceNames: workspaceNames,
        pubDevVersions: pubDev,
        releaseSet: {'universal_automation_interface'},
        publishOrder: publishOrder,
      );
      expect(errors, isEmpty);
    });

    test('rejects dependent before dependency in publish order', () {
      final errors = resolveErrorsAlongPublishOrder(
        packages: packages,
        workspaceNames: workspaceNames,
        pubDevVersions: pubDev,
        releaseSet: {'universal_automation_interface'},
        publishOrder: const [
          'universal_automation_semantics',
          'universal_automation_interface',
        ],
      );
      expect(errors, isNotEmpty);
    });
  });

  group('evaluateVersionPolicy', () {
    final repoRoot = Directory.systemTemp;

    Future<VersionPolicyResult> policyFor({
      required List<WorkspacePackage> packages,
      required Map<String, String> manifestByName,
      required Map<String, List<String>> pubDevVersions,
      Set<String> releaseSet = const {},
      bool warnManifestBehindPub = false,
      Future<bool?> Function(Directory, WorkspacePackage)? gitCheck,
    }) {
      return evaluateVersionPolicy(
        repoRoot: repoRoot,
        packages: packages,
        manifestByName: manifestByName,
        pubDevVersions: pubDevVersions,
        releaseSet: releaseSet,
        warnManifestBehindPub: warnManifestBehindPub,
        gitChangesSinceTag:
            gitCheck ?? (_, __) async => false,
      );
    }

    test('PR #24 shape: manifest == pub.dev latest, pubspec ahead — pass', () async {
      final result = await policyFor(
        packages: [
          WorkspacePackage(
            name: 'universal_automation_semantics',
            version: '0.6.0',
            pubspecPath: 'x',
            workspaceDeps: {},
          ),
        ],
        manifestByName: {'universal_automation_semantics': '0.5.0'},
        pubDevVersions: {
          'universal_automation_semantics': ['0.4.0', '0.5.0'],
        },
        releaseSet: {'universal_automation_semantics'},
      );
      expect(result.errors, isEmpty);
    });

    test('release path: manifest behind pub.dev latest is blocking', () async {
      final result = await policyFor(
        packages: [
          WorkspacePackage(
            name: 'universal_automation_semantics',
            version: '0.5.0',
            pubspecPath: 'x',
            workspaceDeps: {},
          ),
        ],
        manifestByName: {'universal_automation_semantics': '0.3.0'},
        pubDevVersions: {
          'universal_automation_semantics': ['0.3.0', '0.5.0'],
        },
      );
      expect(result.errors.any((e) => e.contains('manifest 0.3.0')), isTrue);
    });

    test('main/PR: manifest behind pub.dev latest can warn only', () async {
      final result = await policyFor(
        packages: [
          WorkspacePackage(
            name: 'universal_automation_semantics',
            version: '0.5.0',
            pubspecPath: 'x',
            workspaceDeps: {},
          ),
        ],
        manifestByName: {'universal_automation_semantics': '0.3.0'},
        pubDevVersions: {
          'universal_automation_semantics': ['0.3.0', '0.5.0'],
        },
        warnManifestBehindPub: true,
      );
      expect(result.errors, isEmpty);
      expect(result.warnings.any((e) => e.contains('manifest 0.3.0')), isTrue);
    });

    test('manifest version not on pub.dev (never shipped)', () async {
      final result = await policyFor(
        packages: [
          WorkspacePackage(
            name: 'universal_automation_interface',
            version: '0.5.0',
            pubspecPath: 'x',
            workspaceDeps: {},
          ),
        ],
        manifestByName: {'universal_automation_interface': '0.4.0'},
        pubDevVersions: {
          'universal_automation_interface': ['0.3.0'],
        },
      );
      expect(result.errors.any((e) => e.contains('not on pub.dev')), isTrue);
    });

    test('main/PR warn mode: manifest not on pub.dev is warning', () async {
      final result = await policyFor(
        packages: [
          WorkspacePackage(
            name: 'universal_automation_interface',
            version: '0.5.0',
            pubspecPath: 'x',
            workspaceDeps: {},
          ),
        ],
        manifestByName: {'universal_automation_interface': '0.4.0'},
        pubDevVersions: {
          'universal_automation_interface': ['0.3.0'],
        },
        warnManifestBehindPub: true,
      );
      expect(result.errors, isEmpty);
      expect(result.warnings.any((e) => e.contains('not on pub.dev')), isTrue);
    });

    test('pubspec lower than pub.dev latest', () async {
      final result = await policyFor(
        packages: [
          WorkspacePackage(
            name: 'universal_automation_toolkit',
            version: '0.3.0',
            pubspecPath: 'x',
            workspaceDeps: {},
          ),
        ],
        manifestByName: {'universal_automation_toolkit': '0.4.0'},
        pubDevVersions: {
          'universal_automation_toolkit': ['0.3.0', '0.4.0'],
        },
      );
      expect(
        result.errors.any((e) => e.contains('lower than pub.dev latest')),
        isTrue,
      );
    });

    test('pubspec on pub.dev while in release set', () async {
      final result = await policyFor(
        packages: [
          WorkspacePackage(
            name: 'universal_automation_toolkit',
            version: '0.4.0',
            pubspecPath: 'x',
            workspaceDeps: {},
          ),
        ],
        manifestByName: {'universal_automation_toolkit': '0.4.0'},
        pubDevVersions: {
          'universal_automation_toolkit': ['0.4.0'],
        },
        releaseSet: {'universal_automation_toolkit'},
      );
      expect(result.errors.any((e) => e.contains('already on pub.dev')), isTrue);
    });

    test('allows manifest behind pubspec when manifest matches pub.dev', () async {
      final result = await policyFor(
        packages: [
          WorkspacePackage(
            name: 'universal_automation_toolkit',
            version: '0.5.0',
            pubspecPath: 'x',
            workspaceDeps: {},
          ),
        ],
        manifestByName: {'universal_automation_toolkit': '0.4.0'},
        pubDevVersions: {
          'universal_automation_toolkit': ['0.3.0', '0.4.0'],
        },
        releaseSet: {'universal_automation_toolkit'},
      );
      expect(result.errors, isEmpty);
    });

    test('pubspec equals pub.dev latest with changes since tag — reuse error', () async {
      final result = await policyFor(
        packages: [
          WorkspacePackage(
            name: 'universal_automation_toolkit',
            version: '0.4.0',
            pubspecPath: 'x',
            workspaceDeps: {},
          ),
        ],
        manifestByName: {'universal_automation_toolkit': '0.4.0'},
        pubDevVersions: {
          'universal_automation_toolkit': ['0.3.0', '0.4.0'],
        },
        gitCheck: (_, __) async => true,
      );
      expect(result.errors.any((e) => e.contains('version reuse')), isTrue);
    });

    test('pubspec equals pub.dev latest without tag — warning', () async {
      final result = await policyFor(
        packages: [
          WorkspacePackage(
            name: 'universal_automation_toolkit',
            version: '0.4.0',
            pubspecPath: 'x',
            workspaceDeps: {},
          ),
        ],
        manifestByName: {'universal_automation_toolkit': '0.4.0'},
        pubDevVersions: {
          'universal_automation_toolkit': ['0.3.0', '0.4.0'],
        },
        gitCheck: (_, __) async => null,
      );
      expect(result.errors, isEmpty);
      expect(result.warnings, isNotEmpty);
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
