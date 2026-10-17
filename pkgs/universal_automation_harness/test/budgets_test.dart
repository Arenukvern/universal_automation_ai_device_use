import 'package:test/test.dart';
import 'package:universal_automation_harness/universal_automation_harness.dart';

void main() {
  test('budget declarations validate negative and zero shapes', () {
    expect(const ServeBudgets().validate(), isEmpty);
    expect(
      const ServeBudgets(maxConcurrentJobs: 0).validate(),
      everyElement(contains('maxConcurrentJobs')),
    );
    expect(
      const ServeBudgets(jobTimeout: Duration()).validate(),
      everyElement(contains('jobTimeout')),
    );
    expect(
      const ServeBudgets(idleExit: Duration(seconds: -1)).validate(),
      everyElement(contains('idleExit')),
    );
  });

  test('the guard refuses admission while the concurrency budget is full',
      () {
    final guard = BudgetGuard(const ServeBudgets(maxConcurrentJobs: 1));
    expect(guard.tryAcquire(), isTrue);
    expect(guard.tryAcquire(), isFalse);
    guard.release();
    expect(guard.activeRuns, 0);
    expect(guard.tryAcquire(), isTrue);
  });

  test('an unbudgeted guard admits everything and never exits', () {
    final guard = BudgetGuard(const ServeBudgets());
    expect(guard.tryAcquire(), isTrue);
    expect(guard.deadlineFor(DateTime.now()), isNull);
    expect(guard.shouldExit, isFalse);
    expect(guard.exitReasons(), isEmpty);
  });

  test('deadlineFor anchors the job timeout at the run start', () {
    final guard = BudgetGuard(
      const ServeBudgets(jobTimeout: Duration(minutes: 5)),
      startedAt: DateTime(2026, 1, 1),
    );
    final deadline = guard.deadlineFor(DateTime(2026, 1, 1, 12));
    expect(deadline, DateTime(2026, 1, 1, 12, 5));
  });

  test('idle and lifetime exit signals report their reasons', () {
    final atNoon = DateTime(2026, 1, 1, 12);
    final idleGuard = BudgetGuard(
      const ServeBudgets(idleExit: Duration(hours: 1)),
      startedAt: atNoon,
      lastActivity: atNoon.subtract(const Duration(hours: 2)),
    );
    expect(idleGuard.shouldExit, isTrue);
    expect(idleGuard.exitReasons().single, contains('idle for'));

    final lifetimeGuard = BudgetGuard(
      const ServeBudgets(maxSessionRuntime: Duration(hours: 4)),
      startedAt: atNoon.subtract(const Duration(hours: 5)),
    );
    expect(lifetimeGuard.shouldExit, isTrue);
    expect(lifetimeGuard.exitReasons().single, contains('session runtime'));
  });

  test('activity resets the idle clock and status carries the shape', () {
    final atNoon = DateTime(2026, 1, 1, 12);
    final guard = BudgetGuard(
      const ServeBudgets(idleExit: Duration(hours: 1)),
      startedAt: atNoon,
      lastActivity: atNoon.subtract(const Duration(hours: 2)),
    );
    expect(guard.shouldExit, isTrue);
    guard.tryAcquire();
    expect(guard.shouldExit, isFalse);
    guard.release();
    expect(guard.shouldExit, isFalse);

    final status = guard.status();
    expect(status['activeRuns'], 0);
    expect(status['shouldExit'], isFalse);
    expect(
      (status['budgets'] as Map<String, Object?>)['idleExitMs'],
      Duration(hours: 1).inMilliseconds,
    );
  });

  test('invalid budgets fail the guard closed', () {
    final guard = BudgetGuard(const ServeBudgets(maxConcurrentJobs: 0));
    expect(guard.shouldExit, isTrue);
    expect(guard.exitReasons().single, contains('invalid budget'));
  });
}
