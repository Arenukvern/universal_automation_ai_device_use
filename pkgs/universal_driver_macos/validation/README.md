# Driver validation evidence

These directories store **point-in-time proof** from native macOS dogfood runs
(background launch, native-hook cache warmth, off-screen window discovery, and
related toolkit effects). They are meant for reviewers and agents auditing
*what was proven*, not for replaying on your machine.

## Path placeholders

Evidence files use neutral placeholders instead of maintainer machine paths:

| Placeholder | Meaning |
| --- | --- |
| `REPO_ROOT/` | Root of this repository (`universal_automation_ai_device_use`) |
| `DOGFOOD_WORKSPACE/` | External dogfood tooling checkout used during the run (not shipped here) |
| `DOGFOOD_APP_PATH/` | Built `.app` bundle path on the dogfood machine at run time |

Hashes, PIDs, window IDs, and timing fields are preserved so the proof stays
meaningful; only host-specific filesystem paths are scrubbed.

## Current validation

For how to run driver tests and conformance today, see
[`../README.md`](../README.md) and
[`CONTRIBUTING.md`](../../../CONTRIBUTING.md) at the repo root.
