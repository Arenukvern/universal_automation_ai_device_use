// Syncs ^version constraints for dependencies on other workspace packages.
//
// Pub workspaces require each package's constraint to accept the workspace
// version of the dependency. release-please bumps package versions but not
// dependent constraints; this tool keeps them aligned.
//
// Usage:
//   dart run tool/sync_workspace_pub_constraints.dart --check
//   dart run tool/sync_workspace_pub_constraints.dart --write

import 'dart:io';

const _workspaceRoot = 'pkgs';

void main(List<String> args) {
  final write = args.contains('--write');
  if (!write && !args.contains('--check')) {
    stderr.writeln('Pass --check or --write');
    exit(64);
  }
  final check = !write;

  final repoRoot = _findRepoRoot();
  final pubspecPaths = _workspacePubspecs(repoRoot);
  final versions = <String, String>{};
  for (final path in pubspecPaths) {
    final doc = _Pubspec.parse(File(path).readAsStringSync());
    versions[doc.name] = doc.version;
  }

  var changed = false;
  for (final path in pubspecPaths) {
    final file = File(path);
    final original = file.readAsStringSync();
    final updated = _syncFile(original, versions);
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
    exit(1);
  }
}

Directory _findRepoRoot() {
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

List<String> _workspacePubspecs(Directory repoRoot) {
  final pkgs = Directory('${repoRoot.path}/$_workspaceRoot');
  return pkgs
      .listSync()
      .whereType<Directory>()
      .map((d) => '${d.path}/pubspec.yaml')
      .where((p) => File(p).existsSync())
      .toList()
    ..sort();
}

String _syncFile(String content, Map<String, String> workspaceVersions) {
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
      final synced = _syncDepLine(line, workspaceVersions);
      out.add(synced);
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

String _syncDepLine(String line, Map<String, String> workspaceVersions) {
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
  return '$indent$name: ^$version';
}

class _Pubspec {
  _Pubspec({required this.name, required this.version});

  final String name;
  final String version;

  static _Pubspec parse(String content) {
    String? name;
    String? version;
    for (final line in content.split('\n')) {
      final t = line.trim();
      if (t.startsWith('name:')) {
        name = t.substring('name:'.length).trim();
      } else if (t.startsWith('version:')) {
        version = t.substring('version:'.length).trim();
      }
    }
    if (name == null || version == null) {
      throw FormatException('pubspec missing name or version');
    }
    return _Pubspec(name: name, version: version);
  }
}
