# Changelog

Workspace-level notes. Per-package changelogs live under `pkgs/*/CHANGELOG.md`.

## Unreleased

- **Seamless tier routing + optional browser tier (ADR 0003):** the
  cold-start failure where `navigate` dead-ended on a desktop-only
  server is fixed at four layers — desktop drivers now lower
  `navigate` to the OS default browser (scheme allowlist, injected
  seam); `serve` accepts `--cdp/--webdriver/--os` together plus
  `--browser-handle`/`--handles-dir` (oka/moli handle artifacts) and
  `UNIVERSAL_AUTOMATION_CDP` env fallback; `navigate`/`evaluate`/
  `invoke` affinity-route to a configured browser tier with a
  `routedTo` receipt; new `automation_capabilities` tool + error
  remedies now survive the MCP boundary as structured JSON blocks.
- docs.page: `docs.json`, `docs/index.mdx`, sidebar navigation, `llms.txt`, CI `docs.yml`.
- all-contributors: `.all-contributorsrc`, README contributors table and badge.
- OSS hygiene: `.editorconfig`, `CODEOWNERS`, Dependabot for Actions and pub.
- Scrubbed maintainer paths from `pkgs/universal_driver_macos/validation/**`
  (neutral `REPO_ROOT` / `DOGFOOD_*` placeholders).
- Added brand banner and icon under `docs/brand/` and charter [docs/NORTH_STAR.mdx](docs/NORTH_STAR.mdx).
- **OSS release prep:** repository renamed to
  `Arenukvern/universal_automation_ai_device_use`; README, CONTRIBUTING,
  CODE_OF_CONDUCT, GitHub Actions validate workflow, and package metadata
  retargeted (see [ADR 0002](docs/decisions/0002_public_github_rename.mdx)).
- **`universal_lexicon`:** drop unsupported `final` formal-parameter modifiers
  so `dart analyze` passes on Dart 3.13 (for-in `final` variables unchanged).
- **Workspace `pubspec`:** remove maintainer-only `path` overrides to sibling
  `storage_problem` checkouts; use hosted `xsoulspace_*` packages instead.
- Moved OS/browser/screencast/capture/WebRTC driver packages from
  `dart_flutter_packages` into this workspace.
- Skill Steward adoption (`steward.yaml`, `AGENTS.md`).
- Package metadata prepared for pub.dev publish order in ADR 0001.
