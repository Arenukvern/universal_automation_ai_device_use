@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_tooling_runtime/xsoulspace_tooling_runtime.dart';

void main() {
  test(
    'owned session exec failure surfaces marker:error stage in spawnError',
    () async {
      final result = await runBounded(
        '/no/such/xsoulspace_tooling_runtime_owned_target',
        [],
        deadline: const Duration(seconds: 5),
      );
      expect(result.cause, BoundedProcessCause.spawnFailed);
      expect(result.spawnError, isNotNull);
      expect(result.spawnError, contains('exec'));
    },
    skip: Platform.isWindows ? 'POSIX owned session' : null,
  );
}
