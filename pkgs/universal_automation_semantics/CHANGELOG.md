# Changelog


## [0.3.0](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_automation_semantics-v0.2.0...universal_automation_semantics-v0.3.0) (2026-10-27)


### ⚠ BREAKING CHANGES

* universal_automation_interface 0.3.0 — coordinate actions, promotions, OS facades

### Features

* plugin ([2e51ebe](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/2e51ebe20e6085b7fae44c03e9e460a1a563c1a3))
* universal_automation_interface 0.3.0 — coordinate actions, promotions, OS facades ([6862303](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/6862303e56d1fba0a586c29e4ddc8b6157bd1bc7))

## 0.2.0

- Family train: `universal_automation_interface` moves to `^0.3.0` (coordinate-tier actions join the sealed action set) and `universal_automation_conformance` to `^0.3.0`; dependency constraints widen accordingly (constraint-widening minor bump).
## 0.1.0

- Initial release (ADR 0052): `SemanticView` — the declarative view
  value (fields, subtreeOf/identifierPrefix selectors, maxNodes cap,
  named `panes`), wire-compatible with mcp_flutter's semantic_snapshot
  filter keys; `Observation` — ref-stable resolution over the full
  walk (refs issue regardless of what is shown), compact numbered text
  rendering with trimming admitted in the header, fail-closed ref
  resolution (`SemanticRefUnavailableException`), structural-signature
  diffs (`ObservationDelta`: added/removed/changed with stable refs).
  Golden tests for every invariant.
