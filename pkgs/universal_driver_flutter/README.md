# universal_driver_flutter

A vmService [`AutomationDriver`](../universal_automation_interface/) for
running Flutter apps — the instrumented tier of the
`universal_automation_*` family.

It speaks the **MCP toolkit's public service-extension wire**
(`ext.mcp.toolkit.*`; canonical names:
`flutter_mcp_toolkit_core.ToolkitExtensionNames`), so an app only needs
the [`mcp_toolkit`](https://pub.dev/packages/mcp_toolkit) binding
(debug or profile build) — no code-generation, no per-app driver code.

## What it gives an agent

- **Observe**: the app's semantic snapshot, projected into the family
  `Snapshot` (flat ref-linked wire → `AxNode` tree; roles mapped to the
  protocol-agnostic set — `textField`→`textbox`, `header`→`heading`).
- **Act**: tap, type (+submit), press key, scroll — addressed by exact
  snapshot ref, label substring, or role+name compose; navigation by
  registered named route (unregistered routes are refused loudly).
- **Screenshot**: PNG frames of the app's views, captured through the
  render pipeline — works while the window is in the background, with no
  screen-recording consent.

The same observe/act/verify vocabulary as the CDP, WebDriver, and
OS-native tiers: agents learn one grammar. Render/ref conventions live
in [`universal_automation_semantics`](../universal_automation_semantics/).

## Usage

```dart
final client = await FlutterVmClient.connect(
  Uri.parse('http://127.0.0.1:8181/TOKEN='),
);
final driver = FlutterVmDriver(client);
final snapshot = await driver.snapshot();
await driver.perform(const ClickAction(css: 's_12'));
final png = await driver.screenshot();
await client.dispose(); // attach-only: never stops the app.
```

With [`universal_automation_toolkit`](../universal_automation_toolkit/),
the tier is built in:

```bash
universal-automation observe  --vm http://127.0.0.1:8181/TOKEN=
universal-automation act      --vm http://127.0.0.1:8181/TOKEN= --click-name Submit
universal-automation serve    --vm http://127.0.0.1:8181/TOKEN=   # MCP stdio
```

## Contract and direction

Per ADR 0036 of the family, this package depends on the *wire contract*
only — never on mcp_flutter packages. A renamed toolkit verb surfaces as
a loud `-32601` on a live app, not silent drift. Composition roots may
replace the factory (`SessionRegistry.registerFactory`).

Attach-only: `dispose()` releases the VM-service connection; the process
behind it belongs to its lifecycle owner (oka / flutter run).
