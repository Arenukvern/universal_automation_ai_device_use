// Ensures workspace sibling dependencies resolve on pub.dev and that
// tool/publish_order.yaml is a valid topological publish order.
//
// Usage:
//   dart run tool/check_hosted_deps_resolve.dart
//   dart run tool/check_hosted_deps_resolve.dart --audit-published
//   dart run tool/check_hosted_deps_resolve.dart --release-manifest .release-please-manifest.json

import 'dart:io';

import 'hosted_deps_resolve_lib.dart';
import 'workspace_pub_constraints_sync.dart';

Future<void> main(List<String> args) async {
  final auditPublished = args.contains('--audit-published');
  final manifestFlag = args.indexOf('--release-manifest');
  String? manifestPath;
  if (manifestFlag >= 0) {
    if (manifestFlag + 1 >= args.length) {
      stderr.writeln('--release-manifest requires a path');
      exit(64);
    }
    manifestPath = args[manifestFlag + 1];
  }

  final publishOrderPath = _flagValue(args, '--publish-order') ??
      '${findWorkspaceRepoRoot().path}/tool/publish_order.yaml';

  final repoRoot = findWorkspaceRepoRoot();
  final packages = loadWorkspacePackages(repoRoot);
  final workspaceNames = packages.map((p) => p.name).toSet();

  final releaseByName = manifestPath != null
      ? loadReleaseManifestVersions(repoRoot, manifestPath)
      : loadReleaseManifestVersions(
          repoRoot,
          '${repoRoot.path}/.release-please-manifest.json',
        );

  final catalog = PubDevCatalog();
  try {
    if (auditPublished) {
      exit(
        await runAuditPublished(
          packages: packages,
          workspaceNames: workspaceNames,
          catalog: catalog,
        ),
      );
    }

    final graph = workspaceDependencyGraph(packages);
    final computedOrder = topologicalPublishOrder(graph);
    stdout.writeln('Computed topological publish order:');
    for (final name in computedOrder) {
      stdout.writeln('  - $name');
    }

    List<String> configuredOrder;
    try {
      configuredOrder = loadPublishOrderYaml(publishOrderPath);
    } on StateError catch (e) {
      stderr.writeln('Publish order check failed: ${e.message}');
      exit(1);
    }

    final orderErrors = validatePublishOrderList(configuredOrder, graph);

    Map<String, List<String>> pubVersions;
    try {
      pubVersions = await fetchAllPubDevVersions(catalog, workspaceNames);
    } on HttpException catch (e) {
      stderr.writeln('Hosted dependency check failed: HTTP error from pub.dev: $e');
      exit(1);
    } on SocketException catch (e) {
      stderr.writeln('Hosted dependency check failed: could not reach pub.dev: $e');
      exit(1);
    } on IOException catch (e) {
      stderr.writeln('Hosted dependency check failed: I/O error talking to pub.dev: $e');
      exit(1);
    }

    final dependencyErrors = resolveErrorsAlongPublishOrder(
      packages: packages,
      workspaceNames: workspaceNames,
      pubDevVersions: pubVersions,
      releaseManifestByName: releaseByName,
      publishOrder: configuredOrder,
    );

    if (orderErrors.isNotEmpty) {
      stderr.writeln('Publish order check failed:\n');
      for (final e in orderErrors) {
        stderr.writeln('  - $e');
      }
    }
    if (dependencyErrors.isNotEmpty) {
      stderr.writeln(
        'Hosted sibling dependency check failed (publish-order batch):\n',
      );
      for (final e in dependencyErrors) {
        stderr.writeln('  - $e');
      }
    }

    if (dependencyErrors.isNotEmpty || orderErrors.isNotEmpty) {
      exit(1);
    }

    stdout.writeln(
      'Workspace sibling dependencies resolve along publish_order.yaml '
      '(pub.dev ∪ earlier co-release manifest versions).',
    );
    stdout.writeln('Publish order file is a valid topological order.');
  } finally {
    catalog.close();
  }
}

String? _flagValue(List<String> args, String flag) {
  final i = args.indexOf(flag);
  if (i < 0 || i + 1 >= args.length) {
    return null;
  }
  return args[i + 1];
}
