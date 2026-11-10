import 'dart:io';

import 'package:test/test.dart';

import 'hosted_deps_resolve_lib.dart';
import 'publish_in_order.dart';
import 'workspace_pub_constraints_sync.dart';

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
  Future<Map<String, String>> publishedWorkspaceDepsAtVersion(
    String packageName,
    String version,
  ) async => {};

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
  Future<Map<String, String>> publishedWorkspaceDepsAtVersion(
    String packageName,
    String version,
  ) async => {};

  @override
  void close() {}
}

/// pub.dev version lists aligned with the fix-forward publish table (2026-11-09).
const _fixForwardPubVersions = <String, List<String>>{
  'universal_automation_interface': ['0.1.0', '0.1.1', '0.2.0', '0.3.0'],
  'universal_automation_semantics': ['0.1.0', '0.2.0', '0.4.0', '0.5.0'],
  'universal_browser_cdp': ['0.1.0', '0.1.1', '0.2.0', '0.3.0', '0.4.0'],
  'universal_browser_webdriver': ['0.1.1', '0.2.0'],
  'universal_driver_flutter': ['0.1.0', '0.1.1'],
  'universal_driver_linux': ['0.1.0', '0.1.1', '0.2.0'],
  'universal_driver_macos': ['0.1.0', '0.1.1', '0.2.0', '0.2.1', '0.3.0'],
  'universal_driver_windows': ['0.1.0', '0.1.1', '0.2.0'],
  'universal_screencast': ['0.1.0', '0.1.1', '0.1.2', '0.2.0'],
  'universal_automation_conformance': ['0.1.0', '0.2.0', '0.3.0', '0.3.1'],
  'universal_automation_toolkit': ['0.1.0', '0.1.1', '0.2.0', '0.4.0'],
  'universal_automation_harness': ['0.1.0', '0.1.1'],
  'universal_capture_flutter': ['0.1.0', '0.1.1', '0.2.0'],
  'universal_capture_macos': ['0.1.0', '0.1.1', '0.1.2', '0.2.0'],
  'universal_tooling_runtime': ['0.2.0', '0.2.2'],
  'universal_webrtc_raw': ['0.1.0'],
  'universal_webrtc': ['0.1.0', '0.1.1', '0.2.0'],
};

const _fixForwardManifest24 = r'''
{
  "pkgs/universal_automation_conformance": "0.3.1",
  "pkgs/universal_automation_harness": "0.1.1",
  "pkgs/universal_automation_interface": "0.3.0",
  "pkgs/universal_automation_semantics": "0.5.0",
  "pkgs/universal_automation_toolkit": "0.4.0",
  "pkgs/universal_browser_cdp": "0.4.0",
  "pkgs/universal_browser_webdriver": "0.2.0",
  "pkgs/universal_capture_flutter": "0.2.0",
  "pkgs/universal_capture_macos": "0.2.0",
  "pkgs/universal_driver_flutter": "0.1.1",
  "pkgs/universal_driver_linux": "0.2.0",
  "pkgs/universal_driver_macos": "0.3.0",
  "pkgs/universal_driver_windows": "0.2.0",
  "pkgs/universal_screencast": "0.2.0",
  "pkgs/universal_webrtc": "0.2.0",
  "pkgs/universal_webrtc_raw": "0.1.0",
  "pkgs/universal_tooling_runtime": "0.2.2"
}
''';

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

  group('publish train sibling gate', () {
    late List<WorkspacePackage> packages;
    late Map<String, WorkspacePackage> byName;
    late List<String> publishOrder;

    setUp(() {
      final root = findWorkspaceRepoRoot();
      packages = loadWorkspacePackages(root);
      byName = {for (final p in packages) p.name: p};
      publishOrder = loadPublishOrderYaml('${root.path}/tool/publish_order.yaml');
    });

    test(
      'dry-run train: pending interface 0.4.0 satisfies ^0.4.0 for cdp',
      () {
        final releaseSet = computeReleaseSet(
          packages: packages,
          pubDevVersions: _fixForwardPubVersions,
          coReleaseEnabled: true,
        );
        expect(releaseSet.contains('universal_automation_interface'), isTrue);

        final cdp = byName['universal_browser_cdp']!;
        final dryRunErrors = siblingDepErrorsAtPublishStep(
          pkg: cdp,
          workspaceNames: packages.map((p) => p.name).toSet(),
          pubDevVersions: _fixForwardPubVersions,
          byName: byName,
          releaseSet: releaseSet,
          publishOrder: publishOrder,
          simulateCoReleaseTrain: true,
        );
        expect(dryRunErrors, isEmpty);

        final publishErrors = siblingDepErrorsAtPublishStep(
          pkg: cdp,
          workspaceNames: packages.map((p) => p.name).toSet(),
          pubDevVersions: _fixForwardPubVersions,
          byName: byName,
          releaseSet: releaseSet,
          publishOrder: publishOrder,
          simulateCoReleaseTrain: false,
        );
        expect(publishErrors, isNotEmpty);
        expect(publishErrors.single, contains('^0.4.0'));
      },
    );

    test(
      'fix-forward dry-run: 11-package train completes with mocked pub publish',
      () async {
        final root = findWorkspaceRepoRoot();
        final manifestFile = File('${root.path}/.release-please-manifest.test24.json');
        addTearDown(() {
          if (manifestFile.existsSync()) {
            manifestFile.deleteSync();
          }
        });
        manifestFile.writeAsStringSync(_fixForwardManifest24);

        final gateway = _MutablePubDevGateway(versions: _fixForwardPubVersions);
        final published = <String>[];
        final code = await runPublishInOrder(
          doPublish: false,
          repoRoot: root,
          manifestPathOverride: manifestFile.path,
          catalog: gateway,
          publishRunner: (dir, args) async {
            published.add(dir.path);
            return 0;
          },
        );
        expect(code, 0);
        expect(published.length, 11);
      },
    );

    test(
      'real --publish path uses pub.dev-only gate (harness needs interface on pub.dev)',
      () {
        final releaseSet = computeReleaseSet(
          packages: packages,
          pubDevVersions: _fixForwardPubVersions,
          coReleaseEnabled: true,
        );
        final harness = byName['universal_automation_harness']!;
        expect(releaseSet.contains('universal_automation_harness'), isTrue);

        final dryRun = siblingDepErrorsAtPublishStep(
          pkg: harness,
          workspaceNames: packages.map((p) => p.name).toSet(),
          pubDevVersions: _fixForwardPubVersions,
          byName: byName,
          releaseSet: releaseSet,
          publishOrder: publishOrder,
          simulateCoReleaseTrain: true,
        );
        expect(dryRun, isEmpty);

        final realPublish = siblingDepErrorsAtPublishStep(
          pkg: harness,
          workspaceNames: packages.map((p) => p.name).toSet(),
          pubDevVersions: _fixForwardPubVersions,
          byName: byName,
          releaseSet: releaseSet,
          publishOrder: publishOrder,
          simulateCoReleaseTrain: false,
        );
        expect(realPublish.any((e) => e.contains('^0.4.0')), isTrue);
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
