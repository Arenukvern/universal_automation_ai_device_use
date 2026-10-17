# Changelog


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
