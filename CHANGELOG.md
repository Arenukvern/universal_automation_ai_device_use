# Changelog

Workspace-level notes. Per-package changelogs live under `pkgs/*/CHANGELOG.md`.

## Unreleased

- Scrubbed maintainer paths from `pkgs/universal_driver_macos/validation/**`
  (neutral `REPO_ROOT` / `DOGFOOD_*` placeholders).
- Added brand banner and icon under `docs/brand/` and charter [docs/NORTH_STAR.mdx](docs/NORTH_STAR.mdx).
- **OSS release prep:** repository renamed to
  `Arenukvern/universal_automation_ai_device_use`; README, CONTRIBUTING,
  CODE_OF_CONDUCT, GitHub Actions validate workflow, and package metadata
  retargeted (see [ADR 0002](docs/decisions/0002_public_github_rename.md)).
- **`universal_lexicon`:** drop unsupported `final` formal-parameter modifiers
  so `dart analyze` passes on Dart 3.13 (for-in `final` variables unchanged).
- **Workspace `pubspec`:** remove maintainer-only `path` overrides to sibling
  `storage_problem` checkouts; use hosted `xsoulspace_*` packages instead.
- Moved OS/browser/screencast/capture/WebRTC driver packages from
  `dart_flutter_packages` into this workspace.
- Skill Steward adoption (`steward.yaml`, `AGENTS.md`).
- Package metadata prepared for pub.dev publish order in ADR 0001.
