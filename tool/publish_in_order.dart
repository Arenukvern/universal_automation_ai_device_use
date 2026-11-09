// Manual pub.dev publish train: owner runs locally (Mac) with their pub.dev login.
//
//   dart run tool/publish_in_order.dart
//   dart run tool/publish_in_order.dart --publish
//   dart run tool/publish_in_order.dart --publish --yes
//
// Default is dry-run: prints release set, publish order, and exact commands.
// Real publishes only with --publish plus interactive confirmation (type
// `publish`) or --yes.

import 'dart:io';

import 'hosted_deps_resolve_lib.dart';
import 'workspace_pub_constraints_sync.dart';

Future<void> main(List<String> args) async {
  final doPublish = args.contains('--publish');
  final skipConfirm = args.contains('--yes');
  exit(
    await runPublishInOrder(
      doPublish: doPublish,
      skipConfirm: skipConfirm,
    ),
  );
}

typedef PublishConfirm = Future<bool> Function();

/// Entry point for tests and CLI.
Future<int> runPublishInOrder({
  required bool doPublish,
  bool skipConfirm = false,
  PubDevGateway? catalog,
  Directory? repoRoot,
  String? manifestPathOverride,
  Future<int> Function(Directory dir, List<String> publishArgs)? publishRunner,
  PublishConfirm? confirmPublish,
}) async {
  final root = repoRoot ?? findWorkspaceRepoRoot();
  final publishOrderPath = '${root.path}/tool/publish_order.yaml';
  final manifestPath =
      manifestPathOverride ?? '${root.path}/.release-please-manifest.json';

  final packages = loadWorkspacePackages(root);
  final workspaceNames = packages.map((p) => p.name).toSet();
  final manifestByName = loadReleaseManifestVersions(root, manifestPath);
  final configuredOrder = loadPublishOrderYaml(publishOrderPath);
  final byName = {for (final p in packages) p.name: p};

  final gateway = catalog ?? PubDevCatalog();
  final ownsCatalog = catalog == null;
  try {
    var pubVersions = await fetchAllPubDevVersions(gateway, workspaceNames);
    final releaseSet = computeReleaseSet(
      packages: packages,
      pubDevVersions: pubVersions,
      coReleaseEnabled: true,
    );

    stdout.writeln(releaseSetRuleText);
    stdout.writeln('\nRelease set (${releaseSet.length} packages):');
    for (final name in configuredOrder) {
      if (releaseSet.contains(name)) {
        stdout.writeln('  - $name@${byName[name]!.version}');
      }
    }
    if (releaseSet.isEmpty) {
      stdout.writeln('  (empty — nothing pending on pub.dev)');
    }

    stdout.writeln('\nPublish order (tool/publish_order.yaml):');
    for (final name in configuredOrder) {
      final inTrain = releaseSet.contains(name);
      final mark = inTrain ? 'PUBLISH' : 'skip';
      stdout.writeln('  - $name [$mark]');
    }

    final policy = await evaluateVersionPolicyStrict(
      repoRoot: root,
      packages: packages,
      manifestByName: manifestByName,
      pubDevVersions: pubVersions,
      releaseSet: releaseSet,
    );
    final dependencyErrors = resolveErrorsAlongPublishOrder(
      packages: packages,
      workspaceNames: workspaceNames,
      pubDevVersions: pubVersions,
      releaseSet: releaseSet,
      publishOrder: configuredOrder,
    );

    if (policy.warnings.isNotEmpty) {
      stderr.writeln('\nVersion policy warnings:\n');
      for (final w in policy.warnings) {
        stderr.writeln('  - $w');
      }
    }

    final preflightErrors = [...policy.errors, ...dependencyErrors];
    if (preflightErrors.isNotEmpty) {
      stderr.writeln('\nPre-publish checks failed:\n');
      for (final e in preflightErrors) {
        stderr.writeln('  - $e');
      }
      return 1;
    }

    final planned = <String>[];
    for (final name in configuredOrder) {
      if (!releaseSet.contains(name)) {
        continue;
      }
      final dir = packageDirectory(byName[name]!);
      final rel = dir.path.startsWith('${root.path}/')
          ? dir.path.substring(root.path.length + 1)
          : dir.path;
      planned.add('(cd $rel && dart pub publish)');
    }

    stdout.writeln('\nPlanned commands (dry-run uses --dry-run):');
    if (planned.isEmpty) {
      stdout.writeln('  (none)');
    } else {
      for (final cmd in planned) {
        final suffix = doPublish ? '' : ' # add --dry-run';
        stdout.writeln('  $cmd$suffix');
      }
    }

    if (!doPublish) {
      stdout.writeln(
        '\nDry-run mode. Re-run with --publish to publish (owner machine + pub.dev login).',
      );
    }

    if (doPublish && releaseSet.isNotEmpty) {
      final ok = skipConfirm
          ? true
          : await (confirmPublish ?? _interactivePublishConfirm)();
      if (!ok) {
        stderr.writeln('Publish cancelled.');
        return 1;
      }
    }

    Future<int> defaultPublishRunner(Directory dir, List<String> publishArgs) async {
      final result = await Process.run(
        'dart',
        publishArgs,
        workingDirectory: dir.path,
        runInShell: true,
      );
      stdout.write(result.stdout);
      stderr.write(result.stderr);
      return result.exitCode;
    }

    final runPublish = publishRunner ?? defaultPublishRunner;

    for (final name in configuredOrder) {
      if (!releaseSet.contains(name)) {
        continue;
      }
      final pkg = byName[name]!;

      pubVersions = await fetchAllPubDevVersions(gateway, workspaceNames);
      final siblingErrors = siblingDepErrorsAtPublishStep(
        pkg: pkg,
        workspaceNames: workspaceNames,
        pubDevVersions: pubVersions,
        byName: byName,
        releaseSet: releaseSet,
        publishOrder: configuredOrder,
        simulateCoReleaseTrain: !doPublish,
      );
      if (siblingErrors.isNotEmpty) {
        final hint = doPublish
            ? 'siblings must already be on pub.dev'
            : 'sibling constraints unresolved in publish train';
        stderr.writeln('Refusing to publish $name: $hint:\n');
        for (final e in siblingErrors) {
          stderr.writeln('  - $e');
        }
        return 1;
      }

      final dir = packageDirectory(pkg);
      final publishArgs = doPublish
          ? ['pub', 'publish', '-f']
          : ['pub', 'publish', '--dry-run'];
      stdout.writeln('\n--- dart ${publishArgs.join(' ')} ($name) ---');
      final code = await runPublish(dir, publishArgs);
      if (code != 0) {
        stderr.writeln('Stopped: publish failed for $name');
        return code;
      }

      if (doPublish) {
        await waitForVersionOnPubDev(
          catalog: gateway,
          packageName: name,
          version: pkg.version,
        );
      }
    }

    final verb = doPublish ? 'publishes' : 'dry-runs';
    stdout.writeln('\nAll release-set $verb passed (in publish_order.yaml order).');

    if (doPublish) {
      stdout.writeln('\n--- post-publish audit (--audit-published) ---');
      final auditCode = await runAuditPublished(
        packages: packages,
        workspaceNames: workspaceNames,
        catalog: gateway,
      );
      if (auditCode != 0) {
        stderr.writeln('Post-publish audit failed.');
        return auditCode;
      }
    }

    return 0;
  } on StateError catch (e) {
    stderr.writeln('Publish train failed: $e');
    return 1;
  } finally {
    if (ownsCatalog) {
      gateway.close();
    }
  }
}

Future<bool> _interactivePublishConfirm() async {
  stdout.writeln(
    '\nAbout to run real `dart pub publish` for the release set. '
    'Type publish and press Enter to continue:',
  );
  final line = stdin.readLineSync();
  return line?.trim() == 'publish';
}
