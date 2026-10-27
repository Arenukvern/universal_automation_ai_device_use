import 'package:test/test.dart';
import 'package:universal_automation_harness/universal_automation_harness.dart';
import 'package:universal_automation_toolkit/compose.dart';

CommandSpec _spec({int revision = 1, List<CommandParam>? params}) =>
    CommandSpec(
      name: 'fill-email',
      revision: revision,
      params:
          params ??
          [
            const CommandParam('text', type: 'string', required: true),
            const CommandParam('submit', type: 'bool', defaultValue: true),
          ],
      build: (args) => [
        typeText(args.string('text'), css: '#email', submit: args.flag('submit')),
      ],
    );

void main() {
  test('revision hash is stable and moves with the declared surface', () {
    final first = _spec();
    final second = _spec();
    expect(first.revisionHash, second.revisionHash);
    expect(first.revisionHash, hasLength(16));

    final bumped = _spec(revision: 2);
    expect(bumped.revisionHash, isNot(first.revisionHash));

    final reshaped = _spec(
      params: [
        const CommandParam('text', type: 'string', required: true),
        const CommandParam('submit', type: 'bool', defaultValue: false),
      ],
    );
    expect(reshaped.revisionHash, isNot(first.revisionHash));
  });

  test('duplicate command names fail the registry at construction', () {
    expect(
      () => CommandRegistry([_spec(), _spec()]),
      throwsFormatException,
    );
  });

  test('declaration violations name the offending param', () {
    final registry = CommandRegistry([
      CommandSpec(
        name: 'broken',
        revision: 1,
        params: [
          const CommandParam('a', type: 'blob'),
          const CommandParam('a', type: 'string'),
          CommandParam(
            'b',
            type: 'int',
            defaultValue: 'nope',
          ),
        ],
        build: (_) => [],
      ),
    ]);
    expect(registry.declarationViolations, hasLength(3));
    expect(registry.declarationViolations.first, contains('"broken"'));
  });

  test('expand applies session and soft to the built steps', () {
    final registry = CommandRegistry([_spec()]);
    final (steps, violations) = registry.expand(
      const CommandRef('fill-email', args: {'text': 'a@b.c'}, soft: true),
    );
    expect(violations, isEmpty);
    expect(steps, hasLength(1));
    expect(steps.single.continueOnFailure, isTrue);
  });

  test('expand collects every codec violation at once', () {
    final registry = CommandRegistry([_spec()]);
    final (steps, violations) = registry.expand(
      const CommandRef('fill-email', args: {
        'submit': 'yes',
        'extra': 1,
      }),
    );
    expect(steps, isEmpty);
    expect(violations, hasLength(3));
    expect(violations, everyElement(contains('fill-email')));
  });

  test('expand rejects nested command references', () {
    final registry = CommandRegistry([
      CommandSpec(
        name: 'outer',
        revision: 1,
        build: (args) => [const CommandRef('fill-email')],
      ),
    ]);
    final (steps, violations) = registry.expand(const CommandRef('outer'));
    expect(steps, isEmpty);
    expect(violations.single, contains('nested command reference'));
  });

  test('uri params parse string forms at validation', () {
    Uri? parsed;
    final registry = CommandRegistry([
      CommandSpec(
        name: 'go',
        revision: 1,
        params: [const CommandParam('url', type: 'uri', required: true)],
        build: (args) {
          parsed = args.uri('url');
          return [];
        },
      ),
    ]);
    final (steps, violations) = registry.expand(
      const CommandRef('go', args: {'url': 'https://example.com'}),
    );
    expect(violations, isEmpty);
    expect(steps, isEmpty);
    expect(parsed, Uri.parse('https://example.com'));
  });
}
