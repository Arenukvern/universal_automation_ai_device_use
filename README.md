# universal_automation_ai_device_use

[![maintained with Skill Steward](https://raw.githubusercontent.com/Arenukvern/skill_steward/main/docs/brand/assets/svg/badge-light.svg)](https://github.com/Arenukvern/skill_steward)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Validate](https://github.com/Arenukvern/universal_automation_ai_device_use/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/Arenukvern/universal_automation_ai_device_use/actions/workflows/validate.yml)

![Open devices to people and agents with care — composable automation across device classes](docs/brand/assets/png/banner-16x9.png)
<!-- banner easter-egg: squint at the SVG/PNG horizon for other curious users -->

**Make every device class legible to humans and AI agents** through one
**declarative, compositional** observe / act / verify surface — desktop and
laptop, phones and tablets, browsers, and the tiers you add next. The aim is an
**optimistic, humane** future: people and agents collaborating on real software
with **consent, receipts, and honest proof** — not unattended takeover of user
devices. Dart contracts, platform drivers, capture/WebRTC plumbing, lexicon
packs, plus an MCP + CLI toolkit.

## Vision and principles

Short orientation (sourced from this repo, SECURITY, and sibling stewardship
repos): [docs/VISION.md](docs/VISION.md). Brand assets:
[docs/brand/](docs/brand/).

**Repository:** https://github.com/Arenukvern/universal_automation_ai_device_use  
**Sibling storage product:** [`universal_storage`](https://github.com/Arenukvern/universal_storage)  
**Flutter app harness (separate repo):** [`mcp_flutter`](https://github.com/Arenukvern/mcp_flutter)

- **Contribute:** [CONTRIBUTING.md](CONTRIBUTING.md) · [SECURITY.md](SECURITY.md) · [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- **Agents:** [AGENTS.md](AGENTS.md) · decisions in [docs/decisions/](docs/decisions/)

This monorepo holds the **universal automation** family: shared `AutomationDriver`
contracts, semantic projections, conformance tests, platform drivers (macOS, Linux,
Windows, CDP, WebDriver), screencast/capture helpers, WebRTC sidecars, and
`universal_lexicon`. The agent-facing CLI and MCP server live in
[`universal_automation_toolkit`](pkgs/universal_automation_toolkit/).

## Packages

| Package | Role |
| --- | --- |
| [`universal_automation_interface`](pkgs/universal_automation_interface/) | Core contracts (`Snapshot`, actions, sessions) |
| [`universal_automation_semantics`](pkgs/universal_automation_semantics/) | Semantic views and family projections |
| [`universal_automation_conformance`](pkgs/universal_automation_conformance/) | Shared conformance harness |
| [`universal_automation_toolkit`](pkgs/universal_automation_toolkit/) | CLI, plans, MCP server |
| `universal_driver_*` | Native OS automation (macOS, Linux, Windows) |
| `universal_browser_*` | Browser automation (CDP, WebDriver) |
| `universal_screencast` / `universal_capture_*` | Frames and capture |
| `universal_webrtc` / `universal_webrtc_raw` | WebRTC helpers |
| [`universal_lexicon`](pkgs/universal_lexicon/) | Lexicon packs |

Publish order and migration notes: [ADR 0001](docs/decisions/0001_drivers_into_ua_private_oss_ready.md).

## Quick start (toolkit + MCP)

From a clone of this repository:

```sh
./plugin/install.sh
```

That builds the AOT `universal-automation` binary and links it into
`~/.local/bin`. Point your MCP client at the bundled config in
[`plugin/mcp.json`](plugin/mcp.json) (stdio `serve --os` by default), or run
commands directly:

```sh
dart pub get
cd pkgs/universal_automation_toolkit
dart run bin/universal_automation.dart validate --plan plans/desktop-smoke.yaml
dart run bin/universal_automation.dart serve --os   # MCP stdio
```

See [`pkgs/universal_automation_toolkit/README.md`](pkgs/universal_automation_toolkit/README.md)
for plan composition, browser (`--cdp`), and consent-gated desktop flows.

## Agent plugin (Cursor / Codex / Claude / ZCode)

The shippable plugin bundle is under [`plugin/`](plugin/). After `plugin/install.sh`,
link the local plugin for Cursor:

```sh
ln -sf "$(pwd)/plugin" ~/.cursor/plugins/local/universal-automation
```

Skills are listed in [`skills.json`](skills.json); the skill body is
[`plugin/skills/universal-automation/SKILL.md`](plugin/skills/universal-automation/SKILL.md).

## Develop / validate

```sh
dart pub get
steward doctor --json   # when steward CLI is installed
steward map
# Primary gate (also runs in CI):
dart analyze pkgs/universal_automation_interface pkgs/universal_automation_semantics \
  pkgs/universal_automation_conformance pkgs/universal_browser_cdp pkgs/universal_screencast \
  pkgs/universal_lexicon pkgs/universal_webrtc_raw
```

Full command list: `steward.yaml` → `stewardship.quality.validate`.

## License

MIT — see [LICENSE](LICENSE).
