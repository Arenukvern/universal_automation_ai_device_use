# OS-AX web fidelity + window-local actuation (ADR 0065)

## Automated

- `dart test pkgs/universal_driver_macos` — web-first walk bridge, window-local `clickAt`, `requiresForeground` ladder
- `dart test pkgs/universal_automation_toolkit/test/mcp_server_test.dart` — MCP tools including `automation_preview`
- `dart test pkgs/universal_automation_toolkit/test/background_actuation_test.dart` — anchored sessions

## Live (manual, macOS)

With Chrome on `pub.dev/packages/oka_process/admin#github-actions` and Cursor frontmost:

1. `automation_list_apps` → anchor `app: {bundleId: "com.google.Chrome"}`
2. `automation_observe` with `view` → `walkMeta.webRootFound: true` and form controls in tree
3. `automation_preview` `{op: start, windowId, maxPx: 640}` then `{op: frame, image: true}`
4. `automation_act` `{action: setValue, role: textbox, value: "Arenukvern/oka"}` or window-local `clickAt` with `windowId`

Gate script: `pkgs/universal_driver_macos/validation/gate_os_ax_web_fidelity.sh`
