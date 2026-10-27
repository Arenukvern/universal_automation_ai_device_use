import 'package:test/test.dart';
import 'package:universal_automation_harness/universal_automation_harness.dart';
import 'package:universal_automation_toolkit/compose.dart';

AutomationPlan _plan() => AutomationAssembly(
  sessions: [cdp('web', handle: 'browser')],
  flows: [
    Flow(
      'three',
      session: 'web',
      steps: [
        waitFor([exists(role: 'button', name: 'One')]),
        waitFor([exists(role: 'button', name: 'Two')]),
      ],
    ),
  ],
).compile();

void main() {
  test('the guard refuses a run while the concurrency budget is exhausted',
      () {
    final guard = BudgetGuard(const ServeBudgets(maxConcurrentJobs: 1));
    guard.tryAcquire(); // simulates another run in flight
    final runner = HarnessRunner(guard: guard);
    expect(
      runner.run(_plan()),
      throwsA(
        isA<BudgetExceededException>().having(
          (error) => error.kind,
          'kind',
          'budget',
        ),
      ),
    );
    guard.release();
  });

  test('a run is admitted, accounted, and released', () async {
    final guard = BudgetGuard(const ServeBudgets(jobTimeout: Duration(hours: 1)));
    final runner = HarnessRunner(guard: guard);
    // No CDP endpoint exists behind the `browser` handle in this test
    // process: the first step fails on attach, the deadline never fires —
    // the point is admission, the guard's accounting, and the release.
    final report = await runner.run(_plan());
    expect(report.ok, isFalse);
    expect(report.steps.first.errorKind, 'endpointUnreachable');
    expect(guard.activeRuns, 0);
    expect(guard.shouldExit, isFalse);
  });
}
