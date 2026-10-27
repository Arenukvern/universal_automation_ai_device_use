import 'package:universal_automation_interface/universal_automation_interface.dart';

/// Declared budgets for a harness session (the self-bounding serve,
/// ADR 0004 §4): the inside-the-process half of containment. The oka
/// supervisor owns the process (converge + budgeted restarts); these
/// budgets own what runs inside it.
final class ServeBudgets {
  /// Declares budgets; every field is optional — `null` means unbudgeted,
  /// which is a deliberate, visible choice (explain() prints it).
  const ServeBudgets({
    this.maxConcurrentJobs,
    this.jobTimeout,
    this.idleExit,
    this.maxSessionRuntime,
  });

  /// At most this many runs execute at once; further acquisitions wait
  /// ([BudgetGuard.tryAcquire] refuses while full).
  final int? maxConcurrentJobs;

  /// Wall-clock deadline per run, enforced at step boundaries by the
  /// runner (a single long step can overshoot; steps carry their own
  /// timeouts for the interior).
  final Duration? jobTimeout;

  /// Exit signal after this long without a run acquiring the guard —
  /// the embedder's event loop decides what "exit" is; the guard only
  /// says when.
  final Duration? idleExit;

  /// Exit signal once the guard has been alive this long.
  final Duration? maxSessionRuntime;

  /// Violations: negative or zero values, contradictory shapes.
  List<String> validate() => [
    if (maxConcurrentJobs != null && maxConcurrentJobs! < 1)
      'maxConcurrentJobs must be at least 1',
    for (final entry in {
      'jobTimeout': jobTimeout,
      'idleExit': idleExit,
      'maxSessionRuntime': maxSessionRuntime,
    }.entries)
      if (entry.value != null && entry.value! <= Duration.zero)
        '${entry.key} must be positive',
  ];

  /// Canonical shape (receipts, snapshots of the serving side).
  Map<String, Object?> toJson() => {
    if (maxConcurrentJobs != null) 'maxConcurrentJobs': maxConcurrentJobs,
    if (jobTimeout != null) 'jobTimeoutMs': jobTimeout!.inMilliseconds,
    if (idleExit != null) 'idleExitMs': idleExit!.inMilliseconds,
    if (maxSessionRuntime != null)
      'maxSessionRuntimeMs': maxSessionRuntime!.inMilliseconds,
  };

  @override
  String toString() {
    final parts = <String>[
      if (maxConcurrentJobs != null) 'maxConcurrentJobs=$maxConcurrentJobs',
      if (jobTimeout != null) 'jobTimeout=${jobTimeout!.inSeconds}s',
      if (idleExit != null) 'idleExit=${idleExit!.inSeconds}s',
      if (maxSessionRuntime != null)
        'maxSessionRuntime=${maxSessionRuntime!.inMinutes}min',
    ];
    return parts.isEmpty ? 'unbudgeted' : parts.join(', ');
  }
}

/// Raised when a run is refused because a budget is exhausted.
final class BudgetExceededException extends AutomationException {
  /// Creates the refusal; [details] names the budget and its bound.
  const BudgetExceededException(super.message, {super.details});

  @override
  String get kind => 'budget';
}

/// Enforces [ServeBudgets] at runtime: concurrency admission, per-run
/// deadlines, idle and lifetime exit signals. Pure value mechanics —
/// no threads, no timers of its own; the embedder polls [shouldExit].
final class BudgetGuard {
  /// Creates a guard over [budgets]; [startedAt] defaults to now and
  /// anchors [ServeBudgets.maxSessionRuntime]; [lastActivity] exists for
  /// deterministic tests of the idle signal (defaults to now, moves on
  /// every [tryAcquire]/[release]).
  BudgetGuard(this.budgets, {DateTime? startedAt, DateTime? lastActivity})
    : budgetsViolations = budgets.validate(),
      startedAt = startedAt ?? DateTime.now(),
      _lastActivity = lastActivity ?? DateTime.now();

  /// Declaration violations (the guard still enforces what is valid —
  /// the assembly refuses to compile with these, this field is for
  /// direct-embed diagnostics).
  final List<String> budgetsViolations;

  /// The declared budgets.
  final ServeBudgets budgets;

  /// When the guard session started.
  final DateTime startedAt;

  var _active = 0;
  var _lastActivity = DateTime.now();

  /// Currently executing runs.
  int get activeRuns => _active;

  /// Whether a run may start now: concurrency admission only. Callers
  /// pair every `true` with exactly one [release].
  bool tryAcquire() {
    final max = budgets.maxConcurrentJobs;
    if (max != null && _active >= max) return false;
    _active++;
    _lastActivity = DateTime.now();
    return true;
  }

  /// Records that one acquired run finished.
  void release() {
    if (_active > 0) _active--;
    _lastActivity = DateTime.now();
  }

  /// The deadline a run started at [now] must honor, or `null` when
  /// [ServeBudgets.jobTimeout] is unset. Passed to the runner, which
  /// fails the run at the next step boundary once it passes.
  DateTime? deadlineFor(DateTime? now) {
    final timeout = budgets.jobTimeout;
    if (timeout == null) return null;
    return (now ?? DateTime.now()).add(timeout);
  }

  /// Whether the embedding session should wind down: idle past
  /// [ServeBudgets.idleExit], lifetime past
  /// [ServeBudgets.maxSessionRuntime], or the budgets themselves were
  /// declared invalid (fail closed — an invalid budget is not a budget).
  bool get shouldExit {
    if (budgetsViolations.isNotEmpty) return true;
    final now = DateTime.now();
    final idle = budgets.idleExit;
    if (idle != null && now.difference(_lastActivity) >= idle) return true;
    final lifetime = budgets.maxSessionRuntime;
    if (lifetime != null && now.difference(startedAt) >= lifetime) {
      return true;
    }
    return false;
  }

  /// Why [shouldExit] holds, for receipts and loud logs; empty while
  /// the session may continue.
  List<String> exitReasons() {
    if (budgetsViolations.isNotEmpty) {
      return [
        for (final violation in budgetsViolations) 'invalid budget: $violation',
      ];
    }
    final now = DateTime.now();
    return [
      if (budgets.idleExit != null &&
          now.difference(_lastActivity) >= budgets.idleExit!)
        'idle for ${now.difference(_lastActivity).inSeconds}s '
            '(budget ${budgets.idleExit!.inSeconds}s)',
      if (budgets.maxSessionRuntime != null &&
          now.difference(startedAt) >= budgets.maxSessionRuntime!)
        'session runtime ${now.difference(startedAt).inMinutes}min exceeds '
            'budget ${budgets.maxSessionRuntime!.inMinutes}min',
    ];
  }

  /// Observability shape (receipts, health endpoints).
  Map<String, Object?> status() => {
    'budgets': budgets.toJson(),
    'activeRuns': _active,
    'startedAt': startedAt.toIso8601String(),
    'shouldExit': shouldExit,
  };
}
