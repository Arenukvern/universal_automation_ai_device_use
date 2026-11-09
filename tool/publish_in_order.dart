// Manual pub.dev publish train: checks, then dry-run or publish per package.
//
//   dart run tool/publish_in_order.dart
//   dart run tool/publish_in_order.dart --publish   # owner only: real publish
//
// Reads tool/publish_order.yaml, computes the release set (--co-release rules),
// runs hosted-deps + drift checks, then `dart pub publish --dry-run` per
// release-set package in order (stops at first failure). With --publish, waits
// for each version on pub.dev before publishing dependents (fail closed).

import 'dart:io';

import 'hosted_deps_resolve_lib.dart';
import 'workspace_pub_constraints_sync.dart';

Future<void> main(List<String> args) async {
  exit(await runPublishInOrder(doPublish: args.contains('--publish')));
}

/// Entry point for tests and CLI.
Future<int> runPublishInOrder({
  required bool doPublish,
  PubDevGateway? catalog,
  Directory? repoRoot,
  Future<int> Function(Directory dir, List<String> publishArgs)? publishRunner,
}) async {
  final root = repoRoot ?? findWorkspaceRepoRoot();
  final publishOrderPath = '${root.path}/tool/publish_order.yaml';
  final manifestPath = '${root.path}/.release-please-manifest.json';

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
    stdout.writeln('Packages selected for this publish train:');
    for (final name in configuredOrder) {
      if (releaseSet.contains(name)) {
        stdout.writeln('  - $name@${byName[name]!.version}');
      }
    }

    final driftErrors = manifestDriftErrors(
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

    if (driftErrors.isNotEmpty || dependencyErrors.isNotEmpty) {
      stderr.writeln('Pre-publish checks failed:\n');
      for (final e in [...driftErrors, ...dependencyErrors]) {
        stderr.writeln('  - $e');
      }
      return 1;
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
      final pubDevOnlyErrors = siblingDepErrorsPubDevOnly(
        pkg: pkg,
        workspaceNames: workspaceNames,
        pubDevVersions: pubVersions,
      );
      if (pubDevOnlyErrors.isNotEmpty) {
        stderr.writeln(
          'Refusing to publish $name: siblings must already be on pub.dev:\n',
        );
        for (final e in pubDevOnlyErrors) {
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
