import 'package:meta/meta.dart';
import 'package:universal_automation_toolkit/compose.dart';

/// One named flow: a component-shaped scenario tree that compiles to a
/// toolkit [Scenario].
///
/// [session] is the flow's default binding — every step without an
/// explicit session lowers to it at compile time (the tree-shaped form of
/// `onSession`). [extend] names a parent flow whose steps run first, and
/// must resolve inside the same assembly (fail closed).
final class Flow {
  /// Creates a flow; [steps] may embed [runCommand] references, expanded
  /// by the owning assembly at compile time.
  const Flow(this.name, {this.extend, this.session, this.steps = const []});

  /// Stable, unique within an assembly.
  final String name;

  /// Parent flow whose steps run first, when extending.
  final String? extend;

  /// Default session for steps that name none.
  final String? session;

  /// This flow's own steps (after the parent's, when extending).
  final List<Object> steps;

  /// A child flow whose steps run after this one's.
  Flow extendWith(String name, {List<Object> steps = const []}) =>
      Flow(name, extend: this.name, steps: List.of(steps));

  /// Lowers to the toolkit scenario shape; command references must be
  /// expanded first ([AutomationAssembly.compile] does that).
  @internal
  Scenario toScenario(List<PlanStep> expanded) =>
      Scenario(name: name, parent: extend, steps: List.of(expanded));
}

/// A command invocation embedded in a [Flow.steps] tree; the assembly
/// expands it against the pinned [CommandSpec] at compile time (never at
/// runtime), so every face executes identical steps.
final class CommandRef {
  /// References command [name] with raw [args] (validated against the
  /// spec's declared parameters — unknown, missing, or mis-typed values
  /// are compile-time violations).
  const CommandRef(
    this.name, {
    this.args = const {},
    this.session,
    this.soft = false,
  });

  final String name;
  final Map<String, Object?> args;

  /// Overrides the flow's default session for the expanded steps.
  final String? session;

  /// Marks every expanded step continue-on-failure.
  final bool soft;
}

/// Declares a command invocation inside a flow tree.
CommandRef runCommand(
  String name, {
  Map<String, Object?> args = const {},
  String? session,
  bool soft = false,
}) => CommandRef(name, args: args, session: session, soft: soft);
