@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

Future<Uri> _workspacePackageConfig() async {
  final entry = await Isolate.resolvePackageUri(
    Uri.parse(
      'package:universal_tooling_runtime/universal_tooling_runtime.dart',
    ),
  );
  expect(entry, isNotNull);
  var dir = File.fromUri(entry!).parent.parent;
  while (true) {
    final candidate = File('${dir.path}/.dart_tool/package_config.json');
    if (candidate.existsSync()) {
      return candidate.absolute.uri;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      fail('package_config.json not found above ${dir.path}');
    }
    dir = parent;
  }
}

void main() {
  test('abandoned host anchor kills the admitted group', () async {
    final directory = Directory.systemTemp.createTempSync('anchor-orphan-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final packageConfig = await _workspacePackageConfig();
    final script = File('${directory.path}/driver.dart')
      ..writeAsStringSync('''
import 'dart:io';
import 'package:universal_tooling_runtime/universal_tooling_runtime.dart';

Future<void> main() async {
  await runBounded(
    'sh',
    ['-c', r'sleep 120 & echo \$! > sleeper.pid; wait'],
    deadline: const Duration(hours: 1),
  );
}
''');
    final driver = await Process.start(
      Platform.resolvedExecutable,
      ['--packages=$packageConfig', script.path],
      workingDirectory: directory.path,
      environment: Platform.environment,
    );
    final childPidFile = File('${directory.path}/sleeper.pid');
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!childPidFile.existsSync() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(childPidFile.existsSync(), isTrue);
    final childPid = int.parse(childPidFile.readAsStringSync());
    driver.kill();
    await driver.exitCode.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(
      (await Process.run('kill', ['-0', '$childPid'])).exitCode,
      isNot(0),
      reason:
          'supervisor must tear down the group when the host anchor vanishes',
    );
  }, skip: Platform.isWindows ? 'POSIX session ownership' : null);
}
