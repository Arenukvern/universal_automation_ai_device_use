// Structural contract check for release_binaries.yml (not grep — YAML AST).
//
// Usage:
//   dart run tool/check_release_workflow.dart
//   dart run tool/check_release_workflow.dart --workflow path/to.yml

import 'dart:io';

import 'release_workflow_contract_lib.dart';
import 'wait_publish_train_lib.dart';

Future<void> main(List<String> args) async {
  final root = Directory.current;
  if (!args.contains('--workflow') && !args.contains('--pr-smoke-workflow')) {
    await _validateAllReleaseWorkflowContracts(root.path);
    return;
  }
  if (args.contains('--pr-smoke-workflow')) {
    final i = args.indexOf('--pr-smoke-workflow');
    if (i + 1 >= args.length) {
      stderr.writeln('--pr-smoke-workflow requires a path');
      exit(2);
    }
    final workflowPath = args[i + 1];
    final file = File(workflowPath);
    if (!file.existsSync()) {
      stderr.writeln('Missing workflow: $workflowPath');
      exit(1);
    }
    final errors = validateReleaseBinariesPrWorkflowYaml(
      await file.readAsString(),
      label: file.uri.pathSegments.last,
    );
    if (errors.isNotEmpty) {
      stderr.writeln('check_release_workflow failures:');
      for (final e in errors) {
        stderr.writeln('  - $e');
      }
      exit(1);
    }
    stdout.writeln('check_release_workflow: ${file.path} OK');
    return;
  }
  String workflowPath;
  if (args.contains('--workflow')) {
    final i = args.indexOf('--workflow');
    if (i + 1 >= args.length) {
      stderr.writeln('--workflow requires a path');
      exit(2);
    }
    workflowPath = args[i + 1];
  } else {
    workflowPath = '${root.path}/.github/workflows/release_binaries.yml';
  }

  final file = File(workflowPath);
  if (!file.existsSync()) {
    stderr.writeln('Missing workflow: $workflowPath');
    exit(1);
  }

  final text = await file.readAsString();
  var errors = validateReleaseBinariesWorkflowYaml(
    text,
    label: file.uri.pathSegments.last,
  );
  if (workflowPath.endsWith('release_binaries.yml')) {
    errors = [
      ...errors,
      ...validateGhRunListJsonFieldAllowlist(releaseBinariesRunListJsonFields),
    ];
  }

  if (errors.isNotEmpty) {
    stderr.writeln('check_release_workflow failures:');
    for (final e in errors) {
      stderr.writeln('  - $e');
    }
    exit(1);
  }

  stdout.writeln('check_release_workflow: ${file.path} OK');
}

Future<void> _validateAllReleaseWorkflowContracts(String rootPath) async {
  final binaries =
      File('$rootPath/.github/workflows/release_binaries.yml');
  final prSmoke =
      File('$rootPath/.github/workflows/release_binaries_pr.yml');
  final releasePlease =
      File('$rootPath/.github/workflows/release-please.yml');
  for (final f in [binaries, prSmoke, releasePlease]) {
    if (!f.existsSync()) {
      stderr.writeln('Missing workflow: ${f.path}');
      exit(1);
    }
  }

  final binariesText = await binaries.readAsString();
  var errors = validateReleaseBinariesWorkflowYaml(
    binariesText,
    label: 'release_binaries.yml',
  );
  errors = [
    ...errors,
    ...validateGhRunListJsonFieldAllowlist(releaseBinariesRunListJsonFields),
  ];

  errors.addAll(
    validateReleaseBinariesPrWorkflowYaml(
      await prSmoke.readAsString(),
    ),
  );
  errors.addAll(
    validateReleasePleaseBinariesCaller(await releasePlease.readAsString()),
  );

  if (errors.isNotEmpty) {
    stderr.writeln('check_release_workflow failures:');
    for (final e in errors) {
      stderr.writeln('  - $e');
    }
    exit(1);
  }

  stdout.writeln('check_release_workflow: release binary workflows OK');
}