import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

/// Toolkit package path segment under `pkgs/`.
const toolkitReleasePleasePackage = 'pkgs/universal_automation_toolkit';

/// Toolkit pubspec `name:` in `changesets.yaml` `version_files`.
const toolkitChangesetsPackageName = 'universal_automation_toolkit';

/// One `changesets.yaml` version_files entry for the toolkit package.
typedef ToolkitVersionFile = ({String path, String pattern});

/// Documented excludes for [discoverToolkitVersionSurfaces] (paths are
/// matched against repo-relative posix segments).
const toolkitVersionDiscoveryExcludeRules = <String>[
  'pubspec.yaml',
  'CHANGELOG.md',
  'CHANGELOG',
  'pubspec.lock',
  'package-lock.json',
  '.dart_tool',
  'build',
  'dist',
  'test',
  'example',
  'showcase',
  'plans',
];

/// A versioned file the release train must bump (`changesets.yaml` version_files).
typedef ToolkitVersionSurface = ({
  String configPath,
  String kind,
  String? jsonpath,
});

/// Release-please extra-files path: leading `/` is repo-root-relative;
/// otherwise the path is relative to [toolkitReleasePleasePackage].
String canonicalExtraFileConfigPath(String raw) => raw.trim();

String toolkitPackageDir(String repoRoot) =>
    '$repoRoot/$toolkitReleasePleasePackage';

String pluginDir(String repoRoot) => '$repoRoot/plugin';

/// Absolute filesystem path for a toolkit `extra-files` entry.
String absolutePathForToolkitExtraFile(String configPath, String repoRoot) {
  final p = canonicalExtraFileConfigPath(configPath);
  if (p.startsWith('/')) {
    return '$repoRoot$p';
  }
  return '${toolkitPackageDir(repoRoot)}/$p';
}

/// Config-path form of a discovered absolute file (for matching extra-files).
/// Repo-root-relative POSIX path for a discovered version surface.
String repoRelativePathForToolkitVersionSurface(
  String configPath,
  String repoRoot,
) {
  final abs = absolutePathForToolkitExtraFile(configPath, repoRoot);
  return abs.substring(repoRoot.length + 1).replaceAll(r'\', '/');
}

String absoluteToExtraFileConfigPath(String absolutePath, String repoRoot) {
  final normalized = absolutePath.replaceAll(r'\', '/');
  final toolkitRoot = '${toolkitPackageDir(repoRoot)}/';
  final pluginRoot = '${pluginDir(repoRoot)}/';
  if (normalized.startsWith(toolkitRoot)) {
    return normalized.substring(toolkitRoot.length);
  }
  if (normalized.startsWith(pluginRoot)) {
    return '/plugin/${normalized.substring(pluginRoot.length)}';
  }
  throw ArgumentError('not under toolkit or plugin/: $absolutePath');
}

bool _segmentExcluded(String posixRelative) {
  final segments = posixRelative.split('/');
  for (final rule in toolkitVersionDiscoveryExcludeRules) {
    if (segments.contains(rule)) {
      return true;
    }
    if (posixRelative == rule || posixRelative.endsWith('/$rule')) {
      return true;
    }
  }
  if (posixRelative.endsWith('.lock')) {
    return true;
  }
  return false;
}

String? readToolkitPubspecVersion(String repoRoot) {
  final pubspec = File('${toolkitPackageDir(repoRoot)}/pubspec.yaml');
  if (!pubspec.existsSync()) return null;
  final match = RegExp(r'^version:\s*(\S+)', multiLine: true)
      .firstMatch(pubspec.readAsStringSync());
  return match?.group(1);
}

Iterable<File> _jsonFilesUnder(Directory root) sync* {
  if (!root.existsSync()) return;
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.json')) continue;
    final rel = entity.path
        .substring(root.path.length + 1)
        .replaceAll(r'\', '/');
    if (_segmentExcluded(rel)) continue;
    yield entity;
  }
}

bool isToolkitVersionSemver(String value) {
  try {
    Version.parse(value);
    return true;
  } on FormatException {
    return false;
  }
}

bool jsonHasTopLevelSemverVersion(File file) {
  try {
    final doc = jsonDecode(file.readAsStringSync());
    if (doc is! Map) return false;
    final v = doc['version'];
    return v is String && isToolkitVersionSemver(v);
  } on FormatException {
    return false;
  }
}

/// Top-level or `static`/`final` const whose identifier contains `version` and value is semver.
final dartVersionConstPattern = RegExp(
  r"""(?:^|\n)\s*(?:(?:static|final)\s+)*const\s+(?:[A-Za-z_]\w*\s+)?([A-Za-z_]\w*)\s*=\s*(?:"([^"]*)"|'([^']*)')\s*;""",
  multiLine: true,
);

bool dartFileDeclaresVersionConstSurface(String source) {
  for (final match in dartVersionConstPattern.allMatches(source)) {
    final name = match.group(1)!;
    if (!name.toLowerCase().contains('version')) {
      continue;
    }
    final value = match.group(2) ?? match.group(3);
    if (value != null && isToolkitVersionSemver(value)) {
      return true;
    }
  }
  return false;
}

List<ToolkitVersionSurface> discoverToolkitVersionSurfaces(String repoRoot) {
  if (readToolkitPubspecVersion(repoRoot) == null) {
    throw StateError('could not read toolkit pubspec version');
  }
  final surfaces = <ToolkitVersionSurface>[];
  final seen = <String>{};

  void addSurface(ToolkitVersionSurface surface) {
    if (seen.add(surface.configPath)) {
      surfaces.add(surface);
    }
  }

  for (final file in _jsonFilesUnder(Directory(toolkitPackageDir(repoRoot)))) {
    if (!jsonHasTopLevelSemverVersion(file)) continue;
    addSurface((
      configPath: absoluteToExtraFileConfigPath(file.path, repoRoot),
      kind: 'json',
      jsonpath: r'$.version',
    ));
  }

  for (final file in _jsonFilesUnder(Directory(pluginDir(repoRoot)))) {
    if (!jsonHasTopLevelSemverVersion(file)) continue;
    addSurface((
      configPath: absoluteToExtraFileConfigPath(file.path, repoRoot),
      kind: 'json',
      jsonpath: r'$.version',
    ));
  }

  final libDir = Directory('${toolkitPackageDir(repoRoot)}/lib');
  if (libDir.existsSync()) {
    for (final entity in libDir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path
          .substring(libDir.path.length + 1)
          .replaceAll(r'\', '/');
      if (_segmentExcluded(rel)) continue;
      final text = entity.readAsStringSync();
      if (dartFileDeclaresVersionConstSurface(text)) {
        addSurface((
          configPath: absoluteToExtraFileConfigPath(entity.path, repoRoot),
          kind: 'generic',
          jsonpath: null,
        ));
      }
    }
  }

  surfaces.sort((a, b) => a.configPath.compareTo(b.configPath));
  return surfaces;
}

/// `changesets.yaml` version_files for [toolkitChangesetsPackageName].
List<ToolkitVersionFile> loadToolkitChangesetsVersionFiles(String repoRoot) {
  final file = File('$repoRoot/changesets.yaml');
  if (!file.existsSync()) {
    throw StateError('missing changesets.yaml');
  }
  final doc = loadYaml(file.readAsStringSync());
  if (doc is! Map) {
    throw StateError('changesets.yaml: root must be a mapping');
  }
  final versionFiles = doc['version_files'];
  if (versionFiles is! Map) {
    throw StateError('changesets.yaml: version_files missing');
  }
  final raw = versionFiles[toolkitChangesetsPackageName];
  if (raw is! List) {
    throw StateError(
      'changesets.yaml: version_files.$toolkitChangesetsPackageName missing',
    );
  }
  final out = <ToolkitVersionFile>[];
  for (final item in raw) {
    if (item is! Map) {
      throw StateError('invalid version_files entry: $item');
    }
    final path = item['path']?.toString().trim() ?? '';
    final pattern = item['pattern']?.toString() ?? '';
    if (path.isEmpty || !pattern.contains('{version}')) {
      throw StateError('invalid version_files entry: $item');
    }
    out.add((path: path, pattern: pattern));
  }
  return out;
}

bool versionFilesCoverSurface(
  List<ToolkitVersionFile> versionFiles,
  ToolkitVersionSurface surface,
  String repoRoot,
) {
  final want = repoRelativePathForToolkitVersionSurface(
    surface.configPath,
    repoRoot,
  );
  for (final entry in versionFiles) {
    final normalized = entry.path.replaceAll(r'\', '/').trim();
    if (normalized != want) {
      continue;
    }
    if (!entry.pattern.contains('{version}')) {
      continue;
    }
    if (surface.kind == 'json' && normalized.endsWith('.json')) {
      return true;
    }
    if (surface.kind == 'generic' && normalized.endsWith('.dart')) {
      return true;
    }
  }
  return false;
}

List<String> validateToolkitVersionSurfacesChangesets(String repoRoot) {
  final errors = <String>[];
  List<ToolkitVersionFile> versionFiles;
  try {
    versionFiles = loadToolkitChangesetsVersionFiles(repoRoot);
  } catch (e) {
    return ['changesets toolkit versions: $e'];
  }

  List<ToolkitVersionSurface> surfaces;
  try {
    surfaces = discoverToolkitVersionSurfaces(repoRoot);
  } catch (e) {
    return ['changesets toolkit versions: $e'];
  }

  for (final entry in versionFiles) {
    final abs = File('$repoRoot/${entry.path}');
    if (!abs.existsSync()) {
      errors.add(
        'changesets.yaml: version_files path missing on disk: '
        '${entry.path} → ${abs.path}',
      );
    }
  }

  for (final surface in surfaces) {
    if (!versionFilesCoverSurface(versionFiles, surface, repoRoot)) {
      errors.add(
        'changesets.yaml: version_files.$toolkitChangesetsPackageName must cover '
        '${surface.configPath} (kind: ${surface.kind}'
        '${surface.jsonpath != null ? ', jsonpath: ${surface.jsonpath}' : ''}); '
        'dart_changesets bumps version_files on release',
      );
    }
  }

  return errors;
}