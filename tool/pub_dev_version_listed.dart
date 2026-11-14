// CLI: decide whether an exact version is already listed on pub.dev (skip publish).
//
// Exit 0 + stdout "listed" | "not_listed" | "not_found" (package 404).
// Exit 1 on usage/API errors.

import 'dart:convert';
import 'dart:io';

import 'pub_dev_version_listed_lib.dart';
import 'tool_cli.dart';

void printUsage() {
  stderr.writeln('''
Usage: dart run tool/pub_dev_version_listed.dart --package NAME --version V [--body-file PATH]

  --package NAME   pub.dev package name
  --version V      exact version string
  --body-file PATH Read package API JSON from file (else fetch live pub.dev)

Exit stdout (exit 0):
  listed       version is on pub.dev
  not_listed   package exists but version is absent (first publish of this version)
  not_found    package API returned 404 (first package publish)
''');
}

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    printUsage();
    exit(0);
  }

  requireOnlyKnownFlags(
    args,
    flags: {'--package', '--version', '--body-file', '--help', '-h'},
    valueFlags: {'--package', '--version', '--body-file'},
    onUsage: printUsage,
  );

  final pkgIdx = args.indexOf('--package');
  final verIdx = args.indexOf('--version');
  if (pkgIdx < 0 || verIdx < 0) {
    stderr.writeln('--package and --version are required');
    printUsage();
    exit(64);
  }
  final packageName = args[pkgIdx + 1];
  final version = args[verIdx + 1];
  final bodyFileIdx = args.indexOf('--body-file');
  String body;
  if (bodyFileIdx >= 0) {
    body = await File(args[bodyFileIdx + 1]).readAsString();
    final listed = pubDevPackageApiBodyListsVersion(body, version);
    stdout.writeln(listed ? 'listed' : 'not_listed');
    exit(0);
  }

  final client = HttpClient();
  try {
    final uri = Uri.parse('https://pub.dev/api/packages/$packageName');
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    if (response.statusCode == 404) {
      stdout.writeln('not_found');
      exit(0);
    }
    if (response.statusCode != 200) {
      stderr.writeln('pub.dev HTTP ${response.statusCode} for $packageName');
      exit(1);
    }
    body = await response.transform(utf8.decoder).join();
    final listed = pubDevPackageApiBodyListsVersion(body, version);
    stdout.writeln(listed ? 'listed' : 'not_listed');
  } finally {
    client.close(force: true);
  }
}
