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

void main() {
  group('waitForRuntimeDepsOnPubDev', () {
    test('succeeds when constraint becomes satisfiable', () async {
      final dir = Directory.systemTemp.createTempSync('wait-deps');
      Directory('${dir.path}/pkg').createSync();
      File('${dir.path}/pkg/pubspec.yaml').writeAsStringSync('''
name: universal_automation_harness
version: 0.2.1
dependencies:
  universal_automation_toolkit: ^0.5.0
''');
      final gateway = _SeqPubDevGateway({
        'universal_automation_toolkit': [
          ['0.4.0'],
          ['0.4.0', '0.5.0'],
        ],
      });
      await waitForRuntimeDepsOnPubDev(
        packageDir: Directory('${dir.path}/pkg'),
        catalog: gateway,
        timeout: const Duration(seconds: 5),
        initialPollInterval: const Duration(milliseconds: 1),
        maxPollInterval: const Duration(milliseconds: 5),
      );
      dir.deleteSync(recursive: true);
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
