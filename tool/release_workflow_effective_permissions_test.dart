import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'release_workflow_contract_lib.dart';

void main() {
  group('effective contents: production caller → callee jobs', () {
    test('release-please build reusable (all jobs read)', () {
      const caller = 'read';
      const workflow = 'read';
      for (final job in ['prepare', 'build', 'dry-run-bundle']) {
        expect(
          effectiveContentsPermission(
            callerContents: caller,
            workflowContents: workflow,
            jobContents: null,
          ),
          'read',
          reason: 'build.$job',
        );
      }
    });

    test('release-please publish reusable (publish write, postflight read)', () {
      const caller = 'write';
      const workflow = 'read';
      expect(
        effectiveContentsPermission(
          callerContents: caller,
          workflowContents: workflow,
          jobContents: 'write',
        ),
        'write',
        reason: 'publish.publish',
      );
      expect(
        effectiveContentsPermission(
          callerContents: caller,
          workflowContents: workflow,
          jobContents: 'read',
        ),
        'read',
        reason: 'publish.postflight',
      );
    });

    test('manual dispatch matches please train grants', () {
      expect(
        effectiveContentsPermission(
          callerContents: 'read',
          workflowContents: 'read',
          jobContents: null,
        ),
        'read',
      );
      expect(
        effectiveContentsPermission(
          callerContents: 'write',
          workflowContents: 'read',
          jobContents: 'write',
        ),
        'write',
      );
    });
  });

  test('golden caller YAML grants align with contract (table)', () {
    final please = loadYaml(
      r'''
release-binaries-build:
  permissions:
    contents: read
release-binaries-publish:
  permissions:
    contents: write
''',
    ) as Map;
    final dispatch = loadYaml(
      r'''
build:
  permissions:
    contents: read
publish:
  permissions:
    contents: write
''',
    ) as Map;

  final table = <Map<String, String>>[
    {
      'path': 'release-please → build → prepare',
      'effective':
          effectiveContentsPermission(callerContents: 'read', workflowContents: 'read', jobContents: null),
    },
    {
      'path': 'release-please → build → build',
      'effective':
          effectiveContentsPermission(callerContents: 'read', workflowContents: 'read', jobContents: null),
    },
    {
      'path': 'release-please → publish → publish',
      'effective': effectiveContentsPermission(
        callerContents: please['release-binaries-publish']['permissions']['contents'].toString(),
        workflowContents: 'read',
        jobContents: 'write',
      ),
    },
    {
      'path': 'release-please → publish → postflight',
      'effective': effectiveContentsPermission(
        callerContents: please['release-binaries-publish']['permissions']['contents'].toString(),
        workflowContents: 'read',
        jobContents: 'read',
      ),
    },
    {
      'path': 'release_binaries.yml → build → prepare',
      'effective':
          effectiveContentsPermission(callerContents: 'read', workflowContents: 'read', jobContents: null),
    },
    {
      'path': 'release_binaries.yml → publish → publish',
      'effective': effectiveContentsPermission(
        callerContents: dispatch['publish']['permissions']['contents'].toString(),
        workflowContents: 'read',
        jobContents: 'write',
      ),
    },
    {
      'path': 'release_binaries.yml → publish → postflight',
      'effective': effectiveContentsPermission(
        callerContents: dispatch['publish']['permissions']['contents'].toString(),
        workflowContents: 'read',
        jobContents: 'read',
      ),
    },
  ];

    expect(
      table.every((row) =>
          row['path']!.contains('publish') && row['path']!.endsWith('publish')
              ? row['effective'] == 'write'
              : row['effective'] == 'read'),
      isTrue,
      reason: table.map((r) => '${r['path']}: ${r['effective']}').join('; '),
    );
  });
}