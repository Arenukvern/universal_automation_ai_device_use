# universal_automation_ai_device_use

[![Docs](https://img.shields.io/badge/docs-docs.page-blue)](https://docs.page/arenukvern/universal_automation_ai_device_use/)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/Arenukvern/universal_automation_ai_device_use)
[![All Contributors](https://img.shields.io/github/all-contributors/Arenukvern/universal_automation_ai_device_use?color=ee8449&style=flat-square)](https://github.com/Arenukvern/universal_automation_ai_device_use#contributors)
[![maintained with Skill Steward](https://raw.githubusercontent.com/Arenukvern/skill_steward/main/docs/brand/assets/svg/badge-light.svg)](https://github.com/Arenukvern/skill_steward)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Validate](https://github.com/Arenukvern/universal_automation_ai_device_use/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/Arenukvern/universal_automation_ai_device_use/actions/workflows/validate.yml)

**pub.dev (published packages):**  
[![universal_automation_interface](https://img.shields.io/pub/v/universal_automation_interface.svg?label=interface)](https://pub.dev/packages/universal_automation_interface)
[![universal_automation_toolkit](https://img.shields.io/pub/v/universal_automation_toolkit.svg?label=toolkit)](https://pub.dev/packages/universal_automation_toolkit)
[![universal_driver_macos](https://img.shields.io/pub/v/universal_driver_macos.svg?label=driver_macos)](https://pub.dev/packages/universal_driver_macos)
[![universal_browser_cdp](https://img.shields.io/pub/v/universal_browser_cdp.svg?label=browser_cdp)](https://pub.dev/packages/universal_browser_cdp)
[![universal_screencast](https://img.shields.io/pub/v/universal_screencast.svg?label=screencast)](https://pub.dev/packages/universal_screencast)
[![universal_webrtc](https://img.shields.io/pub/v/universal_webrtc.svg?label=webrtc)](https://pub.dev/packages/universal_webrtc)
[![universal_tooling_runtime](https://img.shields.io/pub/v/universal_tooling_runtime.svg?label=tooling_runtime)](https://pub.dev/packages/universal_tooling_runtime)

![Open devices to people and agents with care — composable automation across device classes](docs/brand/assets/png/banner-16x9.png)
<!-- banner easter-egg: squint at the SVG/PNG horizon for other curious users -->

**Make every device class legible to humans and AI agents** through one
**declarative, compositional** observe / act / verify surface — desktop and
laptop, phones and tablets, browsers, and the tiers you add next. The aim is an
**optimistic, humane** future: people and agents collaborating on real software
with **consent, receipts, and honest proof** — not unattended takeover of user
devices. Dart contracts, platform drivers, capture/WebRTC plumbing, plus an MCP
+ CLI toolkit. Lexicon packs:
[`universal_lexicon`](https://github.com/xsoulspace/dart_flutter_packages/tree/main/pkgs/universal_lexicon)
in [`dart_flutter_packages`](https://github.com/xsoulspace/dart_flutter_packages).

- 📖 **Docs:** [docs.page/arenukvern/universal_automation_ai_device_use](https://docs.page/arenukvern/universal_automation_ai_device_use/) (wiki + [DX FAQ](docs/DX_FAQ.mdx) + [llms.txt](llms.txt))
- 🤝 **Contribute:** [guide](docs/contributing/contribution_guide.mdx) · [contributors](docs/contributing/contributors.mdx) · [code of conduct](CODE_OF_CONDUCT.md) · [security](SECURITY.md)

**Charter:** [docs/NORTH_STAR.mdx](docs/NORTH_STAR.mdx) · **Decisions:** [docs/decisions/](docs/decisions/) · [AGENTS.md](AGENTS.md) · **Brand:** [docs/brand/](docs/brand/)

**Repository:** https://github.com/Arenukvern/universal_automation_ai_device_use  
**Sibling storage product:** [`universal_storage`](https://github.com/Arenukvern/universal_storage)  
**Flutter app harness (separate repo):** [`mcp_flutter`](https://github.com/Arenukvern/mcp_flutter)

- **Contribute:** [CONTRIBUTING.md](CONTRIBUTING.md) · [SECURITY.md](SECURITY.md) · [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- **Agents:** [AGENTS.md](AGENTS.md) · decisions in [docs/decisions/](docs/decisions/)

This monorepo holds the **universal automation** family: shared `AutomationDriver`
contracts, semantic projections, conformance tests, platform drivers (macOS, Linux,
Windows, CDP, WebDriver), screencast/capture helpers, and WebRTC sidecars. The
agent-facing CLI and MCP server live in
[`universal_automation_toolkit`](pkgs/universal_automation_toolkit/).

## Architecture: one MCP server, many adapters

Universal Automation exposes **one MCP server** (`universal-automation serve …`) and
one `automation_*` tool surface (observe, act, capture/verify). Platform code plugs
in as **adapter packages** registered on a single runtime registry — macOS, Windows,
Linux, browser (CDP/WebDriver), and future Android, iOS, and Flutter tiers.

Do **not** ship or configure separate per-platform MCP servers (`android-use`,
`ios-use`, `macos-use`, …). That would duplicate browser tooling, capture, and
config, let implementations drift, and force agents to learn which server to call.

| Layer | Role |
| --- | --- |
| `universal_automation_interface` | Contracts only; no native code (ADR 0004) |
| `universal_driver_*` / `universal_browser_*` | Adapters chosen at install or composition time |
| `universal_automation_toolkit` | Plans, runner, MCP face, registry |

**Lean default:** core + desktop OS adapter + optional browser tier (`serve --os`,
`--cdp`). Flutter, mobile adapters, and harness/SDK are opt-in adapter dependencies on
the **same** MCP entry. **oka may host UA** under its supervisor; UA does not embed or
launch oka runners. Shared tools
(screenshot, semantics tree, tap) cover common work; truly platform-specific
behavior (e.g. Flutter hot reload) lives in named tool groups on that server, not a
forked product. UA **never owns target lifecycle** (apps, emulators, simulators): **oka**
creates targets and hands declared **`oka_devices`** id and typed **`vmServiceUri`** from
its session manifest — UA never scrapes discovery output. Bounded subprocesses for tools
like `adb` / `xcrun` go through **`oka_process`**; **`universal_tooling_runtime`** thins
over that contract. The Flutter
adapter stays thin over
[`mcp_flutter`](https://github.com/Arenukvern/mcp_flutter)'s published attach-only driver
(today `VmClient` plus `ToolkitDriver` in `flutter_mcp_harness`, planned as its own
attach-only package). Optional adapter tool groups appear in `tools/list` only when the
package is installed **and** the target is reachable, with `tools/list_changed` on
appear/disappear — so agents are not drowned in 100+ tools by default.

Durable rule: [ADR 0009](docs/decisions/0009_one_mcp_server_with_adapters.mdx).

## Packages

| Package | Role |
| --- | --- |
| [`universal_automation_interface`](pkgs/universal_automation_interface/) ([pub](https://pub.dev/packages/universal_automation_interface)) | Core contracts (`Snapshot`, actions, sessions) |
| [`universal_automation_semantics`](pkgs/universal_automation_semantics/) ([pub](https://pub.dev/packages/universal_automation_semantics)) | Semantic views and family projections |
| [`universal_automation_conformance`](pkgs/universal_automation_conformance/) ([pub](https://pub.dev/packages/universal_automation_conformance)) | Shared conformance harness |
| [`universal_automation_toolkit`](pkgs/universal_automation_toolkit/) ([pub](https://pub.dev/packages/universal_automation_toolkit)) | CLI, plans, MCP server |
| `universal_driver_*` ([macOS](https://pub.dev/packages/universal_driver_macos) · [Linux](https://pub.dev/packages/universal_driver_linux) · [Windows](https://pub.dev/packages/universal_driver_windows)) | Native OS automation |
| `universal_browser_*` ([CDP](https://pub.dev/packages/universal_browser_cdp) · [WebDriver](https://pub.dev/packages/universal_browser_webdriver)) | Browser automation |
| `universal_screencast` ([pub](https://pub.dev/packages/universal_screencast)) / `universal_capture_*` ([macOS](https://pub.dev/packages/universal_capture_macos) · [Flutter](https://pub.dev/packages/universal_capture_flutter)) | Frames and capture |
| `universal_webrtc` ([pub](https://pub.dev/packages/universal_webrtc)) / `universal_webrtc_raw` ([pub](https://pub.dev/packages/universal_webrtc_raw)) | WebRTC helpers |
| [`universal_lexicon`](https://github.com/xsoulspace/dart_flutter_packages/tree/main/pkgs/universal_lexicon) | Lexicon packs in DFP (not vendored here) |
| [`universal_tooling_runtime`](pkgs/universal_tooling_runtime/) ([pub](https://pub.dev/packages/universal_tooling_runtime)) | Bounded process runs, path policy, locks, macOS no-fork verify |

Publish order and migration notes: [ADR 0001](docs/decisions/0001_drivers_into_ua_private_oss_ready.mdx).

## Quick start (toolkit + MCP)

Install the prebuilt MCP/CLI binary (no Dart required on macOS arm64 / Linux x64 / Windows x64):

```sh
curl -fsSL https://raw.githubusercontent.com/Arenukvern/universal_automation_ai_device_use/main/install.sh | bash
```

```powershell
irm https://raw.githubusercontent.com/Arenukvern/universal_automation_ai_device_use/main/install.ps1 | iex
```

macOS downloads are **preview (unsigned)** until release signing is enabled
([RELEASING.md](RELEASING.md)). To build from source instead:

```sh
./plugin/install.sh
```

That runs `dart build cli` and links the binary into `~/.local/bin`. Point your MCP client at the bundled config in
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
  pkgs/universal_webrtc_raw pkgs/universal_tooling_runtime
```

Full command list: `steward.yaml` → `stewardship.quality.validate`.

## Contributors

Thanks to everyone who improves this family.

Roster: [all-contributors](https://allcontributors.org/) · [`.all-contributorsrc`](.all-contributorsrc) · [contributors guide](docs/contributing/contributors.mdx).

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/Arenukvern"><img src="https://avatars.githubusercontent.com/u/15068151?v=4?s=100" width="100px;" alt="Anton Malofeev"/><br /><sub><b>Anton Malofeev</b></sub></a><br /><a href="https://github.com/Arenukvern/universal_automation_ai_device_use/commits?author=Arenukvern" title="Code">💻</a> <a href="https://github.com/Arenukvern/universal_automation_ai_device_use/commits?author=Arenukvern" title="Documentation">📖</a> <a href="#infra-Arenukvern" title="Infrastructure (Hosting, Build-Tools, etc)">🚇</a> <a href="#maintenance-Arenukvern" title="Maintenance">🚧</a></td>
    </tr>
  </tbody>
</table>
<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->
<!-- ALL-CONTRIBUTORS-LIST:END -->

## License

MIT — see [LICENSE](LICENSE).
