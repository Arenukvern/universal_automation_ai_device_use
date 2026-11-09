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
    final pubVersions = await fetchAllPubDevVersions(
      catalog,
      workspaceNames,
    );

    if (auditPublished) {
      final latestDeps = <String, Map<String, String>>{};
      for (final name in workspaceNames) {
        latestDeps[name] = await catalog.latestPublishedWorkspaceDeps(name);
      }
      final errors = auditPublishedLatestErrors(
        packages: packages,
        workspaceNames: workspaceNames,
        pubDevVersions: pubVersions,
        publishedLatestDeps: latestDeps,
      );
      if (errors.isEmpty) {
        stdout.writeln('All pub.dev latest packages resolve sibling deps.');
        return;
      }
      stderr.writeln('pub.dev hosted dependency audit failed:\n');
      for (final e in errors) {
        stderr.writeln('  - $e');
      }
      exit(1);
    }

    final dependencyErrors = resolveErrors(
      packages: packages,
      workspaceNames: workspaceNames,
      pubDevVersions: pubVersions,
      releaseManifestByName: releaseByName,
    );

    final graph = workspaceDependencyGraph(packages);
    final computedOrder = topologicalPublishOrder(graph);
    stdout.writeln('Computed topological publish order:');
    for (final name in computedOrder) {
      stdout.writeln('  - $name');
    }

    List<String> orderErrors = [];
    try {
      final configured = loadPublishOrderYaml(publishOrderPath);
      orderErrors = validatePublishOrderList(configured, graph);
    } on StateError catch (e) {
      orderErrors = [e.message];
    }

    if (dependencyErrors.isNotEmpty) {
      stderr.writeln('Hosted sibling dependency check failed:\n');
      for (final e in dependencyErrors) {
        stderr.writeln('  - $e');
      }
    }
    if (orderErrors.isNotEmpty) {
      stderr.writeln('Publish order check failed:\n');
      for (final e in orderErrors) {
        stderr.writeln('  - $e');
      }
    }

    if (dependencyErrors.isNotEmpty || orderErrors.isNotEmpty) {
      exit(1);
    }

    stdout.writeln(
      'Workspace sibling dependencies resolve (pub.dev ∪ release-please manifest).',
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
