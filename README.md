# ai_computer_use_universal_automation

Private workspace for **universal automation** (observe / act / verify,
MCP + CLI), OS/browser/capture/WebRTC **drivers**, and **lexicon**.

[![maintained with Skill Steward](https://raw.githubusercontent.com/Arenukvern/skill_steward/main/docs/brand/assets/svg/badge-light.svg)](https://github.com/Arenukvern/skill_steward)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Remote:** https://github.com/Arenukvern/ai_computer_use_universal_automation
(**private**). Sibling storage product:
[`universal_storage`](https://github.com/Arenukvern/universal_storage).

## Packages

| Package | Role |
| --- | --- |
| `universal_automation_*` | Contracts, semantics, conformance, toolkit |
| `universal_driver_*` | OS drivers |
| `universal_browser_*` | Browser drivers |
| `universal_screencast` / `universal_capture_*` | Frames / capture |
| `universal_webrtc` / `_raw` | WebRTC + sidecar |
| `universal_lexicon` | Lexicon packs |

## Agent plugin (MCP + skill)

The shippable Cursor/Codex/Claude/ZCode bundle lives in [`plugin/`](plugin/).
Run `plugin/install.sh` to build the AOT CLI and link `~/.local/bin/universal-automation`.

From the harness workspace:

```sh
/Users/antonio/xs/ecsai_harness/tool/install_universal_automation_plugin.sh
```

## Develop / Steward

```sh
dart pub get
steward doctor --json
steward map
# validate: see stewardship.quality.validate in steward.yaml
```

See [CONTRIBUTING.md](CONTRIBUTING.md) · [SECURITY.md](SECURITY.md).
