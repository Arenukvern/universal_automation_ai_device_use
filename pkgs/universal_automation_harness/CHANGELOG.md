# Changelog


## 0.1.1

- Family train: `universal_automation_interface` moves to `^0.3.0` (coordinate-tier actions join the sealed action set) and `universal_automation_conformance` to `^0.3.0`; dependency constraints widen accordingly (constraint-widening minor bump).
## 0.1.0

- Initial release (ADR 0004's harness layer, built on the interface
  promotions and the de-nativized toolkit core):
  - `AutomationAssembly`: sessions, commands, flows, budgets — compiles
    to one `AutomationPlan`, fail closed with every violation at once;
    `snapshot()` for agents, `explain()` for humans.
  - `Flow`: named scenario trees with session defaults that inherit down
    the `extend` chain; the toolkit owns chain semantics.
  - Versioned commands (`CommandSpec` / `CommandRegistry` / `runCommand`):
    declared codec + revision identity + non-cryptographic revision hash;
    compile-time expansion so CLI, serve, and an in-app agent execute
    identical steps.
  - Budgets as components (`ServeBudgets` / `BudgetGuard` /
    `HarnessRunner`): concurrency admission, per-run deadline enforced by
    the toolkit runner at step boundaries, idle/lifetime exit signals —
    the self-bounding serve, inside an oka-supervised process.
  - `RuleEnvelope`: typed rule/guide carrier; content stays world data.
