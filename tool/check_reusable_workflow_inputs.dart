// Validates that `with:` keys match `workflow_call` inputs on remote reusable workflows.
//
// actionlint does not fetch reusable workflow definitions; unknown inputs cause
// workflow startup_failure with 0 jobs.
//
// Usage: dart run tool/check_reusable_workflow_inputs.dart

import 'dart:convert';
import 'dart:io';

final _usesReusable = RegExp(
  r'^\s*uses:\s+([^/\s]+)/([^/\s]+)/\.github/workflows/([^@\s]+)@(\S+)\s*$',
);

Future<void> main() async {
  final root = _findRepoRoot();
  final workflowDir = Directory('${root.path}/.github/workflows');
  final errors = <String>[];

  for (final entity in workflowDir.listSync().whereType<File>()) {
    if (!entity.path.endsWith('.yml') && !entity.path.endsWith('.yaml')) {
      continue;
    }
    final content = entity.readAsStringSync();
    final calls = _extractReusableCalls(content, entity.path);
    for (final call in calls) {
      final declared = await _fetchDeclaredInputs(call);
      for (final key in call.withKeys) {
        if (!declared.contains(key)) {
          errors.add(
            '${call.callerPath}: job "${call.jobName}" passes undeclared input '
            '"$key" to ${call.slug} (declared: ${declared.join(", ")})',
          );
        }
      }
    }
  }

  if (errors.isNotEmpty) {
    stderr.writeln('Reusable workflow input errors:\n');
    for (final e in errors) {
      stderr.writeln('  - $e');
    }
    exit(1);
  }
  stdout.writeln('All reusable workflow inputs match remote workflow_call schemas.');
}

Directory _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (Directory('${dir.path}/.github/workflows').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      stderr.writeln('Could not find .github/workflows');
      exit(2);
    }
    dir = parent;
  }
}

class _ReusableCall {
  _ReusableCall({
    required this.callerPath,
    required this.jobName,
    required this.owner,
    required this.repo,
    required this.workflowFile,
    required this.ref,
    required this.withKeys,
  });

  final String callerPath;
  final String jobName;
  final String owner;
  final String repo;
  final String workflowFile;
  final String ref;
  final List<String> withKeys;

  String get slug => '$owner/$repo/.github/workflows/$workflowFile@$ref';
}

List<_ReusableCall> _extractReusableCalls(String content, String path) {
  final lines = content.split('\n');
  final calls = <_ReusableCall>[];

  for (var i = 0; i < lines.length; i++) {
    final usesMatch = _usesReusable.firstMatch(lines[i]);
    if (usesMatch == null) {
      continue;
    }

    var jobName = 'unknown';
    for (var k = i - 1; k >= 0; k--) {
      if (lines[k].startsWith('jobs:')) {
        break;
      }
      final jobHeader = RegExp(r'^  ([a-zA-Z0-9_-]+):\s*$').firstMatch(lines[k]);
      if (jobHeader != null) {
        jobName = jobHeader.group(1)!;
        break;
      }
    }

    final withKeys = <String>[];
    for (var j = i + 1; j < lines.length; j++) {
      final next = lines[j];
      if (next.trim().isEmpty) {
        continue;
      }
      if (!next.startsWith('    ')) {
        break;
      }
      if (RegExp(r'^    with:\s*$').matchAsPrefix(next) != null) {
        for (var w = j + 1; w < lines.length; w++) {
          final wline = lines[w];
          if (wline.trim().isEmpty) {
            continue;
          }
          if (!wline.startsWith('      ')) {
            break;
          }
          final keyMatch = RegExp(r'^      ([a-zA-Z0-9_-]+):').firstMatch(wline);
          if (keyMatch != null) {
            withKeys.add(keyMatch.group(1)!);
          }
        }
        break;
      }
    }

    calls.add(
      _ReusableCall(
        callerPath: path,
        jobName: jobName,
        owner: usesMatch.group(1)!,
        repo: usesMatch.group(2)!,
        workflowFile: usesMatch.group(3)!,
        ref: usesMatch.group(4)!,
        withKeys: withKeys,
      ),
    );
  }

  return calls;
}

Future<Set<String>> _fetchDeclaredInputs(_ReusableCall call) async {
  final url =
      'https://raw.githubusercontent.com/${call.owner}/${call.repo}/${call.ref}'
      '/.github/workflows/${call.workflowFile}';
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      stderr.writeln('Warning: could not fetch $url (${response.statusCode})');
      return {};
    }
    final body = await response.transform(utf8.decoder).join();
    return _parseWorkflowCallInputs(body);
  } finally {
    client.close();
  }
}

Set<String> _parseWorkflowCallInputs(String yaml) {
  final lines = yaml.split('\n');
  var inWorkflowCall = false;
  var inInputs = false;
  var inputsIndent = 0;
  final names = <String>{};

  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('workflow_call:')) {
      inWorkflowCall = true;
      continue;
    }
    if (!inWorkflowCall) {
      continue;
    }
    if (trimmed.startsWith('inputs:')) {
      inInputs = true;
      inputsIndent = line.indexOf('inputs:');
      continue;
    }
    if (inInputs) {
      if (trimmed.isEmpty) {
        continue;
      }
      final indent = line.length - trimmed.length;
      if (indent <= inputsIndent) {
        inInputs = false;
        continue;
      }
      final key = RegExp(r'^([a-zA-Z0-9_-]+):').firstMatch(trimmed);
      if (key != null && indent == inputsIndent + 2) {
        names.add(key.group(1)!);
      }
    }
  }
  return names;
}
