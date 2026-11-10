// Ensures workspace sibling dependencies resolve on pub.dev and that
// tool/publish_order.yaml is a valid topological publish order.
//
// Usage:
//   dart run tool/check_hosted_deps_resolve.dart --co-release
//   dart run tool/check_hosted_deps_resolve.dart --manifest-drift-only
//   dart run tool/check_hosted_deps_resolve.dart --audit-published
//   dart run tool/check_hosted_deps_resolve.dart --co-release --check-manifest-drift
//   dart run tool/check_hosted_deps_resolve.dart --co-release --check-manifest-drift --release-pr

import 'dart:io';

import 'hosted_deps_resolve_lib.dart';
import 'tool_cli.dart';
import 'workspace_pub_constraints_sync.dart';

void printUsage() {
  stdout.writeln('''
Hosted dependency resolve + release-please version policy.

Flags:
  --co-release              Co-release sibling resolution along publish_order.yaml
  --check-manifest-drift    Blocking manifest/pubspec policy (release paths)
  --release-pr              With --check-manifest-drift: on the release-please
                            branch, accept manifest == pubspec > pub.dev latest
                            not yet on pub.dev as a pending release (not an error).
                            Without this flag, manifest not on pub.dev is always
                            "claimed release never shipped".
  --manifest-drift-only     Version policy only (no co-release resolve)
  --warn-manifest-behind-pub  Downgrade manifest-behind-pub.dev to warnings
  --audit-published         Post-publish: pub.dev latest resolves + shipped-version
                            workspace constraint parity vs pub.dev archives
  --github-report           Emit workflow commands for GitHub Actions
  --release-manifest <path> Alternate release-please manifest JSON
  --publish-order <path>    Alternate publish_order.yaml
  --help                    Show this text
''');
}

const _checkFlags = {
  '--co-release',
  '--check-manifest-drift',
  '--release-pr',
  '--manifest-drift-only',
  '--warn-manifest-behind-pub',
  '--audit-published',
  '--github-report',
  '--release-manifest',
  '--publish-order',
  '--help',
  '-h',
};

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    printUsage();
    exit(0);
  }

  requireOnlyKnownFlags(
    args,
    flags: _checkFlags,
    valueFlags: {'--release-manifest', '--publish-order'},
    onUsage: printUsage,
  );

  final auditPublished = args.contains('--audit-published');
  final manifestDriftOnly = args.contains('--manifest-drift-only');
  final githubReport = args.contains('--github-report');
  final coRelease = args.contains('--co-release');
  final checkManifestDrift = args.contains('--check-manifest-drift');
  final releasePrMode = args.contains('--release-pr');
  final warnManifestBehindPub = args.contains('--warn-manifest-behind-pub');
  final manifestFlag = args.indexOf('--release-manifest');
  String? manifestPath;
  if (manifestFlag >= 0) {
    if (manifestFlag + 1 >= args.length) {
      stderr.writeln('--release-manifest requires a path');
      exit(64);
    }
    manifestPath = args[manifestFlag + 1];
  }

  if (releasePrMode && !checkManifestDrift) {
    stderr.writeln('--release-pr requires --check-manifest-drift');
    exit(64);
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
          githubReport: githubReport,
        ),
      );
    }

    if (manifestDriftOnly) {
      exit(
        await runManifestDriftOnly(
          repoRoot: repoRoot,
          packages: packages,
          manifestByName: releaseByName,
          catalog: catalog,
          githubReport: githubReport,
          warnManifestBehindPub: warnManifestBehindPub,
        ),
      );
    }

    exit(
      await runHostedWorkspaceCheck(
        repoRoot: repoRoot,
        packages: packages,
        workspaceNames: workspaceNames,
        manifestByName: releaseByName,
        publishOrderPath: publishOrderPath,
        catalog: catalog,
        coRelease: coRelease,
        checkManifestDrift: checkManifestDrift,
        releasePrMode: releasePrMode,
        warnManifestBehindPub: warnManifestBehindPub,
        githubReport: githubReport,
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
