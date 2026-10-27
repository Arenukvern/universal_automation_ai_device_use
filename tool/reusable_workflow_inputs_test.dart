import 'dart:io';

import 'package:test/test.dart';

import 'reusable_workflow_inputs_lib.dart';

void main() {
  group('parseWorkflowCallInputs', () {
    test('reads workflow_call input names', () {
      final yaml = File('tool/testdata/reusable_publish_workflow.yml')
          .readAsStringSync();
      expect(
        parseWorkflowCallInputs(yaml),
        {'environment', 'working-directory'},
      );
    });
  });

  group('extractReusableCalls', () {
    test('extracts slug and with keys', () {
      final yaml = File('tool/testdata/caller_valid.yml').readAsStringSync();
      final calls = extractReusableCalls(yaml, 'caller_valid.yml');
      expect(calls, hasLength(1));
      expect(calls.single.slug,
          'dart-lang/setup-dart/.github/workflows/publish.yml@v1');
      expect(calls.single.withKeys, ['working-directory']);
      expect(calls.single.jobName, 'publish');
    });
  });

  group('validateWithKeysAgainstDeclared', () {
    late ReusableWorkflowCall call;
    late Set<String> declared;

    setUp(() {
      declared = parseWorkflowCallInputs(
        File('tool/testdata/reusable_publish_workflow.yml').readAsStringSync(),
      );
      call = extractReusableCalls(
        File('tool/testdata/caller_valid.yml').readAsStringSync(),
        'caller_valid.yml',
      ).single;
    });

    test('accepts declared keys', () {
      expect(validateWithKeysAgainstDeclared(call, declared), isEmpty);
    });

    test('reports undeclared keys', () {
      final bad = extractReusableCalls(
        File('tool/testdata/caller_invalid.yml').readAsStringSync(),
        'caller_invalid.yml',
      ).single;
      final errors = validateWithKeysAgainstDeclared(bad, declared);
      expect(errors, hasLength(1));
      expect(errors.single, contains('use-flutter'));
      expect(errors.single, contains('undeclared input'));
    });
  });

  group('fetchReusableWorkflowYaml', () {
    final call = ReusableWorkflowCall(
      callerPath: 'x.yml',
      jobName: 'publish',
      owner: 'dart-lang',
      repo: 'setup-dart',
      workflowFile: 'publish.yml',
      ref: 'v1',
      withKeys: ['working-directory'],
    );

    test('does not retry 4xx client errors', () async {
      var attempts = 0;
      await expectLater(
        fetchReusableWorkflowYaml(
          call,
          testResponseProvider: (_) async {
            attempts++;
            return (statusCode: 404, body: '');
          },
        ),
        throwsA(
          isA<WorkflowFetchException>()
              .having((e) => e.retryable, 'retryable', isFalse)
              .having((e) => e.message, 'message', contains('HTTP 404')),
        ),
      );
      expect(attempts, 1);
    });

    test('retries 5xx then succeeds', () async {
      var attempts = 0;
      final yaml =
          File('tool/testdata/reusable_publish_workflow.yml').readAsStringSync();
      final body = await fetchReusableWorkflowYaml(
        call,
        testResponseProvider: (_) async {
          attempts++;
          if (attempts < 2) {
            return (statusCode: 503, body: '');
          }
          return (statusCode: 200, body: yaml);
        },
      );
      expect(body, yaml);
      expect(attempts, 2);
    });
  });

  group('validateRepositoryWorkflows', () {
    test('propagates fetch failure instead of empty declared inputs', () async {
      final dir = Directory.systemTemp.createTempSync('rw_inputs_test');
      File('${dir.path}/caller.yml').writeAsStringSync(
        File('tool/testdata/caller_invalid.yml').readAsStringSync(),
      );

      expect(
        () => validateRepositoryWorkflows(
          workflowDirectory: dir,
          fetchYaml: (_) async {
            throw WorkflowFetchException(
              'could not fetch dart-lang/setup-dart/.github/workflows/publish.yml@v1',
            );
          },
        ),
        throwsA(
          isA<WorkflowFetchException>().having(
            (e) => e.message,
            'message',
            contains('could not fetch'),
          ),
        ),
      );

      dir.deleteSync(recursive: true);
    });
  });
}
