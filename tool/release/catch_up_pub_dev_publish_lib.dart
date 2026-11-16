import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import '../publish_package_guard_lib.dart';
import '../pub_dev_version_listed_lib.dart';

/// Packages never dispatched by the catch-up train.
const catchUpNeverPublishPackageNameSubstrings = <String>['ecsai'];

/// One release-please publishable package (pub.dev, not `publish_to: none`).
final class ReleasePleasePublishablePackage {
  ReleasePleasePublishablePackage({
    required this.configPath,
    required this.packageName,
  });

  final String configPath;
  final String packageName;
}

/// Result of a pub.dev package API fetch.
sealed class PubDevPackageFetch {}

final class PubDevPackageFound extends PubDevPackageFetch {
  PubDevPackageFound(this.json);

  final Map<String, dynamic> json;
}

final class PubDevPackageNotFound extends PubDevPackageFetch {}

final class PubDevPackageFetchError extends PubDevPackageFetch {
  PubDevPackageFetchError(this.message);

  final String message;
}

/// Fetches pub.dev `/api/packages/<name>` for catch-up decisions.
abstract class PubDevPackageClient {
  Future<PubDevPackageFetch> fetch(String packageName);
}

/// Live pub.dev client (non-404 HTTP errors are [PubDevPackageFetchError]).
final class HttpPubDevPackageClient implements PubDevPackageClient {
  HttpPubDevPackageClient({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<PubDevPackageFetch> fetch(String packageName) async {
    final uri = Uri.parse('https://pub.dev/api/packages/$packageName');
    try {
      final request = await _client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode == 404) {
        return PubDevPackageNotFound();
      }
      if (response.statusCode != 200) {
        return PubDevPackageFetchError(
          'pub.dev HTTP ${response.statusCode} for $packageName',
        );
      }
      final body = await response.transform(utf8.decoder).join();
      return PubDevPackageFound(jsonDecode(body) as Map<String, dynamic>);
    } on SocketException catch (e) {
      return PubDevPackageFetchError('pub.dev network error for $packageName: $e');
    } on HttpException catch (e) {
      return PubDevPackageFetchError('pub.dev HTTP error for $packageName: $e');
    } on IOException catch (e) {
      return PubDevPackageFetchError('pub.dev I/O error for $packageName: $e');
    }
  }

  void close({bool force = false}) => _client.close(force: force);
}

/// Plan for catch-up publish dispatches.
final class CatchUpPubDevPublishPlan {
  CatchUpPubDevPublishPlan({
    required this.dispatchTags,
    required this.skippedDeduped,
    required this.skippedAlreadyOnPubDev,
    required this.neverPublishedPackageWarnings,
  });

  final List<String> dispatchTags;
  final List<String> skippedDeduped;
  final List<String> skippedAlreadyOnPubDev;
  final List<String> neverPublishedPackageWarnings;
}

List<ReleasePleasePublishablePackage> loadReleasePleasePublishablePackages({
  required String repoRoot,
  String? configText,
}) {
  final text = configText ??
      File('$repoRoot/release-please-config.json').readAsStringSync();
  final decoded = jsonDecode(text) as Map<String, dynamic>;
  final packages = decoded['packages'];
  if (packages is! Map) {
    throw FormatException('release-please-config.json: packages must be an object');
  }
  final out = <ReleasePleasePublishablePackage>[];
  for (final entry in packages.entries) {
    final configPath = entry.key.toString();
    final cfg = entry.value;
    if (cfg is! Map) {
      continue;
    }
    final packageName = cfg['package-name']?.toString();
    if (packageName == null || packageName.isEmpty) {
      continue;
    }
    if (catchUpNeverPublishPackageNameSubstrings
        .any(packageName.contains)) {
      continue;
    }
    final pubspecPath = '$repoRoot/$configPath/pubspec.yaml';
    final pubspec = File(pubspecPath);
    if (!pubspec.existsSync()) {
      throw StateError('missing pubspec for $configPath');
    }
    if (pubspecDeclaresPublishToNone(pubspec.readAsStringSync())) {
      continue;
    }
    out.add(
      ReleasePleasePublishablePackage(
        configPath: configPath,
        packageName: packageName,
      ),
    );
  }
  return out;
}

/// Tags release-please created on this run (for dedupe).
Set<String> releasePleaseTagsDispatchedThisRun(Map<String, dynamic> outputs) {
  final tags = <String>{};
  final pathsRaw = outputs['paths_released'];
  if (pathsRaw == null ||
      pathsRaw == '' ||
      pathsRaw == '[]' ||
      pathsRaw == false) {
    return tags;
  }
  final paths = jsonDecode(pathsRaw as String) as List<dynamic>;
  for (final path in paths) {
    final p = path as String;
    final created = outputs['$p--release_created'];
    if (created != true && created != 'true') {
      continue;
    }
    final tag = outputs['$p--tag_name'] as String?;
    if (tag != null && tag.isNotEmpty) {
      tags.add(tag);
    }
  }
  return tags;
}

/// Highest non-prerelease `package-vX.Y.Z` tag per [packageName], or null.
String? highestStableReleaseTag({
  required String packageName,
  required Iterable<String> allTags,
}) {
  final prefix = '$packageName-v';
  Version? best;
  String? bestTag;
  for (final tag in allTags) {
    if (!tag.startsWith(prefix)) {
      continue;
    }
    final versionText = tag.substring(prefix.length);
    Version version;
    try {
      version = Version.parse(versionText);
    } on FormatException {
      continue;
    }
    if (version.isPreRelease) {
      continue;
    }
    if (best == null || version > best) {
      best = version;
      bestTag = tag;
    }
  }
  return bestTag;
}

/// Computes catch-up publish tags (does not dispatch).
Future<CatchUpPubDevPublishPlan> planCatchUpPubDevPublish({
  required List<ReleasePleasePublishablePackage> packages,
  required Iterable<String> allGitTags,
  required Set<String> dedupeTags,
  required PubDevPackageClient pubDev,
}) async {
  final dispatchTags = <String>[];
  final skippedDeduped = <String>[];
  final skippedAlreadyOnPubDev = <String>[];
  final neverPublishedPackageWarnings = <String>[];

  for (final pkg in packages) {
    final tag = highestStableReleaseTag(
      packageName: pkg.packageName,
      allTags: allGitTags,
    );
    if (tag == null) {
      continue;
    }
    if (dedupeTags.contains(tag)) {
      skippedDeduped.add(tag);
      continue;
    }
    final version = tag.substring('${pkg.packageName}-v'.length);
    final fetch = await pubDev.fetch(pkg.packageName);
    switch (fetch) {
      case PubDevPackageFetchError(:final message):
        throw StateError(message);
      case PubDevPackageNotFound():
        neverPublishedPackageWarnings.add(
          '${pkg.packageName} has tag $tag but pub.dev returned 404 '
          '(package never published; first publish must be manual)',
        );
        dispatchTags.add(tag);
      case PubDevPackageFound(:final json):
        if (pubDevPackageApiListsVersion(json, version)) {
          skippedAlreadyOnPubDev.add(tag);
        } else {
          dispatchTags.add(tag);
        }
    }
  }
  dispatchTags.sort();
  return CatchUpPubDevPublishPlan(
    dispatchTags: dispatchTags,
    skippedDeduped: skippedDeduped,
    skippedAlreadyOnPubDev: skippedAlreadyOnPubDev,
    neverPublishedPackageWarnings: neverPublishedPackageWarnings,
  );
}

Future<List<String>> listGitTags({String? repoRoot}) async {
  final result = await Process.run(
    'git',
    ['tag', '-l', 'universal_*-v*'],
    workingDirectory: repoRoot,
  );
  if (result.exitCode != 0) {
    throw StateError(
      'git tag -l failed: ${result.stderr}',
    );
  }
  return (result.stdout as String)
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}