# Changelog

## [0.6.0](https://github.com/Arenukvern/universal_automation_ai_device_use/compare/universal_automation_semantics-v0.5.0...universal_automation_semantics-v0.6.0) (2026-11-09)


### ⚠ BREAKING CHANGES

* universal_automation_interface 0.3.0 — coordinate actions, promotions, OS facades

### Features

* plugin ([2e51ebe](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/2e51ebe20e6085b7fae44c03e9e460a1a563c1a3))
* **semantics:** compact render quality — state suffixes, fields honored, honest trim accounting, typed deltas ([45a89a5](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/45a89a5378d311fe9a7cb2dca99c70262cc71a64))
* **semantics:** SemanticLens — compact and design render usefulness ([1c6f798](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/1c6f7982a1764ea090860d23aff284c5df073159))
* universal_automation_interface 0.3.0 — coordinate actions, promotions, OS facades ([6862303](https://github.com/Arenukvern/universal_automation_ai_device_use/commit/6862303e56d1fba0a586c29e4ddc8b6157bd1bc7))

## 0.5.0

- **SemanticLens — switchable render usefulness** (measured in
  tool/benchmark_compression.dart, real + synthetic fixtures):
  `standard` (reference grammar), `compact` (act-loop: short role
  codes, unnamed container rows dropped, `=` values — refs, names,
  identifiers and state suffixes never dropped; 100% findability kept
  at 8-17% fewer bytes), `design` (critique seed: geometry rows plus
  column/row/width clustering footers for impeccable-style spacing and
  alignment scoring — pure bounds truth, no pixels).
- `Observation.render(lens: ...)` — source-compatible additive param.

## 0.4.0

- **Compact render quality**: lines now carry the state suffixes that
  locate or gate a control — `[disabled]` and the `#identifier` selector
  target — and drop empty `value=""` noise; quoted values are escaped.
- The `fields` view contract is honored end-to-end (it was declared but
  ignored): `fields: [bounds]` renders `@(left,top) WxH` geometry, and a
  minimal `fields: [role]` renders `ref role` only; `ref` always renders.
- Trim accounting is honest: the header reads `shown=S/M TRIMMED` where M
  is everything the view's selectors matched before the cap.
- Delta rows say WHAT changed in place: `value="old" → "new"` for value
  swaps, `moved (l,t) → (l',t')` for pure moves, both when both — and the
  delta carries a `# delta +A -R ~C` header instead of bare rows.

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
