import 'package:test/test.dart';
import 'package:universal_automation_harness/universal_automation_harness.dart';
import 'package:universal_automation_toolkit/compose.dart';

final _fillEmail = CommandSpec(
  name: 'fill-email',
  revision: 3,
  params: [
    const CommandParam('text', type: 'string', required: true, doc: 'address'),
  ],
  build:
      (args) => [typeText(args.string('text'), css: '#email', submit: true)],
);

AutomationAssembly _assembly() => AutomationAssembly(
  sessions: [cdp('web', uri: Uri.parse('http://127.0.0.1:9222'))],
  commands: [_fillEmail],
  flows: [
    Flow(
      'cart',
      session: 'web',
      steps: [
        navigate(Uri.parse('https://example.com/cart')),
        waitFor([exists(role: 'button', name: 'Checkout')]),
      ],
    ),
    Flow(
      'checkout',
      extend: 'cart',
      steps: [
        runCommand('fill-email', args: {'text': 'a@b.c'}),
        verifyThat([absent(name: 'Error')]),
      ],
    ),
  ],
  budgets: const ServeBudgets(maxConcurrentJobs: 2, jobTimeout: Duration(minutes: 5)),
);

void main() {
  test('compile expands commands and the extends chain in order', () {
    final plan = _assembly().compile();
    expect(plan.scenarios, containsPair('checkout', isNotNull));
    final steps = plan.effectiveSteps('checkout');
    expect(
      steps.map((step) => step.kind),
      ['act', 'wait', 'act', 'verify'],
    );
    final commandStep = steps[2] as ActStep;
    expect(commandStep.session, 'web');
    expect(commandStep.action, isA<TypeAction>());
  });

  test('compile fails closed with every violation at once', () {
    final assembly = AutomationAssembly(
      sessions: [cdp('web', uri: Uri.parse('http://127.0.0.1:9222'))],
      commands: [
        CommandSpec(
          name: 'broken',
          revision: 1,
          params: [const CommandParam('x', type: 'blob', required: true)],
          build: (_) => [],
        ),
      ],
      flows: [
        Flow('cart', steps: []),
        Flow(
          'cart',
          steps: [runCommand('broken', args: {'nope': 1})],
        ),
        Flow(
          'loop',
          extend: 'loop',
          steps: [],
        ),
        Flow('orphan', extend: 'ghost', steps: []),
      ],
      budgets: const ServeBudgets(maxConcurrentJobs: 0),
    );
    late final SpecViolationException error;
    try {
      assembly.compile();
      fail('expected compile to refuse');
    } on SpecViolationException catch (caught) {
      error = caught;
    }
    final text = error.violations.join('\n');
    expect(text, contains('flow "cart" declared twice'));
    expect(text, contains('scenario "cart" declared twice'));
    expect(text, contains('unknown type "blob"'));
    expect(text, contains('unknown param "nope"'));
    expect(text, contains('missing required param "x"'));
    expect(text, contains('maxConcurrentJobs'));
  });

  test('chain violations surface with the plan shape intact', () {
    final assembly = AutomationAssembly(
      sessions: [cdp('web', uri: Uri.parse('http://127.0.0.1:9222'))],
      flows: [
        Flow('loop', extend: 'loop', steps: []),
        Flow('orphan', extend: 'ghost', steps: []),
      ],
    );
    try {
      assembly.compile();
      fail('expected compile to refuse');
    } on SpecViolationException catch (error) {
      final text = error.violations.join('\n');
      expect(text, contains('extends cycle'));
      expect(text, contains('extends unknown scenario "ghost"'));
    }
  });

  test('compile catches toolkit-level violations over the expanded shape',
      () {
    final assembly = AutomationAssembly(
      sessions: [cdp('web', uri: Uri.parse('http://127.0.0.1:9222'))],
      flows: [
        Flow('two', steps: [navigate(Uri.parse('https://example.com'), session: 'ghost')]),
      ],
    );
    expect(
      () => assembly.compile(),
      throwsA(
        isA<SpecViolationException>().having(
          (error) => error.violations.join(),
          'violations',
          contains('unknown session "ghost"'),
        ),
      ),
    );
  });

  test('snapshot matches the compiled plan document', () {
    final assembly = _assembly();
    expect(assembly.snapshot(), assembly.compile().toJson());
  });

  test('snapshot refuses Dart-only code steps', () {
    final assembly = AutomationAssembly(
      sessions: [cdp('web', uri: Uri.parse('http://127.0.0.1:9222'))],
      flows: [
        Flow('with-code', steps: [code((context) async => {'ok': true})]),
      ],
    );
    expect(() => assembly.snapshot(), throwsA(isA<SpecViolationException>()));
  });

  test('explain is deterministic and carries command identity', () {
    final first = _assembly().explain();
    final second = _assembly().explain();
    expect(first, second);
    expect(first, contains('fill-email@3'));
    expect(first, contains('hash ${_fillEmail.revisionHash}'));
    expect(first, contains('maxConcurrentJobs=2'));
    expect(first, contains('checkout (extends cart)'));
    expect(first, contains('cart @web (2 steps: act, wait)'));
    expect(first, contains('command:fill-email'));
  });
}
