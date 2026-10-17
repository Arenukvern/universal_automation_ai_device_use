import 'package:universal_automation_toolkit/compose.dart';

import 'budgets.dart';
import 'command.dart';
import 'flow.dart';

/// A harness assembly: sessions, commands, flows, and budgets — the
/// component tree that compiles to one toolkit [AutomationPlan] artifact
/// (ADR 0004). Compile is pure and fails closed with every violation at
/// once; nothing attaches until the compiled plan runs.
final class AutomationAssembly {
  /// Declares an assembly. [commands] and [flows] are lists (order is
  /// declaration order for explain()); names must be unique.
  const AutomationAssembly({
    required this.sessions,
    this.profiles = const {},
    this.intents,
    this.commands = const [],
    this.flows = const [],
    this.budgets,
  });

  /// Attach-only session bindings.
  final List<SessionBinding> sessions;

  /// Named behavior profiles (ADR 0044) referenced by steps.
  final Map<String, BehaviorProfile> profiles;

  /// The assembly's intent surface (ADR 0038), when any.
  final IntentRegistry? intents;

  /// Versioned commands flows may reference.
  final List<CommandSpec> commands;

  /// The flows; each compiles to a scenario.
  final List<Flow> flows;

  /// Budgets for the serving side (enforced by [BudgetGuard] and the
  /// runner deadline); they travel in explain() and receipts, never in
  /// the compiled plan — budgets bound the harness, not the scenario.
  final ServeBudgets? budgets;

  /// Compiles to the plan artifact. Violations — duplicate flow names,
  /// unknown extends or command references, codec failures, declaration
  /// errors — are collected all together and thrown as one
  /// [SpecViolationException]; the toolkit's own cross-step validation
  /// runs last over the expanded shape.
  ///
  /// Command references expand at compile time, so CLI, serve, and an
  /// in-app agent execute the identical steps from the identical
  /// artifact; Dart stays the source of truth.
  AutomationPlan compile() {
    final violations = [
      ..._registry.declarationViolations,
      if (budgets != null)
        for (final violation in budgets!.validate())
          'budget: $violation',
    ];
    final seenFlows = <String>{};
    for (final flow in flows) {
      if (!seenFlows.add(flow.name)) {
        violations.add('flow "${flow.name}" declared twice');
      }
    }
    final expandedSteps = <String, List<PlanStep>>{};
    for (final flow in flows) {
      final (steps, flowViolations) = _expandFlow(
        flow,
        effectiveSession: _effectiveSession(flow),
      );
      expandedSteps[flow.name] = steps;
      violations.addAll([
        for (final violation in flowViolations) 'flow "${flow.name}": $violation',
      ]);
    }
    // The plan is built and validated even when expansion already found
    // violations, so chain errors (cycles, unknown extends, unknown
    // sessions) surface in the same list — never one bad step hiding the
    // rest. Construction throws only on duplicate session/scenario
    // names; its message folds in beside the assembly's own.
    AutomationPlan? plan;
    try {
      plan = AutomationPlan(
        sessions: sessions,
        profiles: profiles,
        intents: intents,
        scenarios: [
          for (final flow in flows)
            flow.toScenario(expandedSteps[flow.name] ?? const []),
        ],
      );
      violations.addAll(plan.validate());
    } on SpecViolationException catch (error) {
      violations.addAll(error.violations);
    }
    if (violations.isNotEmpty) {
      throw SpecViolationException(violations);
    }
    return plan!;
  }

  CommandRegistry get _registry => CommandRegistry(commands);

  /// The nearest declared session default in the extends chain (a flow
  /// without one inherits its parent's; no ancestor declares → null and
  /// the toolkit's single-session rule applies).
  String? _effectiveSession(Flow flow) {
    var cursor = flow;
    final visited = <String>{};
    while (cursor.session == null) {
      if (!visited.add(cursor.name) || cursor.extend == null) return null;
      final parent = flows
          .where((entry) => entry.name == cursor.extend)
          .firstOrNull;
      if (parent == null) return null;
      cursor = parent;
    }
    return cursor.session;
  }

  (List<PlanStep>, List<String>) _expandFlow(
    Flow flow, {
    required String? effectiveSession,
  }) {
    final violations = <String>[];
    final steps = <PlanStep>[];
    // Only the flow's OWN steps expand here; the extends chain stays on
    // the compiled Scenario and the toolkit's effectiveSteps owns chain
    // semantics (order, cycles, unknown parents) — one source of truth,
    // never a parallel vocabulary.
    for (final step in flow.steps) {
      switch (step) {
        case CommandRef():
          final (expanded, refViolations) = _registry.expand(step);
          violations.addAll(refViolations);
          steps.addAll([
            for (final expandedStep in expanded)
              effectiveSession != null && expandedStep.session == null
                  ? expandedStep.withCommon(
                      session: effectiveSession,
                      continueOnFailure: expandedStep.continueOnFailure,
                    )
                  : expandedStep,
          ]);
        case final PlanStep planStep:
          steps.add(
            planStep.withCommon(
              session: effectiveSession ?? planStep.session,
              continueOnFailure: planStep.continueOnFailure,
            ),
          );
        default:
          violations.add(
            'step tree holds a non-step (${step.runtimeType})',
          );
      }
    }
    return (steps, violations);
  }

  /// The compiled plan's snapshot (wire) form for agents and MCP clients.
  /// Refuses Dart-only code steps, exactly like the toolkit's export.
  Map<String, Object?> snapshot() => planDocument(compile());

  /// Deterministic, human-readable assembly text: sessions, commands with
  /// revision identity and hashes, budgets, flows with step kinds.
  String explain() {
    final lines = <String>['# universal automation assembly'];
    lines.add('sessions:');
    for (final session in sessions) {
      final location = session.uri?.toString() ??
          (session.handle == null ? '' : 'handle:${session.handle}');
      lines.add('  - ${session.name} (${session.transport.name}, $location)');
    }
    if (commands.isNotEmpty) {
      lines.add('commands:');
      for (final command in commands) {
        final params = command.params.isEmpty
            ? ''
            : ' params: ${[
                for (final param in command.params)
                  '${param.name}:${param.type}'
                  '${param.required ? '!' : ''}',
              ].join(', ')}';
        lines.add(
          '  - ${command.id} (hash ${command.revisionHash})$params',
        );
      }
    }
    if (budgets != null) {
      lines.add('budgets: ${budgets!.toString()}');
    }
    lines.add('flows:');
    for (final flow in flows) {
      final kinds = [
        for (final step in flow.steps)
          step is CommandRef
              ? 'command:${step.name}'
              : (step as PlanStep).kind,
      ];
      lines.add(
        '  - ${flow.name}'
        '${flow.extend == null ? '' : ' (extends ${flow.extend})'}'
        '${flow.session == null ? '' : ' @${flow.session}'} '
        '(${kinds.length} steps: ${kinds.join(', ')})',
      );
    }
    return lines.join('\n');
  }
}
