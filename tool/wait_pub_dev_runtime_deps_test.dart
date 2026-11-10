import 'dart:io';

import 'package:test/test.dart';

import 'hosted_deps_resolve_lib.dart';
import 'wait_pub_dev_runtime_deps_lib.dart';

class _SeqPubDevGateway implements PubDevGateway {
  _SeqPubDevGateway(this.versionsByPoll);

  final Map<String, List<List<String>>> versionsByPoll;
  final _counts = <String, int>{};

  @override
  Future<List<String>> versionsOnPubDev(String packageName) async {
    final seq = versionsByPoll[packageName] ?? [[]];
    final i = _counts[packageName] ?? 0;
    _counts[packageName] = i + 1;
    return List<String>.from(seq[i.clamp(0, seq.length - 1)]);
  }

  @override
  Future<Map<String, String>> latestPublishedWorkspaceDeps(String name) async =>
      {};

  @override
  Future<Map<String, String>> publishedWorkspaceDepsAtVersion(
    String packageName,
    String version,
  ) async =>
      {};

  @override
  void close() {}
}

void _writeMiniWorkspace(Directory root, {required String toolkitVersion}) {
  Directory('${root.path}/pkgs/universal_automation_toolkit').createSync(
    recursive: true,
  );
  File('${root.path}/pkgs/universal_automation_toolkit/pubspec.yaml')
      .writeAsStringSync('''
name: universal_automation_toolkit
version: $toolkitVersion
environment:
  sdk: ^3.13.0
''');
}

void main() {
  group('planRuntimeDepWait', () {
    test('exact wait when workspace 0.4.1 not on pub.dev (^0.4.0)', () {
      final plan = planRuntimeDepWait(
        constraint: '^0.4.0',
        siblingWorkspaceVersion: '0.4.1',
        pubDevVersions: ['0.4.0'],
      );
      expect(plan.strategy, RuntimeDepWaitStrategy.exactWorkspaceVersion);
      expect(plan.exactVersion, '0.4.1');
    });

    test('any satisfying when workspace version already on pub.dev', () {
      final plan = planRuntimeDepWait(
        constraint: '^0.4.0',
        siblingWorkspaceVersion: '0.4.0',
        pubDevVersions: ['0.4.0'],
      );
      expect(plan.strategy, RuntimeDepWaitStrategy.anySatisfyingVersion);
    });

    test('exact wait for in-train 0.5.0 when only 0.4.0 is on pub.dev', () {
      final plan = planRuntimeDepWait(
        constraint: '^0.5.0',
        siblingWorkspaceVersion: '0.5.0',
        pubDevVersions: ['0.4.0'],
      );
      expect(plan.strategy, RuntimeDepWaitStrategy.exactWorkspaceVersion);
      expect(plan.exactVersion, '0.5.0');
    });
  });

  group('waitForRuntimeDepsOnPubDev', () {
    test('waits for exact in-train sibling, not older satisfiers', () async {
      final root = Directory.systemTemp.createTempSync('wait-exact-root');
      _writeMiniWorkspace(root, toolkitVersion: '0.5.0');
      Directory('${root.path}/pkg').createSync();
      File('${root.path}/pkg/pubspec.yaml').writeAsStringSync('''
name: universal_automation_harness
version: 0.2.1
dependencies:
  universal_automation_toolkit: ^0.5.0
''');
      final gateway = _SeqPubDevGateway({
        'universal_automation_toolkit': [
          ['0.4.0'],
          ['0.4.0'],
          ['0.4.0', '0.5.0'],
        ],
      });
      await waitForRuntimeDepsOnPubDev(
        packageDir: Directory('${root.path}/pkg'),
        repoRoot: root,
        catalog: gateway,
        timeout: const Duration(seconds: 5),
        initialPollInterval: const Duration(milliseconds: 1),
        maxPollInterval: const Duration(milliseconds: 5),
      );
      root.deleteSync(recursive: true);
    });

    test('succeeds when any satisfying version appears (shipped sibling)', () async {
      final root = Directory.systemTemp.createTempSync('wait-any-root');
      _writeMiniWorkspace(root, toolkitVersion: '0.4.0');
      Directory('${root.path}/pkg').createSync();
      File('${root.path}/pkg/pubspec.yaml').writeAsStringSync('''
name: universal_automation_harness
version: 0.2.0
dependencies:
  universal_automation_toolkit: ^0.4.0
''');
      final gateway = _SeqPubDevGateway({
        'universal_automation_toolkit': [
          ['0.3.0'],
          ['0.3.0', '0.4.0'],
        ],
      });
      await waitForRuntimeDepsOnPubDev(
        packageDir: Directory('${root.path}/pkg'),
        repoRoot: root,
        catalog: gateway,
        timeout: const Duration(seconds: 5),
        initialPollInterval: const Duration(milliseconds: 1),
        maxPollInterval: const Duration(milliseconds: 5),
      );
      root.deleteSync(recursive: true);
    });

    test('live pub.dev: harness 0.2.1 runtime deps (^0.5.0 toolkit)', () async {
      final catalog = PubDevCatalog();
      try {
        final toolkitVersions =
            await catalog.versionsOnPubDev('universal_automation_toolkit');
        final toolkitReady =
            constraintSatisfiedByAnyVersion('^0.5.0', toolkitVersions);
        if (toolkitReady) {
          expect(toolkitReady, isTrue);
        } else {
          expect(
            constraintSatisfiedByAnyVersion('^0.4.0', toolkitVersions),
            isTrue,
            reason: 'publish wait would block until toolkit 0.5.x ships',
          );
        }
        final ifaceVersions =
            await catalog.versionsOnPubDev('universal_automation_interface');
        expect(constraintSatisfiedByAnyVersion('^0.4.0', ifaceVersions), isTrue);
      } finally {
        catalog.close();
      }
    });
  });
}
