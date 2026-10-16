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
- `mcp.json` — stdio MCP (`serve --os` by default; env knobs below)
- `install.sh` — `dart build cli` + `~/.local/bin/universal-automation` symlink
- `skills/universal-automation/SKILL.md` — agent skill body

## Optional browser tier (ADR 0003)

The server mounts desktop-only by default and works immediately.
`navigate` on the desktop tier opens the OS default browser (untracked);
to *drive* a browser, configure one tier — flag beats env beats handle:

| Route | How |
| --- | --- |
| Flag | `serve --os --cdp http://127.0.0.1:9222` |
| Env (the `mcp.json` route) | `UNIVERSAL_AUTOMATION_CDP=http://127.0.0.1:9222` |
| Handle artifact (oka/moli) | `serve --os --handles-dir ~/.oka/handles --browser-handle moli` (the file `moli` holds an absolute URI; oka or a shell script starts moli/Chrome with a debug port and publishes it) |

With a browser tier configured, `navigate`/`evaluate`/`invoke` attach to it
automatically (the result says so in `routedTo`); explicit per-call
`transport`/`endpoint` always win. Agents discover all of this from
`automation_capabilities` — no trial-and-error.

Migrated from `dart_flutter_packages/plugins/universal-automation` (2026-10-15).
