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

class _SemVerTriple implements Comparable<_SemVerTriple> {
  _SemVerTriple(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(_SemVerTriple other) {
    if (major != other.major) {
      return major.compareTo(other.major);
    }
    if (minor != other.minor) {
      return minor.compareTo(other.minor);
    }
    return patch.compareTo(other.patch);
  }
}

_SemVerTriple? parseSemVerTriple(String version) {
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version.trim());
  if (match == null) {
    return null;
  }
  return _SemVerTriple(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

/// Upper exclusive bound for a caret floor (pub semantics).
_SemVerTriple caretUpperExclusive(_SemVerTriple floor) {
  if (floor.major == 0) {
    return _SemVerTriple(0, floor.minor + 1, 0);
  }
  return _SemVerTriple(floor.major + 1, 0, 0);
}

/// Whether [caretFloor] `^x.y.z` admits [targetVersion] on pub.dev.
bool caretConstraintAdmits(String caretFloor, String targetVersion) {
  final floor = parseSemVerTriple(caretFloor);
  final target = parseSemVerTriple(targetVersion);
  if (floor == null || target == null) {
    return false;
  }
  if (target.compareTo(floor) < 0) {
    return false;
  }
  final upper = caretUpperExclusive(floor);
  return target.compareTo(upper) < 0;
}

String? parseCaretFloorFromConstraint(String constraintPart) {
  final trimmed = constraintPart.trim();
  final match = RegExp(r'^\^(\d+\.\d+\.\d+)').firstMatch(trimmed);
  return match?.group(1);
}

/// Drift when a hand-raised caret floor exceeds the sibling workspace version.
String? workspaceSiblingFloorAboveDriftMessage({
  required String depName,
  required String constraintPart,
  required String siblingVersion,
}) {
  final floor = parseCaretFloorFromConstraint(constraintPart);
  if (floor == null) {
    return null;
  }
  final floorV = parseSemVerTriple(floor);
  final siblingV = parseSemVerTriple(siblingVersion);
  if (floorV == null || siblingV == null) {
    return null;
  }
  if (floorV.compareTo(siblingV) > 0) {
    return 'floor ^$floor is above workspace $depName $siblingVersion';
  }
  return null;
}

List<String> collectHandRaisedFloorDrifts(
  String content,
  Map<String, String> workspaceVersions,
) {
  final messages = <String>[];
  var inDeps = false;
  var depsIndent = 0;

  for (final line in content.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('dependencies:') ||
        trimmed.startsWith('dev_dependencies:')) {
      inDeps = true;
      depsIndent = line.length - trimmed.length;
      continue;
    }

    if (!inDeps) {
      continue;
    }
    if (trimmed.isEmpty) {
      continue;
    }
    final indent = line.length - trimmed.length;
    if (indent <= depsIndent) {
      inDeps = false;
      continue;
    }

    final depMatch = RegExp(r'^([a-zA-Z0-9_]+):\s+(.+)$').firstMatch(trimmed);
    if (depMatch == null) {
      continue;
    }
    final depName = depMatch.group(1)!;
    final siblingVersion = workspaceVersions[depName];
    if (siblingVersion == null) {
      continue;
    }
    final rest = depMatch.group(2)!;
    final comment = RegExp(r'^(.*?)(\s+#.*)$').firstMatch(rest);
    final constraintPart = comment != null ? comment.group(1)! : rest;
    final msg = workspaceSiblingFloorAboveDriftMessage(
      depName: depName,
      constraintPart: constraintPart,
      siblingVersion: siblingVersion,
    );
    if (msg != null) {
      messages.add(msg);
    }
  }
  return messages;
}

/// Rewrites a dependency line for a workspace package; preserves trailing comments.
///
/// Raises the caret floor only when the existing constraint does not admit the
/// sibling package version (pub caret rules). Never lowers a hand-raised floor.
String syncDependencyLine(
  String line,
  Map<String, String> workspaceVersions,
) {
  final match = RegExp(r'^(\s*)([a-zA-Z0-9_]+):\s*(.+)$').firstMatch(line);
  if (match == null) {
    return line;
  }
  final name = match.group(2)!;
  final siblingVersion = workspaceVersions[name];
  if (siblingVersion == null) {
    return line;
  }
  final indent = match.group(1)!;
  final rest = match.group(3)!;
  final comment = RegExp(r'^(.*?)(\s+#.*)$').firstMatch(rest);
  final constraintPart = comment != null ? comment.group(1)! : rest;
  final suffix = comment?.group(2) ?? '';

  final floor = parseCaretFloorFromConstraint(constraintPart);
  if (floor != null) {
    if (caretConstraintAdmits(floor, siblingVersion)) {
      return line;
    }
    final floorV = parseSemVerTriple(floor);
    final siblingV = parseSemVerTriple(siblingVersion);
    if (floorV != null &&
        siblingV != null &&
        floorV.compareTo(siblingV) > 0) {
      return line;
    }
  }

  final updated = '$indent$name: ^$siblingVersion$suffix';
  return updated;
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
  var handRaisedDrift = false;
  for (final path in pubspecPaths) {
    final file = File(path);
    final original = file.readAsStringSync();
    for (final msg in collectHandRaisedFloorDrifts(original, versions)) {
      handRaisedDrift = true;
      stderr.writeln(msg);
    }
    final updated = syncPubspecContent(original, versions);
    if (updated != original) {
      changed = true;
      stderr.writeln('out of sync: $path');
      if (write) {
        file.writeAsStringSync(updated);
      }
    }
  }

  if (check && (changed || handRaisedDrift)) {
    stderr.writeln(
      'Workspace pub constraints are out of sync with package versions.\n'
      'Run: dart run tool/sync_workspace_pub_constraints.dart --write',
    );
    return 1;
  }
  return 0;
}
