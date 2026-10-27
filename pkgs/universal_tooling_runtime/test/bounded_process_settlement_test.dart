@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_tooling_runtime/universal_tooling_runtime.dart';

void main() {
  test(
    'reported survivor ownership settles promptly once the tree is stopped',
    () async {
      final process = await Process.start('sh', ['-c', 'sleep 30 & wait']);
      addTearDown(() async {
        await stopProcessTree(process.pid);
        await process.exitCode;
      });
      var settled = false;
      final settlement = awaitProcessSettlement([process.pid]);
      unawaited(settlement.then((value) => settled = value));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(settled, isFalse);
      await stopProcessTree(
        process.pid,
        grace: const Duration(milliseconds: 100),
      );
      await process.exitCode;
      final watch = Stopwatch()..start();
      expect(await settlement, isTrue);
      expect(
        watch.elapsed,
        lessThan(const Duration(seconds: 5)),
        reason: 'death must be observed without waiting for the full budget',
      );
      expect(
        (await Process.run('kill', ['-0', '${process.pid}'])).exitCode,
        isNot(0),
      );
    },
    skip: Platform.isWindows ? 'POSIX process observation' : null,
  );

  test(
    'unavailable ps cannot certify death before observation recovers',
    () async {
      var unavailable = true;
      boundedProcessPsRowsOverride = () async {
        if (unavailable) return null;
        return null;
      };
      addTearDown(() {
        boundedProcessPsRowsOverride = null;
        unavailable = false;
      });

      final process = await Process.start('sh', ['-c', 'sleep 3600']);
      addTearDown(() async {
        unavailable = false;
        boundedProcessPsRowsOverride = null;
        await stopProcessTree(process.pid);
        await process.exitCode;
      });

      var settled = false;
      final settlement = awaitProcessSettlement([process.pid]);
      unawaited(settlement.then((value) => settled = value));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(settled, isFalse);

      await stopProcessTree(
        process.pid,
        grace: const Duration(milliseconds: 100),
      );
      await process.exitCode;
      unavailable = false;
      boundedProcessPsRowsOverride = null;
      expect(await settlement, isTrue);
    },
    skip: Platform.isWindows ? 'POSIX process observation' : null,
  );

  test(
    'budget expiry does not certify death while obligations remain',
    () async {
      final process = await Process.start('sh', ['-c', 'sleep 3600']);
      addTearDown(() async {
        await stopProcessTree(process.pid);
        await process.exitCode;
      });

      final watch = Stopwatch()..start();
      expect(
        await awaitProcessSettlement([
          process.pid,
        ], budget: const Duration(milliseconds: 250)),
        isFalse,
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(
        (await Process.run('kill', ['-0', '${process.pid}'])).exitCode,
        0,
        reason: 'budget expiry must not signal the owned pid',
      );
    },
    skip: Platform.isWindows ? 'POSIX process observation' : null,
  );
}
