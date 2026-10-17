import 'package:universal_automation_toolkit/universal_automation_toolkit.dart';

import 'budgets.dart';

/// The toolkit [PlanRunner] behind a budget guard: concurrency admission
/// before the run starts, a per-run deadline handed to the runner (enforced
/// at step boundaries), and activity fed back to the guard so an embedder's
/// idle-exit loop has honest signal.
///
/// The guard never spawns or stops anything (attach-only house rule); it
/// only admits, bounds, and reports.
final class HarnessRunner {
  /// Wraps [runner] (default: an unconfigured [PlanRunner]) with [guard].
  HarnessRunner({required BudgetGuard guard, PlanRunner? runner})
    : _guard = guard,
      _runner = runner ?? PlanRunner();

  final BudgetGuard _guard;
  final PlanRunner _runner;

  /// The wrapped runner, for composition roots that need to register
  /// factories before the first run.
  PlanRunner get runner => _runner;

  /// The guard, for status and exit polling.
  BudgetGuard get guard => _guard;

  /// Runs [scenarioName] under the guard: refuses with
  /// [BudgetExceededException] while the concurrency budget is exhausted,
  /// bounds the run with the guard's deadline, releases on the way out.
  Future<RunReport> run(
    AutomationPlan plan, {
    String? scenarioName,
    Map<String, String> sessionOverrides = const {},
    String? outDir,
  }) async {
    if (!_guard.tryAcquire()) {
      throw BudgetExceededException(
        'run refused: maxConcurrentJobs=${_guard.budgets.maxConcurrentJobs} '
        'with ${_guard.activeRuns} active',
        details: _guard.status(),
      );
    }
    try {
      return await _runner.run(
        plan,
        scenarioName: scenarioName,
        sessionOverrides: sessionOverrides,
        outDir: outDir,
        deadline: _guard.deadlineFor(DateTime.now()),
      );
    } finally {
      _guard.release();
    }
  }
}
