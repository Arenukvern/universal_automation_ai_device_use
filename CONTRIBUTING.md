# Contributing

Thanks for helping improve **universal automation** device-use packages. This
repository follows the same stewardship pattern as
[`mcp_flutter`](https://github.com/Arenukvern/mcp_flutter) and
[`skill_steward`](https://github.com/Arenukvern/skill_steward): charter in
[docs/NORTH_STAR.mdx](docs/NORTH_STAR.mdx) and [AGENTS.md](AGENTS.md), durable decisions in [docs/decisions/](docs/decisions/),
and a native validation gate in [steward.yaml](steward.yaml).

## Local loop

```sh
dart pub get
steward doctor --json   # optional; install via skill_steward install.sh
steward map
```

Run the workspace validation command from `steward.yaml`:

```sh
dart analyze pkgs/universal_automation_interface pkgs/universal_automation_semantics \
  pkgs/universal_automation_conformance pkgs/universal_browser_cdp pkgs/universal_screencast \
  pkgs/universal_lexicon pkgs/universal_webrtc_raw
```

Per-package tests (when you touch a package):

```sh
cd pkgs/<package> && dart pub get && dart test
```

## Skill Steward

1. `steward doctor --json`
2. `steward map`
3. Validation via `steward.yaml` → `stewardship.quality.validate`
4. Durable decisions in `docs/decisions/` (use a new ADR when amending prior non-goals)
5. Claims need evidence; non-claims stay explicit

Optional maintainer skills:

```sh
npx skills add Arenukvern/skill_steward --skill release-changelog-harness
```

## Publishing

Dependency order is documented in
[ADR 0001](docs/decisions/0001_drivers_into_ua_private_oss_ready.mdx). Prefer
`dart pub publish --dry-run` per package before `dart pub publish -f`.

`universal_storage_*` packages live in the sibling repo
[`universal_storage`](https://github.com/Arenukvern/universal_storage).

## Pull requests

- Keep changes focused; match existing style in the package you edit.
- Update `CHANGELOG.md` (workspace or per-package) for user-facing changes.
- Do not commit secrets, tokens, or private URLs.
- Read [SECURITY.md](SECURITY.md) for automation safety expectations.
- Follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
