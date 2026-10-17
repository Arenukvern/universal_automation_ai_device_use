/// The composition-root SDK over the universal automation toolkit
/// (ADR 0004): component-shaped authoring that compiles to one
/// [AutomationPlan] artifact.
///
/// One vocabulary, no parallel Darts: flows, commands, and budgets lower
/// to the toolkit's plan model — CLI, serve, and an in-app agent execute
/// the identical compiled artifact. Dart is the source of truth;
/// snapshots ([AutomationAssembly.snapshot]) are the agent interchange.
///
/// ```dart
/// final assembly = AutomationAssembly(
///   sessions: [cdp('web', uri: Uri.parse('http://127.0.0.1:9222'))],
///   commands: [fillEmail],
///   flows: [
///     Flow('checkout', session: 'web', steps: [
///       navigate(Uri.parse('https://example.com/cart')),
///       runCommand('fill-email', args: {'text': 'a@b.c'}),
///       waitFor([exists(role: 'button', name: 'Checkout')]),
///     ]),
///   ],
///   budgets: const ServeBudgets(maxConcurrentJobs: 2, jobTimeout: Duration(minutes: 5)),
/// );
/// final plan = assembly.compile(); // fail closed, all violations at once
/// ```
///
/// Oka relation: components are structurally compatible with
/// `resource_composition` values (ADR 0004); this package depends on the
/// toolkit, not on oka — the embedding adapter lives at the composition
/// root, so the vocabulary is never forked.
library;

export 'src/assembly.dart';
export 'src/budgets.dart';
export 'src/command.dart';
export 'src/envelope.dart';
export 'src/flow.dart';
export 'src/runner.dart';
