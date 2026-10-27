# Changelog

## [0.4.0](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_automation_interface-v0.3.0...universal_automation_interface-v0.4.0) (2026-10-27)


### ⚠ BREAKING CHANGES

* universal_automation_interface 0.3.0 — coordinate actions, promotions, OS facades

### Features

* **computer-use:** Codex-parity pid pointer, automation_computer, and evidence ([29f22be](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/29f22be3112f97b7080166960840aa20326c3d66))
* **macos:** OS-AX web-first walk, window-local clickAt, automation_preview ([8ab9a39](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/8ab9a39782d2737db145248697a9a5539b14bbfd))
* plugin ([2e51ebe](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/2e51ebe20e6085b7fae44c03e9e460a1a563c1a3))
* seamless tier routing and optional browser tier (ADR 0003) ([f6c1b68](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/f6c1b6868167dd927584ffe9644624e00388f18d))
* universal automation harness v0.1.0 (ADR 0004 §4) ([b40e35b](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/b40e35bb600482f82f24e8cbcfc02a2add31c3cc))
* universal_automation_interface 0.3.0 — coordinate actions, promotions, OS facades ([6862303](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/6862303e56d1fba0a586c29e4ddc8b6157bd1bc7))

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
