import 'dart:io';

import 'package:test/test.dart';

import 'release_please_toolkit_versions_lib.dart';
import 'workspace_pub_constraints_sync.dart';

void main() {
  late Directory repoRoot;

  setUp(() {
    repoRoot = findWorkspaceRepoRoot();
  });

  test('discovers every toolkit version surface (no hard-coded list)', () {
    final surfaces = discoverToolkitVersionSurfaces(repoRoot.path);
    expect(
      surfaces.map((s) => s.configPath).toSet(),
      {
        'lib/src/package_version.dart',
        'server.json',
        '/plugin/.claude-plugin/plugin.json',
        '/plugin/.cursor-plugin/plugin.json',
      },
    );
  });

  test('discovered surfaces are listed in release-please extra-files', () {
    final errors = validateToolkitVersionSurfacesReleasePlease(repoRoot.path);
    expect(errors, isEmpty, reason: errors.join('\n'));
  });

  test('package-relative server.json is not satisfied by repo-root /server.json',
      () {
    final surface = (
      configPath: 'server.json',
      kind: 'json',
      jsonpath: r'$.version',
    );
  final wrongRoot = [
      {'path': '/server.json', 'type': 'json', 'jsonpath': r'$.version'},
    ];
    expect(extraFilesCoverSurface(wrongRoot, surface), isFalse);
    final absWrong =
        absolutePathForToolkitExtraFile('/server.json', repoRoot.path);
    expect(File(absWrong).existsSync(), isFalse);
  });

  test('repo-root plugin paths require leading slash', () {
    final surface = (
      configPath: '/plugin/.cursor-plugin/plugin.json',
      kind: 'json',
      jsonpath: r'$.version',
    );
    final wrongRoot = [
      {
        'path': 'plugin/.cursor-plugin/plugin.json',
        'type': 'json',
        'jsonpath': r'$.version',
      },
    ];
    expect(extraFilesCoverSurface(wrongRoot, surface), isFalse);
    final absWrong = absolutePathForToolkitExtraFile(
      'plugin/.cursor-plugin/plugin.json',
      repoRoot.path,
    );
    expect(
      absWrong,
      contains('pkgs/universal_automation_toolkit/plugin'),
    );
  });

  test('stray versioned toolkit JSON fails validation', () {
    final stray = File(
      '${toolkitPackageDir(repoRoot.path)}/mcp_manifest.json',
    );
    final existed = stray.existsSync();
    final prior = existed ? stray.readAsStringSync() : null;
    final version = readToolkitPubspecVersion(repoRoot.path);
    stray.writeAsStringSync('{"version":"$version"}');
    addTearDown(() {
      if (existed) {
        stray.writeAsStringSync(prior!);
      } else if (stray.existsSync()) {
        stray.deleteSync();
      }
    });
    final errors = validateToolkitVersionSurfacesReleasePlease(repoRoot.path);
    expect(errors, isNotEmpty);
    expect(errors.join('\n'), contains('mcp_manifest.json'));
  });
}