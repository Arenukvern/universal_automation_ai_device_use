import 'dart:io';

import 'hosted_deps_resolve_lib.dart';

/// Immutable release history: tag-source pubspec vs hosted pub.dev for same version.
final tagPubDevProvenanceAllowlist = <String, Map<String, String>>{
  'universal_automation_harness@0.3.0': {
    'universal_automation_toolkit': '^0.5.1',
  },
  'universal_screencast@0.3.1': {
    'universal_browser_cdp': '^0.6.1',
  },
};

typedef TagPubspecReader = Future<String?> Function(
  String tag,
  String pubspecRepoPath,
);

Future<String?> defaultTagPubspecReader(
  String tag,
  String pubspecRepoPath,
) async {
  final result = await Process.run(
    'git',
    ['show', '$tag:$pubspecRepoPath'],
  );
  if (result.exitCode != 0) {
    return null;
  }
  return (result.stdout as String).trim().isEmpty
      ? null
      : result.stdout as String;
}

/// Compares git-tag pubspec `universal_*` constraints to pub.dev archives.
///
/// Returns blocking errors; emits allowlisted historical mismatches as
/// [warnings] only (reported, not fixed by retagging).
Future<({List<String> errors, List<String> warnings})>
evaluateTagSourcePubDevProvenance({
  required List<WorkspacePackage> packages,
  required Map<String, List<String>> pubDevVersions,
  required Map<String, Map<String, String>> publishedDepsAtExactVersion,
  required Directory repoRoot,
  TagPubspecReader? tagPubspecReader,
}) async {
  final readTag = tagPubspecReader ?? defaultTagPubspecReader;
  final errors = <String>[];
  final warnings = <String>[];

  for (final pkg in packages) {
    final listed = pubDevVersions[pkg.name] ?? [];
    if (!listed.contains(pkg.version)) {
      continue;
    }
    final tag = '${pkg.name}-v${pkg.version}';
    final relPath = pkg.pubspecPath.startsWith('${repoRoot.path}/')
        ? pkg.pubspecPath.substring(repoRoot.path.length + 1)
        : pkg.pubspecPath;
    final tagContent = await readTag(tag, relPath);
    if (tagContent == null) {
      warnings.add(
        '$tag: no tag pubspec at $relPath (skip tag-source provenance)',
      );
      continue;
    }
    final tagDeps = parseWorkspaceDependencies(tagContent);
    final hostedKey = publishedDepsAtVersionKey(pkg.name, pkg.version);
    final hosted = publishedDepsAtExactVersion[hostedKey] ?? {};
    final allowKey = '${pkg.name}@${pkg.version}';
    final allowDeps = tagPubDevProvenanceAllowlist[allowKey] ?? {};

    for (final dep in {...tagDeps.keys, ...hosted.keys}) {
      if (!dep.startsWith('universal_')) {
        continue;
      }
      final tagConstraint = tagDeps[dep];
      final hostedConstraint = hosted[dep];
      if (tagConstraint == hostedConstraint) {
        continue;
      }
      final msg =
          '$allowKey: $dep tag-source $tagConstraint vs pub.dev hosted '
          '$hostedConstraint';
      if (allowDeps[dep] == hostedConstraint && tagConstraint != hostedConstraint) {
        warnings.add('KNOWN HISTORY: $msg');
        continue;
      }
      errors.add(msg);
    }
  }

  return (errors: errors, warnings: warnings);
}
