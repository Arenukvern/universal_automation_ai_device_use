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
    final paths = surfaces.map((s) => s.configPath).toSet();
    expect(paths, contains('lib/src/package_version.dart'));
    expect(paths, contains('server.json'));
    expect(paths, contains('/plugin/.claude-plugin/plugin.json'));
    expect(paths, contains('/plugin/.cursor-plugin/plugin.json'));
    expect(paths, contains('/plugin/.codex-plugin/plugin.json'));
    expect(paths, contains('/plugin/.zcode-plugin/plugin.json'));
  });

  final escapeFixturesRoot =
      'tool/contracts/fixtures/toolkit_version_surfaces';

  test('escape fixture: stale semver JSON is discovered', () {
    final root = Directory(
      '${repoRoot.path}/$escapeFixturesRoot/escape_stale_json',
    );
    final surfaces = discoverToolkitVersionSurfaces(root.path);
    expect(
      surfaces.map((s) => s.configPath),
      contains('stale_manifest.json'),
    );
  });

  test('escape fixture: double-quoted version const is discovered', () {
    final root = Directory(
      '${repoRoot.path}/$escapeFixturesRoot/escape_double_quote_const',
    );
    final surfaces = discoverToolkitVersionSurfaces(root.path);
    expect(
      surfaces.map((s) => s.configPath),
      contains('lib/src/toolkit_wire_version.dart'),
    );
  });

  test('escape fixture: typed version const is discovered', () {
    final root = Directory(
      '${repoRoot.path}/$escapeFixturesRoot/escape_typed_const',
    );
    final surfaces = discoverToolkitVersionSurfaces(root.path);
    expect(
      surfaces.map((s) => s.configPath),
      contains('lib/src/toolkit_build_version.dart'),
    );
  });

  test('discovered surfaces are listed in changesets version_files', () {
    final errors = validateToolkitVersionSurfacesChangesets(repoRoot.path);
    expect(errors, isEmpty, reason: errors.join('\n'));
  });

  test('package-relative server.json is not satisfied by repo-root /server.json',
      () {
    final surface = (
      configPath: 'server.json',
      kind: 'json',
      jsonpath: r'$.version',
    );
    final wrongRoot = [(path: 'pkgs/universal_automation_toolkit/wrong.json', pattern: '{version}')];
    expect(
      versionFilesCoverSurface(wrongRoot, surface, repoRoot.path),
      isFalse,
    );
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
      (path: 'pkgs/universal_automation_toolkit/plugin.json', pattern: '{version}'),
    ];
    expect(
      versionFilesCoverSurface(wrongRoot, surface, repoRoot.path),
      isFalse,
    );
    final absWrong = absolutePathForToolkitExtraFile(
      'plugin/.cursor-plugin/plugin.json',
      repoRoot.path,
    );
    expect(
      absWrong,
      contains('pkgs/universal_automation_toolkit/plugin'),
    );
  });

  test('double-quoted version const fails validation when not in extra-files',
      () {
    final dartFile = File(
      '${toolkitPackageDir(repoRoot.path)}/lib/src/toolkit_wire_version.dart',
    );
    dartFile.parent.createSync(recursive: true);
    dartFile.writeAsStringSync(
      File(
        '${repoRoot.path}/$escapeFixturesRoot/escape_double_quote_const/'
        'pkgs/universal_automation_toolkit/lib/src/toolkit_wire_version.dart',
      ).readAsStringSync(),
    );
    addTearDown(() {
      if (dartFile.existsSync()) dartFile.deleteSync();
    });
    final errors = validateToolkitVersionSurfacesChangesets(repoRoot.path);
    expect(errors, isNotEmpty);
    expect(errors.join('\n'), contains('toolkit_wire_version.dart'));
  });

  test('typed version const fails validation when not in extra-files', () {
    final dartFile = File(
      '${toolkitPackageDir(repoRoot.path)}/lib/src/toolkit_build_version.dart',
    );
    dartFile.parent.createSync(recursive: true);
    dartFile.writeAsStringSync(
      File(
        '${repoRoot.path}/$escapeFixturesRoot/escape_typed_const/'
        'pkgs/universal_automation_toolkit/lib/src/toolkit_build_version.dart',
      ).readAsStringSync(),
    );
    addTearDown(() {
      if (dartFile.existsSync()) dartFile.deleteSync();
    });
    final errors = validateToolkitVersionSurfacesChangesets(repoRoot.path);
    expect(errors, isNotEmpty);
    expect(errors.join('\n'), contains('toolkit_build_version.dart'));
  });

  test('stale semver JSON fails validation when not in extra-files', () {
    final stale = File(
      '${toolkitPackageDir(repoRoot.path)}/stale_wire_manifest.json',
    );
    stale.writeAsStringSync('{"version":"0.4.0"}');
    addTearDown(() {
      if (stale.existsSync()) stale.deleteSync();
    });
    final errors = validateToolkitVersionSurfacesChangesets(repoRoot.path);
    expect(errors, isNotEmpty);
    expect(errors.join('\n'), contains('stale_wire_manifest.json'));
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
    final errors = validateToolkitVersionSurfacesChangesets(repoRoot.path);
    expect(errors, isNotEmpty);
    expect(errors.join('\n'), contains('mcp_manifest.json'));
  });
}