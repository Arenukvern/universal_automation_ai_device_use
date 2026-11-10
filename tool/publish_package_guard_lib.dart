import 'dart:io';

import 'workspace_pub_constraints_sync.dart';

/// Release tags: `refs/tags/universal_foo-v1.2.3`.
final publishTagRefPattern = RegExp(
  r'^refs/tags/(universal_[a-z0-9_]+)-v([0-9]+\.[0-9]+\.[0-9]+)$',
);

class PublishTagRef {
  PublishTagRef({
    required this.packageName,
    required this.version,
    required this.pkgDir,
  });

  final String packageName;
  final String version;
  final String pkgDir;
}

PublishTagRef parsePublishTagRef(String githubRef) {
  final match = publishTagRefPattern.firstMatch(githubRef);
  if (match == null) {
    throw FormatException(
      'GITHUB_REF must match refs/tags/universal_<pkg>-vX.Y.Z; got: $githubRef',
    );
  }
  final name = match.group(1)!;
  final version = match.group(2)!;
  return PublishTagRef(
    packageName: name,
    version: version,
    pkgDir: 'pkgs/$name',
  );
}

bool pubspecDeclaresPublishToNone(String content) {
  for (final line in content.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('publish_to:') &&
        trimmed.replaceFirst('publish_to:', '').trim() == 'none') {
      return true;
    }
  }
  return false;
}

/// Validates [pkgDir]/pubspec.yaml for OIDC publish at [tag].
void validatePublishablePackageAtTag({
  required Directory repoRoot,
  required PublishTagRef tag,
}) {
  final pubspecFile = File('${repoRoot.path}/${tag.pkgDir}/pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    throw StateError(
      'No pubspec at ${tag.pkgDir}/pubspec.yaml for tag ${tag.packageName}-v${tag.version}',
    );
  }
  final content = pubspecFile.readAsStringSync();
  if (pubspecDeclaresPublishToNone(content)) {
    throw StateError(
      '${tag.pkgDir}/pubspec.yaml sets publish_to: none; refusing publish',
    );
  }
  final header = parsePubspecHeader(content);
  if (header.name != tag.packageName) {
    throw StateError(
      'Tag package ${tag.packageName} does not match pubspec name ${header.name}',
    );
  }
  if (header.version != tag.version) {
    throw StateError(
      'Tag version ${tag.version} does not match pubspec version ${header.version} '
      'in ${tag.pkgDir}/pubspec.yaml',
    );
  }
}
