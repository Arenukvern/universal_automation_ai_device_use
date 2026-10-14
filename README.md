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

## Develop / Steward

```sh
dart pub get
steward doctor --json
steward map
# validate: see stewardship.quality.validate in steward.yaml
```

See [CONTRIBUTING.md](CONTRIBUTING.md) · [SECURITY.md](SECURITY.md).
