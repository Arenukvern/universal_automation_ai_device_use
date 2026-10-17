# universal_automation_harness

The composition-root SDK over the
[universal automation toolkit](../universal_automation_toolkit) (ADR 0004):
component-shaped authoring that compiles to **one** `AutomationPlan`
artifact — the identical artifact the CLI, the MCP serve face, and an
in-app agent execute. Dart is the source of truth; snapshots are the
agent interchange.

One vocabulary, no parallel Darts: this package depends on the toolkit
and the interface, never redefines them. The relation to oka's
`resource_composition` is recorded in ADR 0004 — components here are
structurally compatible with its `Component` values; the hosted
dependency flips when that package publishes (the assembly/validation
vocabulary in this package is automation-specific, so nothing forks).

## What's here

- **`AutomationAssembly`** — sessions, commands, flows, budgets. `compile()`
  is pure and fails closed with every violation at once; command
  references expand at compile time so every face runs identical steps.
  `snapshot()` exports the agent wire form (refuses Dart-only code
  steps); `explain()` renders deterministic assembly text.
- **`Flow`** — a named scenario tree with a session default that inherits
  down the `extend` chain. The toolkit's `effectiveSteps` owns chain
  semantics (order, cycles, unknown parents); the harness expands only a
  flow's own steps.
- **`CommandSpec` / `CommandRegistry` / `runCommand`** — versioned
  commands (codec + revision identity, the supervisor ADR 0041 pattern).
  Params are declared (type, required, default, doc) and validated at
  expansion; `revisionHash` pins the declared surface. Nested command
  references are refused — cycles must be undecidable-proof at compile.
- **`ServeBudgets` / `BudgetGuard` / `HarnessRunner`** — budgets as
  enforceable components (the self-bounding serve): concurrency
  admission, a per-run deadline the runner enforces at step boundaries,
  and idle/lifetime exit signals for the embedder's loop. The oka
  supervisor owns the process; budgets own the inside.
- **`RuleEnvelope`** — the typed carrier for rules and guides. Content
  stays world data (commons, memory, docs); the harness moves it and
  says what it is, never interprets it.

## Use

```dart
final assembly = AutomationAssembly(
  sessions: [cdp('web', uri: Uri.parse('http://127.0.0.1:9222'))],
  commands: [fillEmail],
  flows: [
    Flow('checkout', session: 'web', steps: [
      navigate(Uri.parse('https://example.com/cart')),
      runCommand('fill-email', args: {'text': 'a@b.c'}),
      waitFor([exists(role: 'button', name: 'Checkout')]),
    ]),
  ],
  budgets: const ServeBudgets(
    maxConcurrentJobs: 2,
    jobTimeout: Duration(minutes: 5),
    idleExit: Duration(minutes: 10),
  ),
);

final plan = assembly.compile();          // fail closed, all at once
print(assembly.explain());                // deterministic assembly text

final runner = HarnessRunner(guard: BudgetGuard(assembly.budgets!));
final report = await runner.run(plan);    // admitted, deadline-bounded
```

## Layout

```
lib/src/assembly.dart   AutomationAssembly: compile / snapshot / explain
lib/src/flow.dart       Flow + runCommand references
lib/src/command.dart    CommandSpec, CommandRegistry, CommandArgs codec
lib/src/budgets.dart    ServeBudgets + BudgetGuard
lib/src/runner.dart     HarnessRunner (guard around PlanRunner)
lib/src/envelope.dart   RuleEnvelope + loading
```

House rules carry over from the family: attach-only (the guard never
spawns or stops anything), fail closed (compile refuses with every
violation at once), and borrowed sessions (detaching never closes the
target's process).
