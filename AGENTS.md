# AGENTS.md — Agent Entrypoint Map

Welcome. This project uses **Skill Steward** to make repository purpose, validation, docs, and agent handoff legible.

Computer-use / agent observe–act–verify automation family. Contracts +
OS/browser/capture/WebRTC drivers + `universal_lexicon` live here.
`universal_storage_*` is a sibling product (`~/xs/universal_storage`).
GitHub remote stays **private** until an explicit public cut; packages are
MIT and pub.dev-ready (ADR 0001). Stewardship follows the mcp_flutter OSS
pattern (doctor → map → validate → CONTRIBUTING/SECURITY).

## Operational Desk

Run the following commands to interact with the project's agentic tools:

- **Show operational map**: `steward map`
- **Inspect Steward contract**: `steward doctor --json`
- **Validate workspace**: use the native validation command recorded in `steward.yaml`

## Map — "I want to…"

| I want to… | Read |
|---|---|
| Know why drivers left DFP | `docs/decisions/0001_drivers_into_ua_private_oss_ready.md` |
| Publish packages | README → Publish order; `dart pub publish --dry-run` per package |
| Wire a consumer | path override to `pkgs/<name>` (not DFP) |
| Install MCP + skill plugin | `plugin/install.sh`; harness shim `../ecsai_harness/tool/install_universal_automation_plugin.sh` |

## North Star Impact

Before durable structural changes, classify `north_star_impact`: `none`, `applies`, `clarifies`, `sub_star`, `amends`, or `conflicts`.

- `none` / `applies`: use the native workflow and validation gate.
- `clarifies`: update the smallest FAQ, docs map, skill, check, or validation message.
- `sub_star`: declare the local parent/child boundary and what the sub-North Star cannot override.
- `amends` / `conflicts`: stop and write or update an ADR before changing the repo center.

Ask whether the change serves real product pain, which North Star value path it serves, and whether a mechanism is becoming the mission.

## Claims and Evidence

Before claiming readiness, maturity, harness support, steward status, or adoption:

1. Name the exact claim.
2. Check the weakest proof that supports only that claim.
3. Route the durable artifact:
   - ADR for durable decisions and trade-offs.
   - FAQ/docs for standing why/how guidance.
   - Check/tool/test for repeated deterministic drift.
   - Current ledger for the weakest true current status.
   - Evidence for real proof or blocked proof.
   - Delete completed plans after extracting durable truth.
4. Record non-claims.

If the same friction loops twice, stop before making another packet. Name the pain signal, owner, native validation gate, smallest disposition, rerun route, and non-claims; then fix the owner, move repeated drift to a check/tool/skill/current ledger, leave the path native, or stop.

If this repo needs a current claim ledger, run `steward evidence init --minimal`.
Default to no harness: do not add actions, probes, benchmarks, or scenarios unless typed actions, probes, or benchmarks help real repo work.
Use `steward.yaml` and harness proof only when typed actions, probes, or benchmarks help real repo work.

## Active Skills

Skills are installed locally under `.agents/skills/`. You can view them using:
- `steward list`

For more information on the project charter and decisions:
- Read [NORTH_STAR.mdx](docs/NORTH_STAR.mdx) (if present)
- Read [ADR Index](docs/decisions/README) (if present)

<!-- codemap-index:start -->
# Codemap — navigate this repo

Discover once per session: `resources/read` `codemap://surface/v1`, or `map_surface`.
Then call `map_index` with `operation=`. The transport refuses retired names
(`map_index_search`, `map_index_query`, `map_index_build`, and the other `map_index_*` tools).

Pass `"root": "/Users/antonio/xs/ai_computer_use_universal_automation"` when the client cwd is not this repo.

1. **Start** — `map_doctor`, then `map_index` `{"operation":"build","root":"/Users/antonio/xs/ai_computer_use_universal_automation","ignore_prefixes":["build/","dist/",".dart_tool/","target/"]}`, then `map_index` `{"operation":"context_map","root":"/Users/antonio/xs/ai_computer_use_universal_automation","limit":24}`.
2. **Find** — `operation=search` and `query`. Concept-shaped queries add `"mode":"bm25"`.
3. **Before an edit** — `operation=query`, `kind=impact`, `symbol` = `rel/path.ext::unit.name` from search. `kind=context` returns the node and its edges. `kind=trace` also needs `target`.
4. **One evidence packet** — `operation=evidence` with `purpose` (`understand`, `impact`, or `trace`) and `budget_bytes`. Open the exact original with `operation=expand` and the handle in `meta.expansion`.
5. **Before commit** — `operation=changes`.
6. **On every answer** — read `freshness` and `meta.transport`. Ordinary reads refresh a stale index. `freshness_policy=refuse` starts no repair. Navigation facts are review leads; they do not authorize adoption.

CLI, from the codemap checkout:

`~/xs/codemap/.venv/bin/python ~/xs/codemap/engines/versions/py_engine/codemap_cli.py --json exec <index_command> --args '{"root":"/Users/antonio/xs/ai_computer_use_universal_automation",...}'`

Parser edges only. Unresolved calls stay in the payload.
<!-- codemap-index:end -->
