import 'dart:convert';
import 'dart:io';

/// Toolkit package key in `release-please-config.json`.
const toolkitReleasePleasePackage = 'pkgs/universal_automation_toolkit';

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

/// A versioned file Release Please must bump via toolkit `extra-files`.
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

bool _jsonTopLevelVersionMatches(File file, String version) {
  try {
    final doc = jsonDecode(file.readAsStringSync());
    if (doc is! Map) return false;
    final v = doc['version'];
    return v is String && v == version;
  } on FormatException {
    return false;
  }
}

final _dartConstString = RegExp(
  r"const\s+\w+\s*=\s*'([^']+)'\s*;",
  multiLine: true,
);

List<ToolkitVersionSurface> discoverToolkitVersionSurfaces(String repoRoot) {
  final version = readToolkitPubspecVersion(repoRoot);
  if (version == null) {
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
    if (!_jsonTopLevelVersionMatches(file, version)) continue;
    addSurface((
      configPath: absoluteToExtraFileConfigPath(file.path, repoRoot),
      kind: 'json',
      jsonpath: r'$.version',
    ));
  }

  for (final file in _jsonFilesUnder(Directory(pluginDir(repoRoot)))) {
    if (!_jsonTopLevelVersionMatches(file, version)) continue;
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
      for (final match in _dartConstString.allMatches(text)) {
        if (match.group(1) == version) {
          addSurface((
            configPath: absoluteToExtraFileConfigPath(entity.path, repoRoot),
            kind: 'generic',
            jsonpath: null,
          ));
          break;
        }
      }
    }
  }

  surfaces.sort((a, b) => a.configPath.compareTo(b.configPath));
  return surfaces;
}

/// Release Please `extra-files` entries for the toolkit package.
List<Map<String, dynamic>> loadToolkitReleasePleaseExtraFiles(String repoRoot) {
  final file = File('$repoRoot/release-please-config.json');
  if (!file.existsSync()) {
    throw StateError('missing release-please-config.json');
  }
  final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final packages = doc['packages'] as Map<String, dynamic>?;
  if (packages == null) {
    throw StateError('release-please-config.json: packages missing');
  }
  final toolkit = packages[toolkitReleasePleasePackage] as Map<String, dynamic>?;
  if (toolkit == null) {
    throw StateError('release-please-config.json: toolkit package missing');
  }
  final extra = toolkit['extra-files'];
  if (extra is! List) {
    throw StateError('release-please-config.json: toolkit extra-files missing');
  }
  return extra
      .map((e) {
        if (e is String) {
          return {'path': e, 'type': 'string'};
        }
        if (e is Map) {
          return Map<String, dynamic>.from(e);
        }
        throw StateError('invalid extra-files entry: $e');
      })
      .toList(growable: false);
}

bool extraFilesCoverSurface(
  List<Map<String, dynamic>> extraFiles,
  ToolkitVersionSurface surface,
) {
  for (final entry in extraFiles) {
    final path = canonicalExtraFileConfigPath('${entry['path']}');
    if (path != surface.configPath) {
      continue;
    }
    final type = '${entry['type'] ?? 'string'}';
    if (surface.kind == 'generic') {
      if (type == 'generic' || (type == 'string' && path.endsWith('.dart'))) {
        return true;
      }
    }
    if (surface.kind == 'json' && type == 'json') {
      if (entry['jsonpath'] == surface.jsonpath) {
        return true;
      }
    }
  }
  return false;
}

List<String> validateToolkitVersionSurfacesReleasePlease(String repoRoot) {
  final errors = <String>[];
  List<Map<String, dynamic>> extraFiles;
  try {
    extraFiles = loadToolkitReleasePleaseExtraFiles(repoRoot);
  } catch (e) {
    return ['release-please toolkit versions: $e'];
  }

  List<ToolkitVersionSurface> surfaces;
  try {
    surfaces = discoverToolkitVersionSurfaces(repoRoot);
  } catch (e) {
    return ['release-please toolkit versions: $e'];
  }

  for (final entry in extraFiles) {
    final configPath = canonicalExtraFileConfigPath('${entry['path']}');
    final abs = absolutePathForToolkitExtraFile(configPath, repoRoot);
    if (!File(abs).existsSync()) {
      errors.add(
        'release-please-config.json: toolkit extra-files path missing on disk: '
        '$configPath → $abs',
      );
    }
  }

  for (final surface in surfaces) {
    if (!extraFilesCoverSurface(extraFiles, surface)) {
      errors.add(
        'release-please-config.json: toolkit extra-files must cover '
        '${surface.configPath} (type: ${surface.kind}'
        '${surface.jsonpath != null ? ', jsonpath: ${surface.jsonpath}' : ''})',
      );
    }
  }

  final dartPath = '${toolkitPackageDir(repoRoot)}/lib/src/package_version.dart';
  final dartText = File(dartPath).readAsStringSync();
  if (!dartText.contains('x-release-please-version')) {
    errors.add(
      '$dartPath: must include x-release-please-version marker for release-please',
    );
  }

  return errors;
}