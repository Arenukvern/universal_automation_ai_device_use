// Manual pub.dev publish train: checks, then dry-run or publish per package.
//
//   dart run tool/publish_in_order.dart
//   dart run tool/publish_in_order.dart --publish   # owner only: real publish
//
// Reads tool/publish_order.yaml, computes the release set (--co-release rules),
// runs hosted-deps + drift checks, then `dart pub publish --dry-run` per
// release-set package in order (stops at first failure).

import 'dart:io';

import 'hosted_deps_resolve_lib.dart';
import 'workspace_pub_constraints_sync.dart';

Future<void> main(List<String> args) async {
  final doPublish = args.contains('--publish');

  final repoRoot = findWorkspaceRepoRoot();
  final publishOrderPath = '${repoRoot.path}/tool/publish_order.yaml';
  final manifestPath = '${repoRoot.path}/.release-please-manifest.json';

  final packages = loadWorkspacePackages(repoRoot);
  final workspaceNames = packages.map((p) => p.name).toSet();
  final manifestByName = loadReleaseManifestVersions(repoRoot, manifestPath);
  final configuredOrder = loadPublishOrderYaml(publishOrderPath);
  final byName = {for (final p in packages) p.name: p};

  final catalog = PubDevCatalog();
  try {
    final pubVersions = await fetchAllPubDevVersions(catalog, workspaceNames);
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
      exit(1);
    }

    for (final name in configuredOrder) {
      if (!releaseSet.contains(name)) {
        continue;
      }
      final dir = packageDirectory(byName[name]!);
      final publishArgs = doPublish
          ? ['pub', 'publish', '-f']
          : ['pub', 'publish', '--dry-run'];
      stdout.writeln(
        '\n--- dart ${publishArgs.join(' ')} ($name) ---',
      );
      final result = await Process.run(
        'dart',
        publishArgs,
        workingDirectory: dir.path,
        runInShell: true,
      );
      stdout.write(result.stdout);
      stderr.write(result.stderr);
      if (result.exitCode != 0) {
        stderr.writeln('Stopped: dry-run failed for $name');
        exit(result.exitCode);
      }
    }

    final verb = doPublish ? 'publishes' : 'dry-runs';
    stdout.writeln('\nAll release-set $verb passed (in publish_order.yaml order).');
  } finally {
    catalog.close();
  }
}
