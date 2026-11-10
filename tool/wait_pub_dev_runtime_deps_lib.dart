import 'dart:io';

import 'hosted_deps_resolve_lib.dart';
import 'workspace_pub_constraints_sync.dart';

/// Polls pub.dev until every `universal_*` **runtime** dependency of [packageDir]
/// has at least one published version satisfying its constraint.
Future<void> waitForRuntimeDepsOnPubDev({
  required Directory packageDir,
  required PubDevGateway catalog,
  Duration timeout = const Duration(minutes: 20),
  Duration initialPollInterval = const Duration(seconds: 15),
  Duration maxPollInterval = const Duration(seconds: 60),
}) async {
  final pubspec = File('${packageDir.path}/pubspec.yaml');
  if (!pubspec.existsSync()) {
    throw StateError('Missing pubspec: ${pubspec.path}');
  }
  final content = pubspec.readAsStringSync();
  final header = parsePubspecHeader(content);
  final deps = parseWorkspaceDependencies(content);
  if (deps.isEmpty) {
    stdout.writeln(
      '${header.name}: no universal_* runtime dependencies; nothing to wait for',
    );
    return;
  }

  final deadline = DateTime.now().add(timeout);
  var backoff = initialPollInterval;

  for (final entry in deps.entries) {
    final depName = entry.key;
    final constraint = entry.value;
    var polls = 0;
    while (DateTime.now().isBefore(deadline)) {
      polls++;
      if (catalog is PubDevCatalog) {
        catalog.clearVersionCache(depName);
      }
      final versions = await catalog.versionsOnPubDev(depName);
      if (constraintSatisfiedByAnyVersion(constraint, versions)) {
        stdout.writeln(
          '${header.name}: $depName $constraint satisfied on pub.dev '
          '(poll $polls; versions: ${versions.join(', ')})',
        );
        backoff = initialPollInterval;
        break;
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw StateError(
          'Timeout waiting for $depName $constraint on pub.dev for '
          '${header.name} (${timeout.inMinutes}m, $polls polls). '
          'Have: ${versions.join(', ')}',
        );
      }
      stdout.writeln(
        'Waiting for $depName $constraint (poll $polls; pub.dev has: '
        '${versions.isEmpty ? 'none' : versions.join(', ')})…',
      );
      final sleep = remaining < backoff ? remaining : backoff;
      await Future<void>.delayed(sleep);
      final nextMs = (backoff.inMilliseconds * 1.5).round();
      backoff = Duration(
        milliseconds: nextMs.clamp(
          initialPollInterval.inMilliseconds,
          maxPollInterval.inMilliseconds,
        ),
      );
    }
    if (!DateTime.now().isBefore(deadline) &&
        !await _satisfied(catalog, depName, constraint)) {
      throw StateError(
        'Timeout waiting for $depName $constraint on pub.dev for ${header.name}',
      );
    }
  }
}

Future<bool> _satisfied(
  PubDevGateway catalog,
  String depName,
  String constraint,
) async {
  final versions = await catalog.versionsOnPubDev(depName);
  return constraintSatisfiedByAnyVersion(constraint, versions);
}
