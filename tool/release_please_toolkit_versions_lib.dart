import 'dart:convert';
import 'dart:io';

/// Repo-relative paths that must track toolkit pubspec version (see
/// `pkgs/universal_automation_toolkit/test/package_version_test.dart`).
const toolkitVersionSurfaces = <({String path, String kind, String? jsonpath})>[
  (
    path: 'lib/src/package_version.dart',
    kind: 'generic',
    jsonpath: null,
  ),
  (
    path: 'server.json',
    kind: 'json',
    jsonpath: r'$.version',
  ),
  (
    path: 'plugin/.cursor-plugin/plugin.json',
    kind: 'json',
    jsonpath: r'$.version',
  ),
  (
    path: 'plugin/.claude-plugin/plugin.json',
    kind: 'json',
    jsonpath: r'$.version',
  ),
];

String normalizeExtraFilePath(String raw) {
  var p = raw.trim();
  if (p.startsWith('/')) {
    p = p.substring(1);
  }
  return p;
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
  final toolkit = packages['pkgs/universal_automation_toolkit'] as Map<String, dynamic>?;
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
  ({String path, String kind, String? jsonpath}) surface,
) {
  for (final entry in extraFiles) {
    final path = normalizeExtraFilePath('${entry['path']}');
    if (path != normalizeExtraFilePath(surface.path)) {
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

  for (final surface in toolkitVersionSurfaces) {
    if (!extraFilesCoverSurface(extraFiles, surface)) {
      errors.add(
        'release-please-config.json: toolkit extra-files must cover '
        '${surface.path} (type: ${surface.kind}'
        '${surface.jsonpath != null ? ', jsonpath: ${surface.jsonpath}' : ''})',
      );
    }
  }

  final dartPath =
      '$repoRoot/pkgs/universal_automation_toolkit/lib/src/package_version.dart';
  final dartText = File(dartPath).readAsStringSync();
  if (!dartText.contains('x-release-please-version')) {
    errors.add(
      '$dartPath: must include x-release-please-version marker for release-please',
    );
  }

  return errors;
}