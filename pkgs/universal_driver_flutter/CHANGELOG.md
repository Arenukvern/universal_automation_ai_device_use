# Changelog

## 0.1.1

- tap and enter_text now surface the app-side refusal instead of
  swallowing it: `success: false` responses (ref not found, stale ref,
  disabled control, `target_outside_viewport` with its reveal hint)
  throw `ProtocolException` — live-proven: an off-viewport counter
  button now reports the refusal with the reveal_search hint instead of
  a silent ok.

## 0.1.0

- Initial release: vmService `AutomationDriver` over a running Flutter
  app's MCP toolkit service extensions (`ext.mcp.toolkit.*`) — semantic
  snapshot (flat wire → family `AxNode` tree), ref/label/role actions
  (tap, enter text + submit, press key, scroll), named-route navigation,
  background screenshots.
- `FlutterVmClient` with the reconnect-once law and typed
  `EndpointUnreachableException` on dead endpoints.
- `flutterVmServiceFactory` links the tier into `SessionRegistry` (also
  the built-in factory for universal-automation CLI `--vm` and MCP
  `transport: "vmService"`).
