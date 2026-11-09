// Ensures workspace sibling dependencies resolve on pub.dev and that
// tool/publish_order.yaml is a valid topological publish order.
//
// Usage:
//   dart run tool/check_hosted_deps_resolve.dart --co-release
//   dart run tool/check_hosted_deps_resolve.dart --manifest-drift-only
//   dart run tool/check_hosted_deps_resolve.dart --audit-published

import 'dart:io';

import 'hosted_deps_resolve_lib.dart';
import 'workspace_pub_constraints_sync.dart';

Future<void> main(List<String> args) async {
  final auditPublished = args.contains('--audit-published');
  final manifestDriftOnly = args.contains('--manifest-drift-only');
  final coRelease = args.contains('--co-release');
  final checkManifestDrift = args.contains('--check-manifest-drift');
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

    if (manifestDriftOnly) {
      exit(
        await runManifestDriftOnly(
          packages: packages,
          manifestByName: releaseByName,
          catalog: catalog,
        ),
      );
    }

    exit(
      await runHostedWorkspaceCheck(
        packages: packages,
        workspaceNames: workspaceNames,
        manifestByName: releaseByName,
        publishOrderPath: publishOrderPath,
        catalog: catalog,
        coRelease: coRelease,
        checkManifestDrift: checkManifestDrift,
      ),
    );
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
