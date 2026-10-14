# ai_computer_use_universal_automation

Private workspace for the **universal automation** family (agent
observe / act / verify, MCP + CLI). Extracted from
`~/xs/storage_problem/dart_flutter_packages` on 2026-10-14.

**Remote:** https://github.com/Arenukvern/ai_computer_use_universal_automation
(private).

## Packages

| Package | Role |
| --- | --- |
| `universal_automation_interface` | Pure contracts |
| `universal_automation_semantics` | Semantics layer |
| `universal_automation_toolkit` | CLI + MCP serve surface |
| `universal_automation_conformance` | Conformance oracles |

Platform drivers (`universal_driver_*`, `universal_browser_*`,
`universal_screencast`) stay in DFP for now and are path-overridden from
this workspace root.

## Consumers

Point path deps here (not DFP):

```yaml
universal_automation_toolkit:
  path: ../ai_computer_use_universal_automation/pkgs/universal_automation_toolkit
universal_automation_interface:
  path: ../ai_computer_use_universal_automation/pkgs/universal_automation_interface
```

Env for harness UATK lane: `UATK_ROOT` →
`…/pkgs/universal_automation_toolkit` (or rely on `resolveUatkRoot` once
wired).

## Develop

```sh
cd ~/xs/ai_computer_use_universal_automation
dart pub get
dart analyze pkgs/universal_automation_interface
dart test pkgs/universal_automation_interface
```
