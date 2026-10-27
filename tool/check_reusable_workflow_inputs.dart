// Validates that `with:` keys match `workflow_call` inputs on remote reusable workflows.
//
// Usage: dart run tool/check_reusable_workflow_inputs.dart
// Env: GITHUB_TOKEN (optional) — reduces raw.githubusercontent.com rate limits in CI.

import 'dart:io';

import 'reusable_workflow_inputs_lib.dart';

Future<void> main() async {
  try {
    final root = findRepoRootWithWorkflows();
    final errors = await validateRepositoryWorkflows(
      workflowDirectory: Directory('${root.path}/.github/workflows'),
      githubToken: Platform.environment['GITHUB_TOKEN'],
    );

    if (errors.isNotEmpty) {
      stderr.writeln('Reusable workflow input errors:\n');
      for (final e in errors) {
        stderr.writeln('  - $e');
      }
      exit(1);
    }
    stdout.writeln(
      'All reusable workflow inputs match remote workflow_call schemas.',
    );
  } on WorkflowFetchException catch (e) {
    stderr.writeln(e.message);
    exit(1);
  } on StateError catch (e) {
    stderr.writeln(e.message);
    exit(2);
  }
}
