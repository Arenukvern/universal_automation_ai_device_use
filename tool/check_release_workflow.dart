// Structural contract check for release binary workflows (not grep — YAML AST).
//
// Usage:
//   dart run tool/check_release_workflow.dart
//   dart run tool/check_release_workflow.dart --workflow path/to.yml

import 'dart:io';

import 'release_please_toolkit_versions_lib.dart';
import 'release_workflow_contract_lib.dart';
import 'release_publish_script_pins_lib.dart';
import 'release_workflow_permissions_lib.dart';

Future<void> main(List<String> args) async {
  final root = Directory.current;
  if (args.contains('--full-contract-script-overlay')) {
    final i = args.indexOf('--full-contract-script-overlay');
    if (i + 1 >= args.length) {
      stderr.writeln('--full-contract-script-overlay requires a directory');
      exit(2);
    }
    final overlay = args[i + 1];
    await _validateAllReleaseWorkflowContracts(
      root.path,
      scriptOverlayDir: overlay,
    );
    return;
  }
  if (!args.contains('--workflow') &&
      !args.contains('--pr-smoke-workflow') &&
      !args.contains('--publish-caller-workflow') &&
      !args.contains('--release-workflow') &&
      !args.contains('--binary-reusable-caller-workflow')) {
    await _validateAllReleaseWorkflowContracts(root.path);
    return;
  }
  if (args.contains('--release-workflow')) {
    final i = args.indexOf('--release-workflow');
    if (i + 1 >= args.length) {
      stderr.writeln('--release-workflow requires a path');
      exit(2);
    }
    final workflowPath = args[i + 1];
    final file = File(workflowPath);
    if (!file.existsSync()) {
      stderr.writeln('Missing workflow: $workflowPath');
      exit(1);
    }
    final errors = validateChangesetsReleaseWorkflow(await file.readAsString());
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
  if (args.contains('--binary-reusable-caller-workflow')) {
    final i = args.indexOf('--binary-reusable-caller-workflow');
    if (i + 1 >= args.length) {
      stderr.writeln('--binary-reusable-caller-workflow requires a path');
      exit(2);
    }
    final workflowPath = args[i + 1];
    final file = File(workflowPath);
    if (!file.existsSync()) {
      stderr.writeln('Missing workflow: $workflowPath');
      exit(1);
    }
    final label = file.uri.pathSegments.last;
    final errors = validateBinaryReusableCallerYaml(
      await file.readAsString(),
      label,
      repoRoot: root.path,
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
  if (args.contains('--publish-caller-workflow')) {
    final i = args.indexOf('--publish-caller-workflow');
    if (i + 1 >= args.length) {
      stderr.writeln('--publish-caller-workflow requires a path');
      exit(2);
    }
    final workflowPath = args[i + 1];
    final file = File(workflowPath);
    if (!file.existsSync()) {
      stderr.writeln('Missing workflow: $workflowPath');
      exit(1);
    }
    final yaml = await file.readAsString();
    final label = file.uri.pathSegments.last;
    final errors = [
      ...validateChangesetsPublishBinariesCaller(yaml, label: label),
      ...validateBinaryReusableCallerYaml(yaml, label, repoRoot: root.path),
    ];
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
    final label = file.uri.pathSegments.last;
    final yaml = await file.readAsString();
    final errors = [
      ...validateReleaseBinariesPrWorkflowYaml(
        yaml,
        label: label,
      ),
      ...validateBinaryReusableCallerYaml(yaml, label, repoRoot: root.path),
    ];
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
      path.contains('release_workflow_caller') ||
      name == 'release_binaries.yml') {
    errors = [
      ...validateReleaseBinariesDispatchWorkflowYaml(text, label: name),
      ...validateBinaryReusableCallerYaml(text, name, repoRoot: root.path),
    ];
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

Future<void> _validateAllReleaseWorkflowContracts(
  String rootPath, {
  String? scriptOverlayDir,
}) async {
  final paths = [
    '$rootPath/.github/workflows/release_binaries_build.yml',
    '$rootPath/.github/workflows/release_binaries_publish.yml',
    '$rootPath/.github/workflows/release_binaries.yml',
    '$rootPath/.github/workflows/release_binaries_pr.yml',
    '$rootPath/.github/workflows/release.yml',
    '$rootPath/.github/workflows/publish.yml',
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
    ...validateChangesetsReleaseWorkflow(
      await File(paths[4]).readAsString(),
    ),
    ...validateChangesetsPublishBinariesCaller(
      await File(paths[5]).readAsString(),
    ),
    ...validateProductionReusablePermissionChains(rootPath),
    ...validateToolkitVersionSurfacesChangesets(rootPath),
    ...validateReleasePublishScriptClosure(
      rootPath,
      scriptOverlayDir: scriptOverlayDir,
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