# Changelog

## 0.3.0

- **Coordinate-tier actions join the sealed action set**: `ClickAtAction`,
  `MoveAction`, `DragAction` (ADR 0053), plus `SetValueAction` and
  `ElementAction` (ADR 0064) — the semantic-write path. Breaking for
  exhaustive switches over `AutomationAction` (hence the minor bump in
  the 0.x range), which is why `flutter_mcp_harness` 7.0.0 — published
  against this revision — failed to compile against pub.dev's 0.2.0.
- **Harness-facing contract promotions (ADR 0004)**: `SessionBinding`,
  `ResolvedSession`, and the `DriverFactory` typedef move here so
  embedders bind sessions and register drivers against the interface
  alone; `SessionBinding.fromJson` gains a transport-name parser.
- **Capability-granular OS facades**: `OsAppCatalog`, `OsActivator`,
  `OsWindowCapture`, `OsDisplayCapture` with neutral `OsAppRecord` /
  `OsWindowRecord` types — compositions cast to contracts, never to
  concrete drivers.
- `DriverUnsupportedException` carries optional structured `details`.

## 0.2.0

- **Surface action catalog (the `InvokeAction` tier)**: the
  dynamic-registry shape for drivers — framework- and app-specific verbs
  no longer require growing the universal verb set.
  - New sealed `InvokeAction(name, args)`: invoke a named action the
    surface under test registered for automation.
  - New `SurfaceActionDescriptor` (name, description, JSON-Schema-subset
    `inputSchema` carried as plain data — the family depends on no schema
    library) and the opt-in `AutomationActionCatalog` interface
    (`actions()`); implementing it is non-breaking.
  - `CdpDriver` implements the catalog over the page's
    `window.__mcpActions` registry, so any web surface (Jaspr, plain JS,
    Flutter web) composes named, async handlers; new
    `CdpPage.evaluateAsync` awaits Promise results and surfaces JS
    rejections instead of silent `undefined`.
  - WebDriver, AT-SPI, UIA, and AX drivers refuse `InvokeAction` loudly —
    those tiers have no surface action registry.
  - Breaking: exhaustive switches over `AutomationAction` must handle
    `InvokeAction` (all family drivers do; behavioral synthesis refuses
    it — catalog actions carry their own dispatch).
- **Behavior dynamics contract (ADR 0044)**: declarative, composable input
  profiles for humans and agents.
  - New `behavior` module: `BehaviorStep` timed input-step vocabulary,
    `BehaviorPlan`, `BehaviorProfile` (facets: `ActionRhythm`,
    `ReactionDelay`, `SessionPacing`, `PointerMotion`, `KeystrokeCadence`),
    priors (`agentImmediate` degenerate profile, `humanPrior(seed)`
    hyper-prior), `synthesizeBehavior`/`projectBehavior` deterministic
    synthesis, `auditBehavior` self-consistency reporting,
    `BehaviorReceipts` encoders, canonical JSON + SHA-256 hashing, and the
    pinned `xoshiro128**`/splitmix32 PRNG.
  - New `BehavioralDriver` opt-in capability surface (`performWith` with
    typed `BehaviorOutcome`), `ProfiledDriver` wrapper, and
    `DriverCapabilities.behaviorDynamics` (default `false`; `full` sets it).
  - Breaking: `DriverCapabilities.full` now sets `behaviorDynamics: true`;
    drivers claiming `full` without implementing `BehavioralDriver` should
    declare an explicit capability set instead.
