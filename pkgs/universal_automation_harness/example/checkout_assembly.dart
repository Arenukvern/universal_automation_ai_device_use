import 'package:universal_automation_harness/universal_automation_harness.dart';
import 'package:universal_automation_toolkit/compose.dart';

/// A checkout assembly: one versioned command, one flow that uses it,
/// budgets for the serving side. Compile, explain, then (with a live
/// CDP endpoint and `--run`) execute under the guard.
Future<void> main(List<String> args) async {
  final fillEmail = CommandSpec(
    name: 'fill-email',
    revision: 1,
    params: [
      const CommandParam(
        'text',
        type: 'string',
        required: true,
        doc: 'address',
      ),
      const CommandParam('submit', type: 'bool', defaultValue: true),
    ],
    doc: 'types an email into #email and submits',
    build: (args) => [
      typeText(args.string('text'), css: '#email', submit: args.flag('submit')),
    ],
  );

  final assembly = AutomationAssembly(
    sessions: [cdp('web', uri: Uri.parse('http://127.0.0.1:9222'))],
    commands: [fillEmail],
    flows: [
      Flow(
        'checkout',
        session: 'web',
        steps: [
          navigate(Uri.parse('https://example.com/cart')),
          runCommand('fill-email', args: {'text': 'a@b.c'}),
          waitFor([exists(role: 'button', name: 'Checkout')]),
          verifyThat([absent(name: 'Error')]),
        ],
      ),
    ],
    budgets: const ServeBudgets(
      maxConcurrentJobs: 2,
      jobTimeout: Duration(minutes: 5),
      idleExit: Duration(minutes: 10),
    ),
  );

  print(assembly.explain());
  final plan = assembly.compile();
  print('compiled scenarios: ${plan.scenarios.keys.join(', ')}');

  if (args.contains('--run')) {
    final runner = HarnessRunner(guard: BudgetGuard(assembly.budgets!));
    final report = await runner.run(plan);
    print('ok=${report.ok} steps=${report.steps.length}');
  }
}
