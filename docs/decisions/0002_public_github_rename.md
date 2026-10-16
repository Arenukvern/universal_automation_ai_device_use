# ADR 0002 — Public GitHub home and repository rename

**Status:** Accepted (2026-10-16)  
**Amends:** [ADR 0001](0001_drivers_into_ua_private_oss_ready.md) (non-goals on visibility and rename)

## Context

ADR 0001 kept the GitHub remote private and retained the working name
`ai_computer_use_universal_automation` while packages were extracted from
`dart_flutter_packages`. The product surface is **device-use automation**
(universal contracts + drivers + toolkit), distinct from the Flutter app harness
in [`mcp_flutter`](https://github.com/Arenukvern/mcp_flutter).

## Decision

1. Publish the monorepo on GitHub as **`Arenukvern/universal_automation_ai_device_use`**.
2. Retain **package names** on pub.dev (`universal_automation_*`, `universal_driver_*`, …);
   only the Git repository and workspace root Dart package name change.
3. Keep the user-facing CLI/MCP binary alias **`universal-automation`** (hyphenated)
   for compatibility with existing MCP configs and `plugin/install.sh`.
4. Point MCP registry metadata (`server.json`) at the new repository; server id
   `io.github.Arenukvern/universal-automation` (subject to official registry approval).

## Compatibility aliases (intentional)

| Surface | Name |
| --- | --- |
| GitHub repo | `universal_automation_ai_device_use` |
| Workspace root `pubspec` | `universal_automation_ai_device_use` |
| CLI binary on PATH | `universal-automation` |
| MCP server title | Universal Automation Toolkit |
| Dart packages | `universal_automation_*`, `universal_driver_*`, … |

## Non-goals

- Renaming published pub.dev packages
- Moving `universal_storage_*` or merging with this repo
