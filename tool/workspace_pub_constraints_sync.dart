// Library for syncing intra-workspace pub dependency constraints.

import 'dart:io';

const workspaceRootDirName = 'pkgs';

/// Parses top-level `name:` and `version:` (column 0 only).
PubspecHeader parsePubspecHeader(String content) {
  String? name;
  String? version;
  for (final line in content.split('\n')) {
    if (line.startsWith('name:')) {
      name = line.substring('name:'.length).trim();
    } else if (line.startsWith('version:')) {
      version = line.substring('version:'.length).trim();
    }
  }
  if (name == null || version == null) {
    throw FormatException('pubspec missing name or version');
  }
  return PubspecHeader(name: name, version: version);
}

class PubspecHeader {
  PubspecHeader({required this.name, required this.version});

  final String name;
  final String version;
}

/// Rewrites a dependency line for a workspace package; preserves trailing comments.
String syncDependencyLine(
  String line,
  Map<String, String> workspaceVersions,
) {
  final match = RegExp(r'^(\s*)([a-zA-Z0-9_]+):\s*(.+)$').firstMatch(line);
  if (match == null) {
    return line;
  }
  final name = match.group(2)!;
  final version = workspaceVersions[name];
  if (version == null) {
    return line;
  }
  final indent = match.group(1)!;
  final rest = match.group(3)!;
  final comment = RegExp(r'^(.*?)(\s+#.*)$').firstMatch(rest);
  if (comment != null) {
    return '$indent$name: ^$version${comment.group(2)!}';
  }
  return '$indent$name: ^$version';
}

String syncPubspecContent(
  String content,
  Map<String, String> workspaceVersions,
) {
  final endsWithNewline = content.endsWith('\n');
  final lines = content.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  final out = <String>[];
  var inDeps = false;
  var depsIndent = 0;

  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('dependencies:') ||
        trimmed.startsWith('dev_dependencies:')) {
      inDeps = true;
      depsIndent = line.indexOf(trimmed);
      out.add(line);
      continue;
    }

    if (inDeps) {
      if (trimmed.isEmpty) {
        out.add(line);
        continue;
      }
      final indent = line.length - trimmed.length;
      if (indent <= depsIndent && trimmed.isNotEmpty) {
        inDeps = false;
        out.add(line);
        continue;
      }
      out.add(syncDependencyLine(line, workspaceVersions));
      continue;
    }

    out.add(line);
  }

  var result = out.join('\n');
  if (endsWithNewline) {
    result += '\n';
  }
  return result;
}

Directory findWorkspaceRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) {
      final text = File('${dir.path}/pubspec.yaml').readAsStringSync();
      if (text.contains('workspace:')) {
        return dir;
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      stderr.writeln('Could not find workspace root pubspec.yaml');
      exit(2);
    }
    dir = parent;
  }
}

List<String> workspacePubspecPaths(Directory repoRoot) {
  final pkgs = Directory('${repoRoot.path}/$workspaceRootDirName');
  return pkgs
      .listSync()
      .whereType<Directory>()
      .map((d) => '${d.path}/pubspec.yaml')
      .where((p) => File(p).existsSync())
      .toList()
    ..sort();
}

/// Returns exit code: 0 ok, 1 out of sync (check mode), 64 usage error.
int runWorkspacePubConstraintSync({required bool write}) {
  final check = !write;
  final repoRoot = findWorkspaceRepoRoot();
  final pubspecPaths = workspacePubspecPaths(repoRoot);
  final versions = <String, String>{};
  for (final path in pubspecPaths) {
    final doc = parsePubspecHeader(File(path).readAsStringSync());
    versions[doc.name] = doc.version;
  }

  var changed = false;
  for (final path in pubspecPaths) {
    final file = File(path);
    final original = file.readAsStringSync();
    final updated = syncPubspecContent(original, versions);
    if (updated != original) {
      changed = true;
      stderr.writeln('out of sync: $path');
      if (write) {
        file.writeAsStringSync(updated);
      }
    }
  }

  if (check && changed) {
    stderr.writeln(
      'Workspace pub constraints are out of sync with package versions.\n'
      'Run: dart run tool/sync_workspace_pub_constraints.dart --write',
    );
    return 1;
  }
  return 0;
}
