import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_automation_harness/universal_automation_harness.dart';

void main() {
  test('envelopes round-trip and validate their fields', () {
    const envelope = RuleEnvelope(
      id: 'automation.fail-closed',
      kind: RuleKind.rule,
      content: 'Every plan violation is reported before anything runs.',
      source: 'realm commons',
    );
    final restored = RuleEnvelope.fromJson(envelope.toJson());
    expect(restored.id, envelope.id);
    expect(restored.kind, RuleKind.rule);
    expect(restored.content, envelope.content);
    expect(restored.source, envelope.source);
  });

  test('malformed envelopes fail loudly naming the field', () {
    expect(
      () => RuleEnvelope.fromJson({'kind': 'rule', 'content': 'x', 'source': 's'}),
      throwsA(isA<FormatException>().having(
        (error) => error.message,
        'message',
        contains('"id"'),
      )),
    );
    expect(
      () => RuleEnvelope.fromJson({
        'id': 'a',
        'kind': 'decree',
        'content': 'x',
        'source': 's',
      }),
      throwsA(isA<FormatException>().having(
        (error) => error.message,
        'message',
        contains('kind'),
      )),
    );
    expect(
      () => RuleEnvelope.fromJson({'id': 'a', 'kind': 'rule', 'source': 's'}),
      throwsFormatException,
    );
    expect(
      () => RuleEnvelope.fromJson({'id': 'a', 'kind': 'rule', 'content': 'x'}),
      throwsA(isA<FormatException>().having(
        (error) => error.message,
        'message',
        contains('"source"'),
      )),
    );
  });

  test('loadRuleEnvelopes stamps sources and refuses duplicate ids', () {
    final dir = Directory.systemTemp.createTempSync('harness-envelope');
    addTearDown(() => dir.deleteSync(recursive: true));
    final first = File('${dir.path}/rules.json')..writeAsStringSync(
      jsonEncode({
        'id': 'automation.fail-closed',
        'kind': 'rule',
        'content': 'Fail closed.',
      }),
    );
    final second = File('${dir.path}/guides.json')..writeAsStringSync(
      jsonEncode([
        {
          'id': 'automation.semantic-first',
          'kind': 'guide',
          'content': 'Observe through a view before acting.',
        },
        {
          'id': 'automation.fail-closed',
          'kind': 'rule',
          'content': 'Duplicate id inside the bundle.',
        },
      ]),
    );
    expect(
      () => loadRuleEnvelopes([first.path, second.path]),
      throwsA(isA<FormatException>().having(
        (error) => error.message,
        'message',
        contains('declared twice'),
      )),
    );

    final envelopes = loadRuleEnvelopes([first.path, second.path].take(1));
    expect(envelopes.single.source, first.path);
    expect(envelopes.single.kind, RuleKind.rule);
  });
}
