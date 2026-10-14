# Contributing

This repository is **private** until an explicit public cut. Packages are
MIT and prepared for pub.dev.

## Local loop

```sh
dart pub get
steward doctor --json
steward map
dart analyze pkgs/universal_automation_interface
```

## Skill Steward

Follow mcp_flutter’s OSS stewardship pattern:

1. `steward doctor --json`
2. `steward map`
3. Validation via `steward.yaml` → `stewardship.quality.validate`
4. Durable decisions in `docs/decisions/`
5. Claims need evidence; non-claims stay explicit

Install maintainer skills when added:

```sh
npx skills add Arenukvern/skill_steward --skill release-changelog-harness
```

## Publishing

Dependency order is documented in
`docs/decisions/0001_drivers_into_ua_private_oss_ready.md`. Prefer
`dart pub publish --dry-run` per package before `dart pub publish -f`.

Storage packages live in the sibling repo
[`universal_storage`](https://github.com/Arenukvern/universal_storage).
