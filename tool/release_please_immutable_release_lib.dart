import 'dart:convert';
import 'dart:io';

import 'release_please_toolkit_versions_lib.dart';

/// Toolkit release-please settings required when GitHub immutable releases are on.
List<String> validateToolkitImmutableReleaseReleasePleaseConfig(
  String repoRoot, {
  String? configText,
}) {
  final errors = <String>[];
  final text = configText ??
      File('$repoRoot/release-please-config.json').readAsStringSync();
  final dynamic decoded;
  try {
    decoded = jsonDecode(text);
  } catch (e) {
    return ['release-please-config.json: invalid JSON: $e'];
  }
  if (decoded is! Map<String, dynamic>) {
    return ['release-please-config.json: root must be an object'];
  }
  if (decoded['draft'] == true) {
    errors.add(
      'release-please-config.json: must not set top-level "draft": true '
      '(would draft every package release and break pub.dev tag dispatch; '
      'only $toolkitReleasePleasePackage may be draft)',
    );
  }
  if (decoded['force-tag-creation'] == true) {
    errors.add(
      'release-please-config.json: must not set top-level "force-tag-creation": true',
    );
  }
  final packages = decoded['packages'];
  if (packages is! Map) {
    return ['release-please-config.json: packages must be an object'];
  }

  final toolkit = packages[toolkitReleasePleasePackage];
  if (toolkit is! Map) {
    errors.add(
      'release-please-config.json: missing $toolkitReleasePleasePackage package config',
    );
    return errors;
  }
  if (toolkit['draft'] != true) {
    errors.add(
      'release-please-config.json: $toolkitReleasePleasePackage must set '
      '"draft": true (immutable GitHub releases: upload assets before publish)',
    );
  }
  if (toolkit['force-tag-creation'] != true) {
    errors.add(
      'release-please-config.json: $toolkitReleasePleasePackage must set '
      '"force-tag-creation": true so release-please anchors on the git tag '
      'while the GitHub release stays a draft (avoids duplicate release PRs)',
    );
  }

  for (final entry in packages.entries) {
    final path = entry.key.toString();
    if (path == toolkitReleasePleasePackage) {
      continue;
    }
    final pkg = entry.value;
    if (pkg is Map && pkg['draft'] == true) {
      errors.add(
        'release-please-config.json: only $toolkitReleasePleasePackage may set '
        'draft: true (other packages have no GitHub binary assets; got $path)',
      );
    }
    if (pkg is Map && pkg['force-tag-creation'] == true) {
      errors.add(
        'release-please-config.json: only $toolkitReleasePleasePackage may set '
        'force-tag-creation: true (got $path)',
      );
    }
  }

  return errors;
}