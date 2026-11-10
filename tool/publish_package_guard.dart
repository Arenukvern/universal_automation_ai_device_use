// Validates GITHUB_REF and pubspec for publish_package.yml guard job.
//
// Writes pkg_dir, package_name, version to GITHUB_OUTPUT when set.

import 'dart:io';

import 'publish_package_guard_lib.dart';
import 'workspace_pub_constraints_sync.dart';

void main(List<String> args) {
  final ref = Platform.environment['GITHUB_REF'];
  if (ref == null || ref.isEmpty) {
    stderr.writeln('GITHUB_REF is not set');
    exit(1);
  }

  try {
    final tag = parsePublishTagRef(ref);
    final repoRoot = findWorkspaceRepoRoot();
    validatePublishablePackageAtTag(repoRoot: repoRoot, tag: tag);
    stdout.writeln(
      'Publish guard OK: ${tag.packageName}@${tag.version} (${tag.pkgDir})',
    );
    _writeGithubOutput(tag);
    exit(0);
  } on FormatException catch (e) {
    stderr.writeln('::error::${e.message}');
    stderr.writeln(
      'Manual publish: gh workflow run publish_package.yml '
      '--ref universal_<pkg>-vX.Y.Z',
    );
    exit(1);
  } on StateError catch (e) {
    stderr.writeln('::error::${e.message}');
    exit(1);
  }
}

void _writeGithubOutput(PublishTagRef tag) {
  final path = Platform.environment['GITHUB_OUTPUT'];
  if (path == null || path.isEmpty) {
    return;
  }
  File(path).writeAsStringSync(
    'pkg_dir=${tag.pkgDir}\n'
    'package_name=${tag.packageName}\n'
    'version=${tag.version}\n',
    mode: FileMode.append,
  );
}
