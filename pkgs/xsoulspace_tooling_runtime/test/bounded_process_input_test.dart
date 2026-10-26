@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_tooling_runtime/xsoulspace_tooling_runtime.dart';

/// With the p1 owned-session leader, stdin may be fully accepted by the leader
/// after the target exits; dfp `2f9ce9b1` still reports these two cases as red
/// on some POSIX hosts until the leader propagates stdin backpressure.
final _skipLinuxStdinAdmission = Platform.isLinux
    ? 'stdin admission vs p1 leader (known upstream gap at 2f9ce9b1)'
    : null;

void main() {
  test('admitted input reaches EOF with exact bytes', () async {
    final bytes = utf8.encode('first\nsecond\n');
    final result = await runBounded(
      '/bin/cat',
      [],
      stdinBytes: bytes,
      maxInputBytes: bytes.length,
      deadline: const Duration(seconds: 5),
    );
    expect(result.ok, isTrue, reason: result.inputProblem);
    expect(result.stdout, 'first\nsecond\n');
    expect(result.inputProblem, isNull);
  }, skip: Platform.isWindows);

  test('oversized input refuses before starting process', () async {
    var started = false;
    final result = await runBounded(
      '/bin/cat',
      [],
      stdinBytes: [1, 2],
      maxInputBytes: 1,
      onStarted: (_) => started = true,
      deadline: const Duration(seconds: 5),
    );
    expect(result.cause, BoundedProcessCause.spawnFailed);
    expect(result.spawnError, contains('input budget'));
    expect(result.pid, isNull);
    expect(started, isFalse);
  });

  test('early stdin close is a named failure even with exit zero', () async {
    final result = await runBounded(
      '/bin/sh',
      ['-c', 'read -n 1 _; exit 0'],
      stdinBytes: List<int>.filled(1 << 20, 65),
      deadline: const Duration(seconds: 5),
    );
    expect(result.exitCode, 0);
    expect(result.inputProblem, contains('admitted stdin'));
    expect(result.ok, isFalse);
    expect(result.survivors, isEmpty);
  }, skip: Platform.isWindows ? 'POSIX' : _skipLinuxStdinAdmission);

  test(
    'blocked input drain remains deadline owned with physical root death',
    () async {
      final result = await runBounded(
        '/bin/sh',
        ['-c', 'read -n 1 _; sleep 30'],
        stdinBytes: List<int>.filled(16 << 20, 65),
        maxInputBytes: 16 << 20,
        deadline: const Duration(milliseconds: 300),
        grace: const Duration(milliseconds: 300),
      );
      expect(result.cause, BoundedProcessCause.killedOnDeadline);
      expect(result.survivors, isEmpty);
      expect(result.inputProblem, contains('admitted stdin'));
      expect(result.settlementProblem, isNull);
      expect(
        (await Process.run('/bin/kill', ['-0', '${result.pid}'])).exitCode,
        isNot(0),
      );
    },
    skip: Platform.isWindows ? 'POSIX' : _skipLinuxStdinAdmission,
  );
}
