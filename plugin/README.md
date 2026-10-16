# universal-automation (plugin)

Shippable Cursor / Codex / Claude / ZCode plugin: MCP registration, skills,
and the AOT binary installer for `pkgs/universal_automation_toolkit`.

## Install (local checkout)

From this repository:

```sh
./plugin/install.sh
ln -sf "$(pwd)/plugin" ~/.cursor/plugins/local/universal-automation
```

Then reload MCP in Cursor (or restart the `universal-automation` server).

## Layout

- `.cursor-plugin/plugin.json` — Cursor manifest
- `.codex-plugin/plugin.json` — Codex manifest (+ `interface`)
- `.claude-plugin/plugin.json` — Claude Code
- `.zcode-plugin/plugin.json` — ZCode
- `mcp.json` — stdio MCP (`serve --os` by default)
- `install.sh` — `dart build cli` + `~/.local/bin/universal-automation` symlink
- `skills/universal-automation/SKILL.md` — agent skill body

Migrated from `dart_flutter_packages/plugins/universal-automation` (2026-10-15).
