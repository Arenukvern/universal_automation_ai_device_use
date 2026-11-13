import 'dart:io';

import 'package:test/test.dart';

import 'hosted_deps_resolve_lib.dart';

class _FakePubDevGateway implements PubDevGateway {
  _FakePubDevGateway({
    this.versions = const {},
    this.latestDeps = const {},
    this.versionDeps = const {},
    this.failOnVersionsFor,
    this.failOnLatestFor,
    this.failOnVersionDepsFor,
  });

  final Map<String, List<String>> versions;
  final Map<String, Map<String, String>> latestDeps;
  final Map<String, Map<String, String>> versionDeps;
  final String? failOnVersionsFor;
  final String? failOnLatestFor;
  final String? failOnVersionDepsFor;

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
  Future<Map<String, String>> publishedWorkspaceDepsAtVersion(
    String packageName,
    String version,
  ) async {
    final key = publishedDepsAtVersionKey(packageName, version);
    if (failOnVersionDepsFor == key) {
      throw HttpException('simulated 503', uri: Uri.parse('https://pub.dev'));
    }
    return versionDeps[key] ?? {};
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
      bool releasePrMode = false,
      Future<bool?> Function(Directory, WorkspacePackage)? gitCheck,
    }) {
      return evaluateVersionPolicy(
        repoRoot: repoRoot,
        packages: packages,
        manifestByName: manifestByName,
        pubDevVersions: pubDevVersions,
        releaseSet: releaseSet,
        warnManifestBehindPub: warnManifestBehindPub,
        releasePrMode: releasePrMode,
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

    test('release-PR mode: manifest == pubspec > pub latest, not on pub', () async {
      final result = await policyFor(
        packages: [
          WorkspacePackage(
            name: 'universal_automation_semantics',
            version: '0.6.0',
            pubspecPath: 'x',
            workspaceDeps: {},
          ),
        ],
        manifestByName: {'universal_automation_semantics': '0.6.0'},
        pubDevVersions: {
          'universal_automation_semantics': ['0.4.0', '0.5.0'],
        },
        releaseSet: {'universal_automation_semantics'},
        releasePrMode: true,
      );
      expect(result.errors, isEmpty);
    });

    test('release-PR mode: manifest != pubspec is error', () async {
      final result = await policyFor(
        packages: [
          WorkspacePackage(
            name: 'universal_automation_toolkit',
            version: '0.5.0',
            pubspecPath: 'x',
            workspaceDeps: {},
          ),
        ],
        manifestByName: {'universal_automation_toolkit': '0.6.0'},
        pubDevVersions: {
          'universal_automation_toolkit': ['0.3.0', '0.4.0'],
        },
        releaseSet: {'universal_automation_toolkit'},
        releasePrMode: true,
      );
      expect(result.errors.any((e) => e.contains('not on pub.dev')), isTrue);
    });

    test('release-PR mode: manifest <= pub latest but not on pub is error', () async {
      final result = await policyFor(
        packages: [
          WorkspacePackage(
            name: 'universal_automation_interface',
            version: '0.4.0',
            pubspecPath: 'x',
            workspaceDeps: {},
          ),
        ],
        manifestByName: {'universal_automation_interface': '0.4.0'},
        pubDevVersions: {
          'universal_automation_interface': ['0.3.0', '0.5.0'],
        },
        releaseSet: {'universal_automation_interface'},
        releasePrMode: true,
      );
      expect(result.errors.any((e) => e.contains('not on pub.dev')), isTrue);
    });

    test('strict mode: manifest not on pub.dev (never shipped)', () async {
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
      final result = await evaluateVersionPolicy(
        repoRoot: repoRoot,
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
        releaseSet: {'universal_automation_toolkit'},
        enableTagReuseCheck: true,
        gitChangesSinceTag: (_, __) async => true,
      );
      expect(result.errors.any((e) => e.contains('version reuse')), isTrue);
    });

    test('tag reuse skipped when package not in release set', () async {
      final result = await evaluateVersionPolicy(
        repoRoot: repoRoot,
        packages: [
          WorkspacePackage(
            name: 'universal_automation_conformance',
            version: '0.3.1',
            pubspecPath: 'x',
            workspaceDeps: {},
          ),
        ],
        manifestByName: {'universal_automation_conformance': '0.3.1'},
        pubDevVersions: {
          'universal_automation_conformance': ['0.3.0', '0.3.1'],
        },
        releaseSet: const {},
        enableTagReuseCheck: true,
        gitChangesSinceTag: (_, __) async => true,
      );
      expect(result.errors, isEmpty);
    });

    test('tag reuse not run for pending release-set version (ahead of pub.dev)', () async {
      final result = await evaluateVersionPolicy(
        repoRoot: repoRoot,
        packages: [
          WorkspacePackage(
            name: 'universal_automation_interface',
            version: '0.4.0',
            pubspecPath: 'x',
            workspaceDeps: {},
          ),
        ],
        manifestByName: {'universal_automation_interface': '0.3.0'},
        pubDevVersions: {
          'universal_automation_interface': ['0.3.0'],
        },
        releaseSet: {'universal_automation_interface'},
        enableTagReuseCheck: true,
        gitChangesSinceTag: (_, __) async => throw StateError('should not run'),
      );
      expect(result.errors, isEmpty);
    });
  });

  group('publishedExactVersionWorkspaceConstraintDriftErrors', () {
    test('flags drift for shipped version constraints', () {
      final packages = [
        WorkspacePackage(
          name: 'universal_automation_conformance',
          version: '0.3.1',
          pubspecPath: 'x',
          workspaceDeps: {
            'universal_automation_interface': '^0.4.0',
            'universal_screencast': '^0.3.0',
          },
        ),
      ];
      final errors = publishedExactVersionWorkspaceConstraintDriftErrors(
        packages: packages,
        pubDevVersions: {
          'universal_automation_conformance': ['0.3.1'],
        },
        releaseSet: {},
        publishedDepsAtExactVersion: {
          publishedDepsAtVersionKey(
            'universal_automation_conformance',
            '0.3.1',
          ): {
            'universal_automation_interface': '^0.3.0',
            'universal_screencast': '^0.2.0',
          },
        },
      );
      expect(errors.length, 2);
      expect(errors.first, contains('universal_automation_conformance@0.3.1'));
      expect(errors.first, contains('fix(universal_automation_conformance)'));
    });

    test('skips pending release-set package', () {
      final packages = [
        WorkspacePackage(
          name: 'universal_automation_conformance',
          version: '0.3.2',
          pubspecPath: 'x',
          workspaceDeps: {'universal_automation_interface': '^0.4.0'},
        ),
      ];
      final errors = publishedExactVersionWorkspaceConstraintDriftErrors(
        packages: packages,
        pubDevVersions: {'universal_automation_conformance': ['0.3.1']},
        releaseSet: {'universal_automation_conformance'},
        publishedDepsAtExactVersion: {},
      );
      expect(errors, isEmpty);
    });

    test('passes when constraints match shipped tarball', () {
      final packages = [
        WorkspacePackage(
          name: 'universal_automation_conformance',
          version: '0.3.1',
          pubspecPath: 'x',
          workspaceDeps: {'universal_automation_interface': '^0.3.0'},
        ),
      ];
      final errors = publishedExactVersionWorkspaceConstraintDriftErrors(
        packages: packages,
        pubDevVersions: {
          'universal_automation_conformance': ['0.3.1'],
        },
        releaseSet: {},
        publishedDepsAtExactVersion: {
          publishedDepsAtVersionKey(
            'universal_automation_conformance',
            '0.3.1',
          ): {'universal_automation_interface': '^0.3.0'},
        },
      );
      expect(errors, isEmpty);
    });
  });

  group('auditPublishedLatestErrors', () {
    final fixForwardPackages = [
      WorkspacePackage(
        name: 'universal_pkg_a',
        version: '0.5.0',
        pubspecPath: 'x/a',
        workspaceDeps: {},
      ),
      WorkspacePackage(
        name: 'universal_pkg_b',
        version: '0.3.0',
        pubspecPath: 'x/b',
        workspaceDeps: {'universal_pkg_a': '^0.5.0'},
      ),
    ];

    const fixForwardPubVersions = {
      'universal_pkg_a': ['0.4.0'],
      'universal_pkg_b': ['0.2.0'],
    };

    /// pub.dev latest of A is broken (requires B ^0.4.0; 0.3.0 in-train too low).
    const fixForwardLatestDeps = {
      'universal_pkg_a': {'universal_pkg_b': '^0.4.0'},
    };

    const fixForwardReleaseSet = {'universal_pkg_a', 'universal_pkg_b'};

    test('release-PR in-train sibling satisfies with in-train version', () {
      final findings = auditPublishedLatestErrors(
        packages: fixForwardPackages,
        workspaceNames: {'universal_pkg_a', 'universal_pkg_b'},
        pubDevVersions: fixForwardPubVersions,
        publishedLatestDeps: {
          'universal_pkg_b': {'universal_pkg_a': '^0.2.0'},
        },
        releaseSet: fixForwardReleaseSet,
        releasePrMode: true,
      );
      expect(findings.errors, isEmpty);
    });

    test('release-PR warns when pub.dev latest is broken but train fixes it', () {
      final findings = auditPublishedLatestErrors(
        packages: fixForwardPackages,
        workspaceNames: {'universal_pkg_a', 'universal_pkg_b'},
        pubDevVersions: fixForwardPubVersions,
        publishedLatestDeps: fixForwardLatestDeps,
        releaseSet: fixForwardReleaseSet,
        releasePrMode: true,
      );
      expect(findings.errors, isEmpty);
      expect(findings.warnings, isNotEmpty);
      expect(
        findings.warnings.any((w) => w.contains('universal_pkg_a@0.4.0')),
        isTrue,
      );
    });

    test('main/post-publish still errors on broken pub.dev latest', () {
      final findings = auditPublishedLatestErrors(
        packages: fixForwardPackages,
        workspaceNames: {'universal_pkg_a', 'universal_pkg_b'},
        pubDevVersions: fixForwardPubVersions,
        publishedLatestDeps: fixForwardLatestDeps,
        releaseSet: fixForwardReleaseSet,
        releasePrMode: false,
      );
      expect(findings.errors, isNotEmpty);
      expect(findings.warnings, isEmpty);
    });

    test('version-bump: B requires A in-train; release-PR audit passes', () async {
      final code = await runAuditPublished(
        packages: fixForwardPackages,
        workspaceNames: {'universal_pkg_a', 'universal_pkg_b'},
        catalog: _FakePubDevGateway(
          versions: fixForwardPubVersions,
          latestDeps: fixForwardLatestDeps,
        ),
        releasePrMode: true,
      );
      expect(code, 0);
    });

    test('without release-pr, in-train train still blocks on main audit', () async {
      final code = await runAuditPublished(
        packages: fixForwardPackages,
        workspaceNames: {'universal_pkg_a', 'universal_pkg_b'},
        catalog: _FakePubDevGateway(
          versions: fixForwardPubVersions,
          latestDeps: fixForwardLatestDeps,
        ),
        releasePrMode: false,
      );
      expect(code, 1);
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

    test('reports exact-version constraint drift against pub.dev archives', () async {
      final packages = [
        WorkspacePackage(
          name: 'universal_automation_conformance',
          version: '0.3.1',
          pubspecPath: 'x',
          workspaceDeps: {
            'universal_automation_interface': '^0.4.0',
            'universal_screencast': '^0.3.0',
          },
        ),
      ];
      final key = publishedDepsAtVersionKey(
        'universal_automation_conformance',
        '0.3.1',
      );
      final code = await runAuditPublished(
        packages: packages,
        workspaceNames: {'universal_automation_conformance'},
        catalog: _FakePubDevGateway(
          versions: {'universal_automation_conformance': ['0.3.1']},
          versionDeps: {
            key: {
              'universal_automation_interface': '^0.3.0',
              'universal_screencast': '^0.2.0',
            },
          },
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
