import 'dart:io';

import 'package:test/test.dart';

import 'release_workflow_permissions_lib.dart';

void main() {
  final repoRoot = Directory.current.path;

  group('production reusable chains (parsed from repo YAML)', () {
    late List<PermissionPathRow> paths;
    late List<(String, String)> discoveredCallers;

    setUp(() {
      discoveredCallers = discoverBinaryReusableCallerWorkflowFiles(repoRoot);
      paths = buildReusablePermissionPaths(repoRoot);
    });

    test('discovers every production caller workflow (no hard-coded list)', () {
      expect(
        discoveredCallers.map((e) => e.$1).toSet(),
        {
          'release-please.yml',
          'release_binaries.yml',
          'release_binaries_pr.yml',
        },
      );
    });

    test('enumerates every caller → callee job path', () {
      expect(paths.map((p) => p.path).toSet(), containsAll({
        'release-please.yml → release-binaries-build → release_binaries_build.yml → prepare',
        'release-please.yml → release-binaries-build → release_binaries_build.yml → build',
        'release-please.yml → release-binaries-build → release_binaries_build.yml → dry-run-bundle',
        'release-please.yml → release-binaries-publish → release_binaries_publish.yml → publish',
        'release-please.yml → release-binaries-publish → release_binaries_publish.yml → postflight',
        'release_binaries.yml → build → release_binaries_build.yml → prepare',
        'release_binaries.yml → build → release_binaries_build.yml → build',
        'release_binaries.yml → build → release_binaries_build.yml → dry-run-bundle',
        'release_binaries.yml → publish → release_binaries_publish.yml → publish',
        'release_binaries.yml → publish → release_binaries_publish.yml → postflight',
        'release_binaries_pr.yml → smoke → release_binaries_build.yml → prepare',
        'release_binaries_pr.yml → smoke → release_binaries_build.yml → build',
        'release_binaries_pr.yml → smoke → release_binaries_build.yml → dry-run-bundle',
      }));
    });

    test('no callee scope exceeds its caller job ceiling', () {
      final errors = validateProductionReusablePermissionChains(repoRoot);
      expect(errors, isEmpty, reason: errors.join('; '));
    });

    test('publish job contents:write only where caller grants write', () {
      final publishWrite = paths
          .where((p) => p.path.contains('→ publish') && p.path.endsWith('→ publish'))
          .toList();
      expect(publishWrite, isNotEmpty);
      for (final row in publishWrite) {
        expect(
          row.effective.scopes['contents'],
          AccessLevel.write,
          reason: row.path,
        );
        expect(
          row.ceiling.scopes['contents'],
          AccessLevel.write,
          reason: row.path,
        );
      }
      final smokeRows = paths
          .where((p) => p.path.startsWith('release_binaries_pr.yml'))
          .toList();
      for (final row in smokeRows) {
        expect(
          row.ceiling.scopes['contents'],
          AccessLevel.read,
          reason: row.path,
        );
        expect(
          row.effective.scopes['contents'],
          isNot(AccessLevel.write),
          reason: row.path,
        );
      }
    });
  });

  group('release-please local jobs', () {
    test('audit-release-train and pub train respect explicit ceilings', () {
      final errors = validateReleasePleaseLocalJobPermissions(repoRoot);
      expect(errors, isEmpty, reason: errors.join('; '));
    });
  });

  group('permission parser edge cases', () {
    test('read-all, write-all, and empty map', () {
      expect(
        PermissionMap.parse('read-all').scopes['contents'],
        AccessLevel.read,
      );
      expect(
        PermissionMap.parse('write-all').scopes['packages'],
        AccessLevel.write,
      );
      expect(
        PermissionMap.parse({}).scopes['contents'],
        AccessLevel.none,
      );
    });

    test('rejects unknown access levels', () {
      expect(
        () => PermissionMap.parse({'contents': 'wirte'}),
        throwsA(isA<PermissionParseException>()),
      );
    });

    test('callee write under read caller is an over-request (startup refused)', () {
      final errors = permissionChainErrors(
        callerJobScopes: {'contents': 'read'},
        calleeWorkflowScopes: {'contents': 'read'},
        calleeJobs: {
          'publish': {'contents': 'write'},
        },
      );
      expect(
        errors.any((e) => e.contains('contents') && e.contains('write')),
        isTrue,
        reason: errors.join('; '),
      );
    });

    test('missing caller permissions block is not treated as write-all', () {
      final resolved = PermissionMap.resolveCallerJobCeiling(
        jobPerms: null,
        workflowPerms: null,
        label: 'test → publish',
      );
      expect(resolved.ceiling, isNull);
      expect(resolved.error, contains('explicit permissions'));
    });
  });

  group('negative fixture contracts', () {
    test('zz_new_caller read-all → publish fails over-request (M2)', () {
      final path =
          '$repoRoot/tool/contracts/fixtures/release_workflow_caller/negative_zz_new_caller.yml';
      final errors = validateBinaryReusableCallerYaml(
        File(path).readAsStringSync(),
        'negative_zz_new_caller.yml',
        repoRoot: repoRoot,
      );
      expect(
        errors.any((e) => e.contains('permission over-request') && e.contains('contents')),
        isTrue,
        reason: errors.join('; '),
      );
    });
  });
}