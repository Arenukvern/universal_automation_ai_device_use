// Catch-up dispatches publish_package.yml for tagged versions missing on pub.dev.
//
// Env: RELEASE_PLEASE_OUTPUTS (JSON), GH_TOKEN, GH_REPO
// Flags: --dry-run (print dispatch tags to stdout, one per line; no gh)
//
// On success writes GITHUB_OUTPUT dispatched_tags_json when not dry-run.

import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'catch_up_pub_dev_publish_lib.dart';
import '../tool_cli.dart';

Future<void> main(List<String> args) async {
  exit(await runCatchUpPubDevPublish(args));
}

/// CLI entry; returns a process exit code (testable).
@visibleForTesting
Future<int> runCatchUpPubDevPublish(
  List<String> args, {
  PubDevPackageClient? pubDevOverride,
}) async {
  requireOnlyKnownFlags(
    args,
    flags: {'--dry-run', '--help', '-h', '--repo-root'},
    valueFlags: {'--repo-root'},
    onUsage: _usage,
  );
  if (args.contains('--help') || args.contains('-h')) {
    _usage();
    return 0;
  }
  final dryRun = args.contains('--dry-run');
  final repoRootIdx = args.indexOf('--repo-root');
  final repoRoot = repoRootIdx >= 0
      ? args[repoRootIdx + 1]
      : Directory.current.path;

  Map<String, dynamic> releaseOutputs = const {};
  if (!dryRun) {
    final raw = Platform.environment['RELEASE_PLEASE_OUTPUTS'];
    if (raw == null || raw.isEmpty) {
      stderr.writeln('RELEASE_PLEASE_OUTPUTS is empty');
      return 2;
    }
    releaseOutputs = jsonDecode(raw) as Map<String, dynamic>;
  } else {
    final raw = Platform.environment['RELEASE_PLEASE_OUTPUTS'];
    if (raw != null && raw.isNotEmpty) {
      releaseOutputs = jsonDecode(raw) as Map<String, dynamic>;
    }
  }

  final dedupe = releasePleaseTagsDispatchedThisRun(releaseOutputs);
  final packages = loadReleasePleasePublishablePackages(repoRoot: repoRoot);
  final tags = await listGitTags(repoRoot: repoRoot);
  final client = pubDevOverride ?? HttpPubDevPackageClient();

  CatchUpPubDevPublishPlan plan;
  try {
    try {
      plan = await planCatchUpPubDevPublish(
        packages: packages,
        allGitTags: tags,
        dedupeTags: dedupe,
        pubDev: client,
      );
    } on StateError catch (e) {
      stderr.writeln('::error::catch-up pub.dev lookup failed: ${e.message}');
      return 1;
    }
  } finally {
    if (client is HttpPubDevPackageClient) {
      client.close(force: true);
    }
  }

  for (final warning in plan.neverPublishedPackageWarnings) {
    stderr.writeln('::warning::$warning');
  }
  for (final tag in plan.skippedDeduped) {
    stdout.writeln('Catch-up skip (deduped new release): $tag');
  }
  for (final tag in plan.skippedAlreadyOnPubDev) {
    stdout.writeln('Catch-up skip (already on pub.dev): $tag');
  }

  if (dryRun) {
    for (final tag in plan.dispatchTags) {
      stdout.writeln(tag);
    }
    return 0;
  }

  final repo = Platform.environment['GH_REPO'];
  final token = Platform.environment['GH_TOKEN'];
  if (repo == null || token == null) {
    stderr.writeln('GH_REPO and GH_TOKEN required');
    return 2;
  }

  var dispatched = <String>[];
  for (final tag in plan.dispatchTags) {
    stdout.writeln('Catch-up dispatch publish_package.yml for $tag');
    final result = await Process.run(
      'gh',
      [
        'workflow',
        'run',
        'publish_package.yml',
        '--repo',
        repo,
        '--ref',
        tag,
      ],
      environment: {...Platform.environment, 'GH_TOKEN': token},
    );
    if (result.exitCode != 0) {
      stderr.writeln('::error::gh workflow run failed for catch-up $tag');
      stderr.write(result.stdout);
      stderr.write(result.stderr);
      return 1;
    }
    dispatched.add(tag);
  }
  stdout.writeln(
    'Catch-up dispatched ${dispatched.length} publish workflow(s).',
  );

  final githubOutput = Platform.environment['GITHUB_OUTPUT'];
  final payload = jsonEncode(dispatched);
  if (githubOutput != null && githubOutput.isNotEmpty) {
    File(githubOutput).writeAsStringSync(
      'dispatched_tags_json=$payload\n',
      mode: FileMode.append,
    );
  }
  return 0;
}

void _usage() {
  stderr.writeln('''
Usage: dart run tool/release/catch_up_pub_dev_publish.dart [--dry-run] [--repo-root PATH]

  --dry-run        Print tags that would be dispatched (one per line); no gh
  --repo-root PATH Repository root (default: cwd)

Env (dispatch mode): RELEASE_PLEASE_OUTPUTS, GH_REPO, GH_TOKEN
''');
}