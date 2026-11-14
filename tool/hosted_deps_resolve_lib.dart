// Validates that workspace packages can resolve sibling dependencies from
// pub.dev and optional same-release versions (release-please manifest).

import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import 'tag_pubspec_provenance_lib.dart';
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

  /// `universal_*` dependency constraints from the pub.dev version archive API.
  Future<Map<String, String>> publishedWorkspaceDepsAtVersion(
    String packageName,
    String version,
  );

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
  Future<Map<String, String>> publishedWorkspaceDepsAtVersion(
    String packageName,
    String version,
  ) async {
    final uri = Uri.parse('$_pubDevPackageApi/$packageName/versions/$version');
    final request = await _client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    if (response.statusCode == 404) {
      return {};
    }
    if (response.statusCode != 200) {
      throw HttpException(
        'pub.dev ${response.statusCode} for $packageName@$version',
        uri: uri,
      );
    }
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final pubspec = decoded['pubspec'] as Map<String, dynamic>;
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
  void clearVersionCache([String? packageName]) {
    if (packageName == null) {
      _cache.clear();
    } else {
      _cache.remove(packageName);
    }
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

/// Human-readable rule printed when co-release checking is enabled.
const releaseSetRuleText = '''
Release set rule (co-release mode only):
  A workspace package version may satisfy a sibling constraint (in addition to
  pub.dev) only when ALL are true:
    1. The package is in the computed release set for this run.
    2. Its pubspec version is strictly greater than pub.dev latest.
    3. Its pubspec version is not already on pub.dev.
    4. It appears earlier than the dependent in tool/publish_order.yaml.
  On validate / co-release CI, --co-release enables this set so main answers
  "releasable in publish_order.yaml order?".
  Without --co-release, the release set is empty (pub.dev only).
''';

/// Sibling dependency errors for one package using pub.dev versions only.
List<String> siblingDepErrorsPubDevOnly({
  required WorkspacePackage pkg,
  required Set<String> workspaceNames,
  required Map<String, List<String>> pubDevVersions,
}) {
  return siblingDepErrorsAtPublishStep(
    pkg: pkg,
    workspaceNames: workspaceNames,
    pubDevVersions: pubDevVersions,
    byName: const {},
    releaseSet: const {},
    publishOrder: const [],
    simulateCoReleaseTrain: false,
  );
}

/// Per-package sibling check before `dart pub publish`.
///
/// With [simulateCoReleaseTrain], release-set siblings listed **before** [pkg]
/// in [publishOrder] count at their pending pubspec version (dry-run train).
/// Without it, only pub.dev versions count (real `--publish`).
List<String> siblingDepErrorsAtPublishStep({
  required WorkspacePackage pkg,
  required Set<String> workspaceNames,
  required Map<String, List<String>> pubDevVersions,
  required Map<String, WorkspacePackage> byName,
  required Set<String> releaseSet,
  required List<String> publishOrder,
  required bool simulateCoReleaseTrain,
}) {
  final errors = <String>[];
  final indexOf = <String, int>{};
  for (var i = 0; i < publishOrder.length; i++) {
    indexOf[publishOrder[i]] = i;
  }
  final pkgIdx = indexOf[pkg.name];
  if (pkgIdx == null && simulateCoReleaseTrain) {
    errors.add(
      '${pkg.name} is missing from publish_order.yaml (required for train simulation)',
    );
    return errors;
  }

  for (final entry in pkg.workspaceDeps.entries) {
    final depName = entry.key;
    if (!workspaceNames.contains(depName)) {
      continue;
    }
    final available = <String>{...?pubDevVersions[depName]};
    if (simulateCoReleaseTrain && pkgIdx != null) {
      final depIdx = indexOf[depName];
      final depPkg = byName[depName];
      if (depIdx != null &&
          depIdx < pkgIdx &&
          releaseSet.contains(depName) &&
          depPkg != null) {
        available.add(depPkg.version);
      }
    }
    if (!constraintSatisfiedByAnyVersion(entry.value, available)) {
      errors.add(
        '${pkg.name}@${pkg.version} requires $depName ${entry.value} '
        '(pub.dev has: ${(pubDevVersions[depName] ?? []).join(', ')})',
      );
    }
  }
  return errors;
}

/// Writes [errors] to `$GITHUB_STEP_SUMMARY` and one `::warning` per line.
void emitGithubCiReport({required String title, required List<String> errors}) {
  if (errors.isEmpty) {
    return;
  }
  for (final error in errors) {
    final message = error.replaceAll('%', '%25').replaceAll('\r', '').replaceAll('\n', ' ');
    stderr.writeln('::warning title=$title::$message');
  }
  final summaryPath = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summaryPath == null || summaryPath.isEmpty) {
    return;
  }
  final buffer = StringBuffer('### $title\n\n');
  for (final error in errors) {
    buffer.writeln('- $error');
  }
  buffer.writeln();
  File(summaryPath).writeAsStringSync(buffer.toString(), mode: FileMode.append);
}

/// Waits until exact [version] appears in pub.dev package versions (fail closed).
Future<void> waitForVersionOnPubDev({
  required PubDevGateway catalog,
  required String packageName,
  required String version,
  Duration timeout = const Duration(minutes: 5),
  Duration initialPollInterval = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  var backoff = initialPollInterval;
  var polls = 0;
  final apiUrl = '$_pubDevPackageApi/$packageName';

  while (DateTime.now().isBefore(deadline)) {
    polls++;
    if (catalog is PubDevCatalog) {
      catalog.clearVersionCache(packageName);
    }
    final versions = await catalog.versionsOnPubDev(packageName);
    if (versions.contains(version)) {
      stdout.writeln(
        'pub.dev API lists exact version $packageName@$version '
        '(poll $polls)',
      );
      return;
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      break;
    }
    stdout.writeln(
      'Waiting for exact $packageName@$version in $apiUrl versions '
      '(poll $polls; have: ${versions.join(', ')})…',
    );
    final sleep = remaining < backoff ? remaining : backoff;
    await Future<void>.delayed(sleep);
    final nextMs = (backoff.inMilliseconds * 1.5).round();
    backoff = Duration(
      milliseconds: nextMs.clamp(2000, 30000),
    );
  }

  throw StateError(
    'pub.dev visibility timeout: $packageName@$version never appeared in '
    '$apiUrl versions list within ${timeout.inSeconds}s ($polls polls). '
    'Do not publish dependents until this version is visible.',
  );
}

/// Packages scheduled to publish in this run (--co-release only).
Set<String> computeReleaseSet({
  required List<WorkspacePackage> packages,
  required Map<String, List<String>> pubDevVersions,
  required bool coReleaseEnabled,
}) {
  if (!coReleaseEnabled) {
    return {};
  }
  final releaseSet = <String>{};
  for (final pkg in packages) {
    final pubListed = pubDevVersions[pkg.name] ?? [];
    final workspaceVersion = Version.parse(pkg.version);
    if (pubListed.contains(pkg.version)) {
      continue;
    }
    if (pubListed.isEmpty) {
      releaseSet.add(pkg.name);
      continue;
    }
    final pubLatest = Version.parse(_maxVersion(pubListed));
    if (workspaceVersion > pubLatest) {
      releaseSet.add(pkg.name);
    }
  }
  return releaseSet;
}

/// Version / manifest policy outcome (errors block; warnings do not).
class VersionPolicyResult {
  VersionPolicyResult({required this.errors, required this.warnings});

  final List<String> errors;
  final List<String> warnings;
}

/// `null` = no release tag; `true` = changes since tag; `false` = unchanged.
typedef GitChangesSinceReleaseTag = Future<bool?> Function(
  Directory repoRoot,
  WorkspacePackage pkg,
);

Future<bool?> defaultGitChangesSinceReleaseTag(
  Directory repoRoot,
  WorkspacePackage pkg,
) async {
  final tag = '${pkg.name}-v${pkg.version}';
  final verify = await Process.run(
    'git',
    ['rev-parse', '--verify', 'refs/tags/$tag'],
    workingDirectory: repoRoot.path,
  );
  if (verify.exitCode != 0) {
    return null;
  }
  final pkgDir = File(pkg.pubspecPath).parent;
  final relDir = pkgDir.path.startsWith('${repoRoot.path}/')
      ? pkgDir.path.substring(repoRoot.path.length + 1)
      : pkgDir.path;
  final diff = await Process.run(
    'git',
    ['diff', '--quiet', tag, '--', relDir],
    workingDirectory: repoRoot.path,
  );
  if (diff.exitCode == 0) {
    return false;
  }
  if (diff.exitCode == 1) {
    return true;
  }
  return null;
}

/// Workspace version policy (supersedes legacy manifest-drift-only rules).
///
/// Manifest = last **released** version; pubspec may be ahead without error.
Future<VersionPolicyResult> evaluateVersionPolicy({
  required Directory repoRoot,
  required List<WorkspacePackage> packages,
  required Map<String, String> manifestByName,
  required Map<String, List<String>> pubDevVersions,
  required Set<String> releaseSet,
  bool warnManifestBehindPub = false,
  /// Tag-reuse since release only when `--check-manifest-drift` (not on PRs).
  bool enableTagReuseCheck = false,
  /// Release-please release branch: manifest may equal unreleased pubspec ahead
  /// of pub.dev (`--release-pr` with `--check-manifest-drift`).
  bool releasePrMode = false,
  GitChangesSinceReleaseTag? gitChangesSinceTag,
}) async {
  final gitCheck = gitChangesSinceTag ?? defaultGitChangesSinceReleaseTag;
  final errors = <String>[];
  final warnings = <String>[];

  void addManifestIssue(String msg) {
    if (warnManifestBehindPub) {
      warnings.add(msg);
    } else {
      errors.add(msg);
    }
  }

  for (final pkg in packages) {
    final pubListed = pubDevVersions[pkg.name] ?? [];
    if (pubListed.isEmpty) {
      continue;
    }
    final pubLatestStr = _maxVersion(pubListed);
    final pubLatest = Version.parse(pubLatestStr);
    final pubspecVersion = Version.parse(pkg.version);

    if (pubspecVersion < pubLatest) {
      errors.add(
        '${pkg.name}: pubspec ${pkg.version} is lower than pub.dev latest '
        '$pubLatestStr',
      );
    }

    final manifestVersion = manifestByName[pkg.name];
    if (manifestVersion != null) {
      final manifestParsed = Version.parse(manifestVersion);
      if (manifestParsed < pubLatest) {
        addManifestIssue(
          '${pkg.name}: manifest $manifestVersion is lower than pub.dev '
          'latest $pubLatestStr (last-released marker behind reality)',
        );
      }
      if (!pubListed.contains(manifestVersion)) {
        final pendingReleasePr = releasePrMode &&
            manifestParsed == pubspecVersion &&
            manifestParsed > pubLatest;
        if (!pendingReleasePr) {
          addManifestIssue(
            '${pkg.name}: manifest $manifestVersion is not on pub.dev (claimed '
            'release never shipped)',
          );
        }
      }
    }

    if (pubListed.contains(pkg.version) && pkg.version != pubLatestStr) {
      errors.add(
        '${pkg.name}: pubspec ${pkg.version} is on pub.dev but is not the '
        'latest ($pubLatestStr) — version reuse',
      );
    }

    if (pubspecVersion == pubLatest &&
        enableTagReuseCheck &&
        releaseSet.contains(pkg.name)) {
      final changed = await gitCheck(repoRoot, pkg);
      if (changed == true) {
        errors.add(
          '${pkg.name}: pubspec ${pkg.version} matches pub.dev latest but the '
          'package changed since tag ${pkg.name}-v${pkg.version} — version reuse',
        );
      } else if (changed == null) {
        warnings.add(
          '${pkg.name}: pubspec ${pkg.version} matches pub.dev latest; no git tag '
          '${pkg.name}-v${pkg.version} to verify unchanged (OK with warning)',
        );
      }
    }

    if (releaseSet.contains(pkg.name) && pubListed.contains(pkg.version)) {
      errors.add(
        '${pkg.name}: pubspec ${pkg.version} is already on pub.dev but package '
        'is pending release',
      );
    }
  }

  return VersionPolicyResult(errors: errors, warnings: warnings);
}

/// Back-compat wrapper (strict; no manifest-behind downgrade).
Future<VersionPolicyResult> evaluateVersionPolicyStrict({
  required Directory repoRoot,
  required List<WorkspacePackage> packages,
  required Map<String, String> manifestByName,
  required Map<String, List<String>> pubDevVersions,
  required Set<String> releaseSet,
}) {
  return evaluateVersionPolicy(
    repoRoot: repoRoot,
    packages: packages,
    manifestByName: manifestByName,
    pubDevVersions: pubDevVersions,
    releaseSet: releaseSet,
    warnManifestBehindPub: false,
  );
}

Directory packageDirectory(WorkspacePackage pkg) {
  return File(pkg.pubspecPath).parent;
}

/// Resolves sibling deps as if packages publish in [publishOrder] sequence.
/// Co-release versions count only for dependencies in [releaseSet] listed
/// **before** the dependent in [publishOrder].
List<String> resolveErrorsAlongPublishOrder({
  required List<WorkspacePackage> packages,
  required Set<String> workspaceNames,
  required Map<String, List<String>> pubDevVersions,
  required Set<String> releaseSet,
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
      final depPkg = byName[depName];
      if (depIdx < pkgIdx &&
          releaseSet.contains(depName) &&
          depPkg != null) {
        available.add(depPkg.version);
      }
      if (!constraintSatisfiedByAnyVersion(constraint, available)) {
        errors.add(
          '${pkg.name}@${pkg.version} requires $depName $constraint when '
          'published at publish-order index $pkgIdx '
          '(pub.dev: ${pubDevVersions[depName]?.join(', ') ?? 'none'}'
          '${releaseSet.contains(depName) && depIdx < pkgIdx ? '; co-release: ${depPkg?.version}' : ''})',
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

/// Outcome of checking pub.dev **latest** tarball sibling constraints.
class AuditPublishedLatestFindings {
  AuditPublishedLatestFindings({
    required this.errors,
    required this.warnings,
  });

  final List<String> errors;
  final List<String> warnings;
}

/// Checks pub.dev **latest** tarball pubspecs for unresolved sibling deps.
///
/// On a release-please PR ([releasePrMode]), pub.dev-latest drift becomes a
/// warning only when the workspace in-train [entry.key] version satisfies the
/// failing constraint (fix-forward). If in-train does not satisfy, stay error.
AuditPublishedLatestFindings auditPublishedLatestErrors({
  required List<WorkspacePackage> packages,
  required Set<String> workspaceNames,
  required Map<String, List<String>> pubDevVersions,
  required Map<String, Map<String, String>> publishedLatestDeps,
  Set<String> releaseSet = const {},
  bool releasePrMode = false,
}) {
  final errors = <String>[];
  final warnings = <String>[];
  final byName = {for (final p in packages) p.name: p};

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
      final available = List<String>.from(pubDevVersions[entry.key] ?? const []);
      if (releaseSet.contains(entry.key)) {
        final inTrain = byName[entry.key]?.version;
        if (inTrain != null && !available.contains(inTrain)) {
          available.add(inTrain);
        }
      }
      if (!constraintSatisfiedByAnyVersion(entry.value, available)) {
        final msg =
            'pub.dev ${pkg.name}@$latest requires ${entry.key} ${entry.value} '
            '(pub.dev has: ${(pubDevVersions[entry.key] ?? []).join(', ')}'
            '${releaseSet.contains(entry.key) ? '; in-train: ${byName[entry.key]?.version}' : ''})';
        final inTrainVer = byName[entry.key]?.version;
        final inTrainSatisfies = inTrainVer != null &&
            constraintSatisfiedByAnyVersion(entry.value, [inTrainVer]);
        final pendingFix = releasePrMode &&
            (releaseSet.contains(pkg.name) || releaseSet.contains(entry.key));
        if (pendingFix && inTrainSatisfies) {
          warnings.add('PENDING RELEASE (pub.dev latest drift): $msg');
        } else {
          errors.add(msg);
        }
      }
    }
  }
  return AuditPublishedLatestFindings(errors: errors, warnings: warnings);
}

String publishedDepsAtVersionKey(String packageName, String version) =>
    '$packageName@$version';

/// For packages whose **pubspec version is already on pub.dev**, workspace
/// `universal_*` constraints must match that exact published tarball (not
/// merely "resolve" against pub.dev). Pending packages in [releaseSet] are
/// skipped (same exemption as version reuse under `--release-pr`).
List<String> publishedExactVersionWorkspaceConstraintDriftErrors({
  required List<WorkspacePackage> packages,
  required Map<String, List<String>> pubDevVersions,
  required Set<String> releaseSet,
  required Map<String, Map<String, String>> publishedDepsAtExactVersion,
}) {
  final errors = <String>[];
  for (final pkg in packages) {
    final pubListed = pubDevVersions[pkg.name] ?? [];
    if (!pubListed.contains(pkg.version)) {
      continue;
    }
    if (releaseSet.contains(pkg.name)) {
      continue;
    }
    final key = publishedDepsAtVersionKey(pkg.name, pkg.version);
    final published = publishedDepsAtExactVersion[key];
    if (published == null) {
      errors.add(
        '${pkg.name}@${pkg.version}: missing pub.dev metadata for shipped '
        'version (cannot verify workspace constraints)',
      );
      continue;
    }
    final allKeys = {
      ...pkg.workspaceDeps.keys,
      ...published.keys,
    };
    for (final depName in allKeys) {
      final local = pkg.workspaceDeps[depName];
      final remote = published[depName];
      if (local == remote) {
        continue;
      }
      errors.add(
        '${pkg.name}@${pkg.version}: workspace $depName constraint '
        '${local ?? '(missing)'} differs from pub.dev ${pkg.version} '
        '(${remote ?? '(missing)'}). '
        'Land a fix(${pkg.name}) commit so release-please bumps it and you can publish a new version.',
      );
    }
  }
  return errors;
}

Future<Map<String, Map<String, String>>>
fetchPublishedWorkspaceDepsForShippedPubspecVersions({
  required List<WorkspacePackage> packages,
  required Map<String, List<String>> pubDevVersions,
  required PubDevGateway catalog,
}) async {
  final out = <String, Map<String, String>>{};
  for (final pkg in packages) {
    final pubListed = pubDevVersions[pkg.name] ?? [];
    if (!pubListed.contains(pkg.version)) {
      continue;
    }
    final key = publishedDepsAtVersionKey(pkg.name, pkg.version);
    out[key] = await catalog.publishedWorkspaceDepsAtVersion(
      pkg.name,
      pkg.version,
    );
  }
  return out;
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

/// Default workspace hosted-deps + publish-order check.
Future<int> runHostedWorkspaceCheck({
  required Directory repoRoot,
  required List<WorkspacePackage> packages,
  required Set<String> workspaceNames,
  required Map<String, String> manifestByName,
  required String publishOrderPath,
  required PubDevGateway catalog,
  required bool coRelease,
  required bool checkManifestDrift,
  bool releasePrMode = false,
  bool warnManifestBehindPub = false,
  bool githubReport = false,
}) async {
  try {
    final graph = workspaceDependencyGraph(packages);
    final computedOrder = topologicalPublishOrder(graph);
    stdout.writeln('Computed topological publish order:');
    for (final name in computedOrder) {
      stdout.writeln('  - $name');
    }

    final configuredOrder = loadPublishOrderYaml(publishOrderPath);
    final orderErrors = validatePublishOrderList(configuredOrder, graph);

    final pubVersions = await fetchAllPubDevVersions(catalog, workspaceNames);
    final releaseSet = computeReleaseSet(
      packages: packages,
      pubDevVersions: pubVersions,
      coReleaseEnabled: coRelease,
    );

    if (coRelease) {
      stdout.writeln(releaseSetRuleText);
      stdout.writeln('Release set (${releaseSet.length} packages):');
      for (final name in configuredOrder) {
        if (releaseSet.contains(name)) {
          final pkg = packages.firstWhere((p) => p.name == name);
          stdout.writeln('  - $name@${pkg.version}');
        }
      }
    } else {
      stdout.writeln(
        'Co-release disabled: release set is empty (pub.dev only).',
      );
    }

    final runVersionPolicy = coRelease || checkManifestDrift;
    VersionPolicyResult? policy;
    if (runVersionPolicy) {
      policy = await evaluateVersionPolicy(
        repoRoot: repoRoot,
        packages: packages,
        manifestByName: manifestByName,
        pubDevVersions: pubVersions,
        releaseSet: releaseSet,
        warnManifestBehindPub:
            warnManifestBehindPub && !checkManifestDrift,
        enableTagReuseCheck: checkManifestDrift,
        releasePrMode: releasePrMode,
      );
    }

    final dependencyErrors = coRelease
        ? resolveErrorsAlongPublishOrder(
      packages: packages,
      workspaceNames: workspaceNames,
      pubDevVersions: pubVersions,
      releaseSet: releaseSet,
      publishOrder: configuredOrder,
        )
        : <String>[];

    List<String> publishedConstraintErrors = [];
    if (checkManifestDrift) {
      final publishedAtVersion =
          await fetchPublishedWorkspaceDepsForShippedPubspecVersions(
        packages: packages,
        pubDevVersions: pubVersions,
        catalog: catalog,
      );
      publishedConstraintErrors =
          publishedExactVersionWorkspaceConstraintDriftErrors(
        packages: packages,
        pubDevVersions: pubVersions,
        releaseSet: releaseSet,
        publishedDepsAtExactVersion: publishedAtVersion,
      );
    }

    if (policy != null && policy.warnings.isNotEmpty) {
      stderr.writeln('Version policy warnings:\n');
      for (final w in policy.warnings) {
        stderr.writeln('  - $w');
      }
      if (githubReport) {
        emitGithubCiReport(title: 'Version policy warning', errors: policy.warnings);
      }
    }
    if (policy != null && policy.errors.isNotEmpty) {
      stderr.writeln('Version policy errors:\n');
      for (final e in policy.errors) {
        stderr.writeln('  - $e');
      }
      if (githubReport) {
        emitGithubCiReport(title: 'Version policy', errors: policy.errors);
      }
    }
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
    if (publishedConstraintErrors.isNotEmpty) {
      stderr.writeln(
        'Published exact-version workspace constraint drift:\n',
      );
      for (final e in publishedConstraintErrors) {
        stderr.writeln('  - $e');
      }
      if (githubReport) {
        emitGithubCiReport(
          title: 'Published constraint drift',
          errors: publishedConstraintErrors,
        );
      }
    }

    if ((policy?.errors.isNotEmpty ?? false) ||
        dependencyErrors.isNotEmpty ||
        publishedConstraintErrors.isNotEmpty ||
        orderErrors.isNotEmpty) {
      return 1;
    }

    stdout.writeln(
      'Workspace sibling dependencies resolve along publish_order.yaml.',
    );
    stdout.writeln('Publish order file is a valid topological order.');
    return 0;
  } on HttpException catch (e) {
    stderr.writeln('Hosted dependency check failed: HTTP error from pub.dev: $e');
    return 1;
  } on SocketException catch (e) {
    stderr.writeln('Hosted dependency check failed: could not reach pub.dev: $e');
    return 1;
  } on IOException catch (e) {
    stderr.writeln('Hosted dependency check failed: I/O error talking to pub.dev: $e');
    return 1;
  } on StateError catch (e) {
    stderr.writeln('Publish order check failed: ${e.message}');
    return 1;
  }
}

/// Manifest / pubspec drift only (--manifest-drift-only).
Future<int> runManifestDriftOnly({
  required Directory repoRoot,
  required List<WorkspacePackage> packages,
  required Map<String, String> manifestByName,
  required PubDevGateway catalog,
  bool githubReport = false,
  bool warnManifestBehindPub = false,
}) async {
  try {
    final workspaceNames = packages.map((p) => p.name).toSet();
    final pubVersions = await fetchAllPubDevVersions(catalog, workspaceNames);
    final releaseSet = computeReleaseSet(
      packages: packages,
      pubDevVersions: pubVersions,
      coReleaseEnabled: true,
    );
    final policy = await evaluateVersionPolicy(
      repoRoot: repoRoot,
      packages: packages,
      manifestByName: manifestByName,
      pubDevVersions: pubVersions,
      releaseSet: releaseSet,
      warnManifestBehindPub: warnManifestBehindPub,
      enableTagReuseCheck: false,
    );
    if (policy.warnings.isNotEmpty) {
      stderr.writeln('Version policy warnings:\n');
      for (final w in policy.warnings) {
        stderr.writeln('  - $w');
      }
      if (githubReport) {
        emitGithubCiReport(title: 'Version policy warning', errors: policy.warnings);
      }
    }
    final publishedAtVersion =
        await fetchPublishedWorkspaceDepsForShippedPubspecVersions(
      packages: packages,
      pubDevVersions: pubVersions,
      catalog: catalog,
    );
    final publishedConstraintErrors =
        publishedExactVersionWorkspaceConstraintDriftErrors(
      packages: packages,
      pubDevVersions: pubVersions,
      releaseSet: releaseSet,
      publishedDepsAtExactVersion: publishedAtVersion,
    );

    if (policy.errors.isEmpty && publishedConstraintErrors.isEmpty) {
      stdout.writeln('Version policy check passed (no blocking errors).');
      return 0;
    }
    if (policy.errors.isNotEmpty) {
      stderr.writeln('Version policy errors:\n');
      for (final e in policy.errors) {
        stderr.writeln('  - $e');
      }
      if (githubReport) {
        emitGithubCiReport(title: 'Version policy', errors: policy.errors);
      }
    }
    if (publishedConstraintErrors.isNotEmpty) {
      stderr.writeln('Published exact-version workspace constraint drift:\n');
      for (final e in publishedConstraintErrors) {
        stderr.writeln('  - $e');
      }
      if (githubReport) {
        emitGithubCiReport(
          title: 'Published constraint drift',
          errors: publishedConstraintErrors,
        );
      }
    }
    return 1;
  } on HttpException catch (e) {
    stderr.writeln('Manifest drift check failed: HTTP error from pub.dev: $e');
    return 1;
  } on SocketException catch (e) {
    stderr.writeln('Manifest drift check failed: could not reach pub.dev: $e');
    return 1;
  } on IOException catch (e) {
    stderr.writeln('Manifest drift check failed: I/O error: $e');
    return 1;
  }
}

/// Runs [--audit-published]: exits the process on fetch/parse failures (fail closed).
Future<int> runAuditPublished({
  required List<WorkspacePackage> packages,
  required Set<String> workspaceNames,
  required PubDevGateway catalog,
  bool githubReport = false,
  Directory? repoRoot,
  bool releasePrMode = false,
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
    final releaseSet = computeReleaseSet(
      packages: packages,
      pubDevVersions: pubVersions,
      coReleaseEnabled: releasePrMode,
    );
    final latestFindings = auditPublishedLatestErrors(
      packages: packages,
      workspaceNames: workspaceNames,
      pubDevVersions: pubVersions,
      publishedLatestDeps: latestDeps,
      releaseSet: releaseSet,
      releasePrMode: releasePrMode,
    );
    final publishedAtVersion =
        await fetchPublishedWorkspaceDepsForShippedPubspecVersions(
      packages: packages,
      pubDevVersions: pubVersions,
      catalog: catalog,
    );
    final constraintDriftErrors =
        publishedExactVersionWorkspaceConstraintDriftErrors(
      packages: packages,
      pubDevVersions: pubVersions,
      releaseSet: releaseSet,
      publishedDepsAtExactVersion: publishedAtVersion,
    );
    var provenanceWarnings = <String>[];
    var provenanceErrors = <String>[];
    if (repoRoot != null) {
      final provenance = await evaluateTagSourcePubDevProvenance(
        packages: packages,
        pubDevVersions: pubVersions,
        publishedDepsAtExactVersion: publishedAtVersion,
        repoRoot: repoRoot,
      );
      provenanceWarnings = provenance.warnings;
      provenanceErrors = provenance.errors;
    }
  final allErrors = [
      ...latestFindings.errors,
      ...constraintDriftErrors,
      ...provenanceErrors,
    ];
    for (final w in [
      ...latestFindings.warnings,
      ...provenanceWarnings,
    ]) {
      stdout.writeln('::warning::$w');
    }
    if (allErrors.isEmpty) {
      stdout.writeln('All pub.dev latest packages resolve sibling deps.');
      return 0;
    }
    stderr.writeln('pub.dev hosted dependency audit failed:\n');
    for (final e in allErrors) {
      stderr.writeln('  - $e');
    }
    if (githubReport) {
      emitGithubCiReport(title: 'pub.dev audit', errors: allErrors);
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
