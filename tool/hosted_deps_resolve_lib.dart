// Validates that workspace packages can resolve sibling dependencies from
// pub.dev and optional same-release versions (release-please manifest).

import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import 'workspace_pub_constraints_sync.dart';

const _pubDevPackageApi = 'https://pub.dev/api/packages';

class WorkspacePackage {
  WorkspacePackage({
    required this.name,
    required this.version,
    required this.pubspecPath,
    required this.workspaceDeps,
  });

  final String name;
  final String version;
  final String pubspecPath;
  /// Sibling workspace dependencies: name → constraint string.
  final Map<String, String> workspaceDeps;
}

/// Parses `universal_*` entries from dependencies (not dev_dependencies).
Map<String, String> parseWorkspaceDependencies(String pubspecContent) {
  final out = <String, String>{};
  var section = _PubspecSection.none;
  var sectionIndent = 0;

  for (final line in pubspecContent.split('\n')) {
    final trimmed = line.trimLeft();
  if (trimmed.startsWith('dependencies:')) {
      section = _PubspecSection.dependencies;
      sectionIndent = line.length - trimmed.length;
      continue;
    }
    if (trimmed.startsWith('dev_dependencies:') ||
        trimmed.startsWith('dependency_overrides:')) {
      section = _PubspecSection.other;
      continue;
    }

    if (section != _PubspecSection.dependencies) {
      continue;
    }
    if (trimmed.isEmpty) {
      continue;
    }
    final indent = line.length - trimmed.length;
    if (indent <= sectionIndent) {
      section = _PubspecSection.other;
      continue;
    }
    final match = RegExp(r'^([a-zA-Z0-9_]+):\s+(\S+)').firstMatch(trimmed);
    if (match == null) {
      continue;
    }
    final depName = match.group(1)!;
    if (!depName.startsWith('universal_')) {
      continue;
    }
    var constraint = match.group(2)!;
    // Strip inline comment.
    final hash = constraint.indexOf('#');
    if (hash >= 0) {
      constraint = constraint.substring(0, hash).trim();
    }
    out[depName] = constraint;
  }
  return out;
}

enum _PubspecSection { none, dependencies, other }

List<WorkspacePackage> loadWorkspacePackages(Directory repoRoot) {
  final packages = <WorkspacePackage>[];
  for (final path in workspacePubspecPaths(repoRoot)) {
    final content = File(path).readAsStringSync();
    final header = parsePubspecHeader(content);
    packages.add(
      WorkspacePackage(
        name: header.name,
        version: header.version,
        pubspecPath: path,
        workspaceDeps: parseWorkspaceDependencies(content),
      ),
    );
  }
  packages.sort((a, b) => a.name.compareTo(b.name));
  return packages;
}

/// release-please manifest: `pkgs/foo` → semver string.
Map<String, String> loadReleaseManifestVersions(
  Directory repoRoot,
  String manifestPath,
) {
  final file = File(manifestPath);
  if (!file.existsSync()) {
    return {};
  }
  final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final byName = <String, String>{};
  for (final entry in raw.entries) {
    final pkgDir = '${repoRoot.path}/${entry.key}';
    final pubspec = File('$pkgDir/pubspec.yaml');
    if (!pubspec.existsSync()) {
      continue;
    }
    final name = parsePubspecHeader(pubspec.readAsStringSync()).name;
    byName[name] = entry.value as String;
  }
  return byName;
}

/// Network/API access to pub.dev package metadata (overridable in tests).
abstract class PubDevGateway {
  Future<List<String>> versionsOnPubDev(String packageName);

  Future<Map<String, String>> latestPublishedWorkspaceDeps(String packageName);

  void close() {}
}

class PubDevCatalog implements PubDevGateway {
  PubDevCatalog({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;
  final _cache = <String, List<String>>{};

  @override
  Future<List<String>> versionsOnPubDev(String packageName) async {
    if (_cache.containsKey(packageName)) {
      return _cache[packageName]!;
    }
    final uri = Uri.parse('$_pubDevPackageApi/$packageName');
    final request = await _client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException(
        'pub.dev ${response.statusCode} for $packageName',
        uri: uri,
      );
    }
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final versions = (decoded['versions'] as List<dynamic>)
        .map((v) => (v as Map<String, dynamic>)['version'] as String)
        .toList();
    _cache[packageName] = versions;
    return versions;
  }

  @override
  Future<Map<String, String>> latestPublishedWorkspaceDeps(
    String packageName,
  ) async {
    final uri = Uri.parse('$_pubDevPackageApi/$packageName');
    final request = await _client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode == 404) {
      return {};
    }
    if (response.statusCode != 200) {
      throw HttpException(
        'pub.dev ${response.statusCode} for $packageName',
        uri: uri,
      );
    }
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final latest = decoded['latest'] as Map<String, dynamic>;
    final pubspec = latest['pubspec'] as Map<String, dynamic>;
    final deps = pubspec['dependencies'] as Map<String, dynamic>? ?? {};
    final out = <String, String>{};
    for (final entry in deps.entries) {
      if (entry.key.startsWith('universal_')) {
        out[entry.key] = entry.value.toString();
      }
    }
    return out;
  }

  @override
  void close() => _client.close(force: true);
}

bool constraintSatisfiedByAnyVersion(
  String constraintText,
  Iterable<String> versions,
) {
  final constraint = VersionConstraint.parse(constraintText);
  for (final v in versions) {
    if (constraint.allows(Version.parse(v))) {
      return true;
    }
  }
  return false;
}

List<String> resolveErrors({
  required List<WorkspacePackage> packages,
  required Set<String> workspaceNames,
  required Map<String, List<String>> pubDevVersions,
  required Map<String, String> releaseManifestByName,
}) {
  final errors = <String>[];

  for (final pkg in packages) {
    for (final entry in pkg.workspaceDeps.entries) {
      final depName = entry.key;
      if (!workspaceNames.contains(depName)) {
        continue;
      }
      final constraint = entry.value;
      final available = <String>{...?pubDevVersions[depName]};
      final manifestVersion = releaseManifestByName[depName];
      if (manifestVersion != null) {
        available.add(manifestVersion);
      }
      if (!constraintSatisfiedByAnyVersion(constraint, available)) {
        errors.add(
          '${pkg.name}@${pkg.version} requires $depName $constraint '
          '(pub.dev: ${pubDevVersions[depName]?.join(', ') ?? 'none'}'
          '${manifestVersion != null ? '; manifest: $manifestVersion' : ''})',
        );
      }
    }
  }
  return errors;
}

/// Resolves sibling deps as if packages publish in [publishOrder] sequence.
/// A manifest version counts only for dependencies listed **before** the
/// dependent in [publishOrder] (same-release train, topological apply).
List<String> resolveErrorsAlongPublishOrder({
  required List<WorkspacePackage> packages,
  required Set<String> workspaceNames,
  required Map<String, List<String>> pubDevVersions,
  required Map<String, String> releaseManifestByName,
  required List<String> publishOrder,
}) {
  final errors = <String>[];
  final byName = {for (final p in packages) p.name: p};
  final indexOf = <String, int>{};
  for (var i = 0; i < publishOrder.length; i++) {
    indexOf[publishOrder[i]] = i;
  }

  for (final pkgName in publishOrder) {
    final pkg = byName[pkgName];
    if (pkg == null) {
      continue;
    }
    final pkgIdx = indexOf[pkgName]!;
    for (final entry in pkg.workspaceDeps.entries) {
      final depName = entry.key;
      if (!workspaceNames.contains(depName)) {
        continue;
      }
      final depIdx = indexOf[depName];
      if (depIdx == null) {
        errors.add(
          '${pkg.name}@${pkg.version} depends on $depName but $depName '
          'is missing from publish_order.yaml',
        );
        continue;
      }
      final constraint = entry.value;
      final available = <String>{...?pubDevVersions[depName]};
      if (depIdx < pkgIdx) {
        final manifestVersion = releaseManifestByName[depName];
        if (manifestVersion != null) {
          available.add(manifestVersion);
        }
      }
      if (!constraintSatisfiedByAnyVersion(constraint, available)) {
        errors.add(
          '${pkg.name}@${pkg.version} requires $depName $constraint when '
          'published at publish-order index $pkgIdx '
          '(pub.dev: ${pubDevVersions[depName]?.join(', ') ?? 'none'}'
          '${depIdx < pkgIdx && releaseManifestByName[depName] != null ? '; co-release from index $depIdx: ${releaseManifestByName[depName]}' : ''})',
        );
      }
    }
  }

  for (final pkg in packages) {
    if (!indexOf.containsKey(pkg.name)) {
      errors.add(
        'publish order missing workspace package ${pkg.name} '
        '(required for batch release check)',
      );
    }
  }

  return errors;
}

/// Checks pub.dev **latest** tarball pubspecs for unresolved sibling deps.
List<String> auditPublishedLatestErrors({
  required List<WorkspacePackage> packages,
  required Set<String> workspaceNames,
  required Map<String, List<String>> pubDevVersions,
  required Map<String, Map<String, String>> publishedLatestDeps,
}) {
  final errors = <String>[];
  for (final pkg in packages) {
    final versions = pubDevVersions[pkg.name];
    if (versions == null || versions.isEmpty) {
      continue;
    }
    final latest = _maxVersion(versions);
    final deps = publishedLatestDeps[pkg.name];
    if (deps == null) {
      continue;
    }
    for (final entry in deps.entries) {
      if (!workspaceNames.contains(entry.key)) {
        continue;
      }
      final available = pubDevVersions[entry.key] ?? [];
      if (!constraintSatisfiedByAnyVersion(entry.value, available)) {
        errors.add(
          'pub.dev ${pkg.name}@$latest requires ${entry.key} ${entry.value} '
          '(pub.dev has: ${available.join(', ')})',
        );
      }
    }
  }
  return errors;
}

String _maxVersion(List<String> versions) {
  return versions.reduce(
    (a, b) => Version.parse(a) > Version.parse(b) ? a : b,
  );
}

/// Builds directed edges: dependency must publish before dependent.
Map<String, Set<String>> workspaceDependencyGraph(
  List<WorkspacePackage> packages,
) {
  final names = packages.map((p) => p.name).toSet();
  final graph = <String, Set<String>>{};
  for (final name in names) {
    graph[name] = {};
  }
  for (final pkg in packages) {
    for (final dep in pkg.workspaceDeps.keys) {
      if (names.contains(dep)) {
        graph[dep]!.add(pkg.name);
      }
    }
  }
  return graph;
}

List<String> topologicalPublishOrder(Map<String, Set<String>> graph) {
  final inDegree = <String, int>{};
  for (final node in graph.keys) {
    inDegree[node] = 0;
  }
  for (final targets in graph.values) {
    for (final t in targets) {
      inDegree[t] = (inDegree[t] ?? 0) + 1;
    }
  }

  final ready = graph.keys.where((n) => inDegree[n] == 0).toList()..sort();
  final order = <String>[];

  while (ready.isNotEmpty) {
    final node = ready.removeAt(0);
    order.add(node);
    for (final dependent in graph[node]!) {
      inDegree[dependent] = inDegree[dependent]! - 1;
      if (inDegree[dependent] == 0) {
        ready.add(dependent);
        ready.sort();
      }
    }
  }

  if (order.length != graph.length) {
  throw StateError('Workspace dependency graph has a cycle');
  }
  return order;
}

List<String> validatePublishOrderList(
  List<String> configuredOrder,
  Map<String, Set<String>> graph,
) {
  final errors = <String>[];
  final index = <String, int>{};
  for (var i = 0; i < configuredOrder.length; i++) {
    index[configuredOrder[i]] = i;
  }
  for (final dep in graph.keys) {
    final depIndex = index[dep];
    if (depIndex == null) {
      errors.add('publish order missing package $dep');
      continue;
    }
    for (final dependent in graph[dep]!) {
      final depIdx = index[dependent];
      if (depIdx == null) {
        errors.add('publish order missing package $dependent');
        continue;
      }
      if (depIndex >= depIdx) {
        errors.add(
          'publish order violates dependency: $dep must come before $dependent',
        );
      }
    }
  }
  return errors;
}

List<String> loadPublishOrderYaml(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('Missing publish order file: $path');
  }
  final lines = file.readAsLinesSync();
  final order = <String>[];
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    if (trimmed.startsWith('- ')) {
      order.add(trimmed.substring(2).trim());
    } else {
      order.add(trimmed);
    }
  }
  return order;
}

Future<Map<String, List<String>>> fetchAllPubDevVersions(
  PubDevGateway catalog,
  Set<String> packageNames,
) async {
  final out = <String, List<String>>{};
  for (final name in packageNames) {
    out[name] = await catalog.versionsOnPubDev(name);
  }
  return out;
}

/// Runs [--audit-published]: exits the process on fetch/parse failures (fail closed).
Future<int> runAuditPublished({
  required List<WorkspacePackage> packages,
  required Set<String> workspaceNames,
  required PubDevGateway catalog,
}) async {
  try {
    final pubVersions = await fetchAllPubDevVersions(catalog, workspaceNames);
    final latestDeps = <String, Map<String, String>>{};
    for (final name in workspaceNames) {
      try {
        latestDeps[name] = await catalog.latestPublishedWorkspaceDeps(name);
      } on HttpException catch (e) {
        stderr.writeln(
          'pub.dev audit failed: could not read latest pubspec for $name: $e',
        );
        return 1;
      } on SocketException catch (e) {
        stderr.writeln(
          'pub.dev audit failed: network error reading $name: $e',
        );
        return 1;
      }
    }
    final errors = auditPublishedLatestErrors(
      packages: packages,
      workspaceNames: workspaceNames,
      pubDevVersions: pubVersions,
      publishedLatestDeps: latestDeps,
    );
    if (errors.isEmpty) {
      stdout.writeln('All pub.dev latest packages resolve sibling deps.');
      return 0;
    }
    stderr.writeln('pub.dev hosted dependency audit failed:\n');
    for (final e in errors) {
      stderr.writeln('  - $e');
    }
    return 1;
  } on HttpException catch (e) {
    stderr.writeln('pub.dev audit failed: HTTP error from pub.dev: $e');
    return 1;
  } on SocketException catch (e) {
    stderr.writeln('pub.dev audit failed: could not reach pub.dev: $e');
    return 1;
  } on IOException catch (e) {
    stderr.writeln('pub.dev audit failed: I/O error talking to pub.dev: $e');
    return 1;
  } on FormatException catch (e) {
    stderr.writeln('pub.dev audit failed: invalid JSON from pub.dev: $e');
    return 1;
  }
}
