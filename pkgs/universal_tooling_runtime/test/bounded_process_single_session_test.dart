@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_tooling_runtime/universal_tooling_runtime.dart';

void main() {
  test(
    'singleProcessSession exec failure surfaces marker:error as spawnFailed',
    () async {
      final result = await runBounded(
        '/no/such/universal_tooling_runtime_target',
        [],
        singleProcessSession: true,
        deadline: const Duration(seconds: 5),
      );
      expect(result.cause, BoundedProcessCause.spawnFailed);
      expect(result.spawnError, isNotNull);
      expect(result.spawnError, isNotEmpty);
      expect(result.spawnError, contains('exec'));
    },
    skip: Platform.isWindows ? 'POSIX singleProcessSession' : null,
  );
}
