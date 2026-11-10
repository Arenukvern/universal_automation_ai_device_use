import 'dart:io';

import 'hosted_deps_resolve_lib.dart';
import 'workspace_pub_constraints_sync.dart';

/// How long to wait for a runtime sibling before publish.
enum RuntimeDepWaitStrategy {
  /// Sibling's workspace version is not on pub.dev yet — wait for that exact semver.
  exactWorkspaceVersion,

  /// Sibling already at workspace version on pub.dev, or workspace version does not
  /// match constraint — wait for any pub.dev version satisfying the constraint.
  anySatisfyingVersion,
}

class RuntimeDepWaitPlan {
  RuntimeDepWaitPlan({
    required this.strategy,
    this.exactVersion,
  });

  final RuntimeDepWaitStrategy strategy;
  final String? exactVersion;
}

/// Chooses exact-version wait when the in-train sibling version satisfies
/// [constraint] but is not yet listed on pub.dev.
RuntimeDepWaitPlan planRuntimeDepWait({
  required String constraint,
  required String? siblingWorkspaceVersion,
  required List<String> pubDevVersions,
}) {
  if (siblingWorkspaceVersion == null || siblingWorkspaceVersion.isEmpty) {
    return RuntimeDepWaitPlan(strategy: RuntimeDepWaitStrategy.anySatisfyingVersion);
  }
  if (!constraintSatisfiedByAnyVersion(constraint, [siblingWorkspaceVersion])) {
    return RuntimeDepWaitPlan(strategy: RuntimeDepWaitStrategy.anySatisfyingVersion);
  }
  if (pubDevVersions.contains(siblingWorkspaceVersion)) {
    return RuntimeDepWaitPlan(strategy: RuntimeDepWaitStrategy.anySatisfyingVersion);
  }
  return RuntimeDepWaitPlan(
    strategy: RuntimeDepWaitStrategy.exactWorkspaceVersion,
    exactVersion: siblingWorkspaceVersion,
  );
}

/// Polls pub.dev until runtime `universal_*` deps are ready to publish [packageDir].
Future<void> waitForRuntimeDepsOnPubDev({
  required Directory packageDir,
  required Directory repoRoot,
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

  final byName = {
    for (final p in loadWorkspacePackages(repoRoot)) p.name: p.version,
  };

  final deadline = DateTime.now().add(timeout);
  var backoff = initialPollInterval;

  for (final entry in deps.entries) {
    final depName = entry.key;
    final constraint = entry.value;
    final siblingVersion = byName[depName];

    if (catalog is PubDevCatalog) {
      catalog.clearVersionCache(depName);
    }
    final pubListed = await catalog.versionsOnPubDev(depName);
    final plan = planRuntimeDepWait(
      constraint: constraint,
      siblingWorkspaceVersion: siblingVersion,
      pubDevVersions: pubListed,
    );

    if (plan.strategy == RuntimeDepWaitStrategy.exactWorkspaceVersion) {
      stdout.writeln(
        '${header.name}: waiting for exact in-train $depName@${plan.exactVersion} '
        '(constraint $constraint)',
      );
      await waitForVersionOnPubDev(
        catalog: catalog,
        packageName: depName,
        version: plan.exactVersion!,
        timeout: deadline.difference(DateTime.now()),
        initialPollInterval: initialPollInterval,
      );
      continue;
    }

    var polls = 0;
    var satisfied = false;
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
        satisfied = true;
        backoff = initialPollInterval;
        break;
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        break;
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
    if (!satisfied) {
      final versions = await catalog.versionsOnPubDev(depName);
      throw StateError(
        'Timeout waiting for $depName $constraint on pub.dev for '
        '${header.name} (${timeout.inMinutes}m, $polls polls). '
        'Have: ${versions.join(', ')}',
      );
    }
  }
}
