// Structural contract check for release binary workflows (not grep — YAML AST).
//
// Usage:
//   dart run tool/check_release_workflow.dart
//   dart run tool/check_release_workflow.dart --workflow path/to.yml

import 'dart:io';

import 'release_workflow_contract_lib.dart';

Future<void> main(List<String> args) async {
  final root = Directory.current;
  if (!args.contains('--workflow') &&
      !args.contains('--pr-smoke-workflow') &&
      !args.contains('--please-caller-workflow')) {
    await _validateAllReleaseWorkflowContracts(root.path);
    return;
  }
  if (args.contains('--please-caller-workflow')) {
    final i = args.indexOf('--please-caller-workflow');
    if (i + 1 >= args.length) {
      stderr.writeln('--please-caller-workflow requires a path');
      exit(2);
    }
    final workflowPath = args[i + 1];
    final file = File(workflowPath);
    if (!file.existsSync()) {
      stderr.writeln('Missing workflow: $workflowPath');
      exit(1);
    }
    final errors = validateReleasePleaseBinariesCaller(
      await file.readAsString(),
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
    workflowPath = '${root.path}/.github/workflows/release_binaries_build.yml';
  }

  final file = File(workflowPath);
  if (!file.existsSync()) {
    stderr.writeln('Missing workflow: $workflowPath');
    exit(1);
  }

  final text = await file.readAsString();
  final name = file.uri.pathSegments.last;
  final path = file.path;
  final List<String> errors;
  if (path.contains('release_workflow_publish') ||
      name == 'release_binaries_publish.yml') {
    errors = validateReleaseBinariesPublishWorkflowYaml(text, label: name);
  } else if (path.contains('release_workflow_dispatch') ||
      name == 'release_binaries.yml') {
    errors = validateReleaseBinariesDispatchWorkflowYaml(text, label: name);
  } else {
    errors = validateReleaseBinariesBuildWorkflowYaml(text, label: name);
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
  final paths = [
    '$rootPath/.github/workflows/release_binaries_build.yml',
    '$rootPath/.github/workflows/release_binaries_publish.yml',
    '$rootPath/.github/workflows/release_binaries.yml',
    '$rootPath/.github/workflows/release_binaries_pr.yml',
    '$rootPath/.github/workflows/release-please.yml',
  ];
  for (final p in paths) {
    if (!File(p).existsSync()) {
      stderr.writeln('Missing workflow: $p');
      exit(1);
    }
  }

  var errors = <String>[
    ...validateReleaseBinariesBuildWorkflowYaml(
      await File(paths[0]).readAsString(),
    ),
    ...validateReleaseBinariesPublishWorkflowYaml(
      await File(paths[1]).readAsString(),
    ),
    ...validateReleaseBinariesDispatchWorkflowYaml(
      await File(paths[2]).readAsString(),
    ),
    ...validateReleaseBinariesPrWorkflowYaml(
      await File(paths[3]).readAsString(),
    ),
    ...validateReleasePleaseBinariesCaller(
      await File(paths[4]).readAsString(),
    ),
  ];

  if (errors.isNotEmpty) {
    stderr.writeln('check_release_workflow failures:');
    for (final e in errors) {
      stderr.writeln('  - $e');
    }
    exit(1);
  }

  stdout.writeln('check_release_workflow: release binary workflows OK');
}