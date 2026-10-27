---
name: universal-automation
description: >
  Drive browsers (CDP/WebDriver), native macOS/Linux/Windows apps, and
  Flutter surfaces through the universal_automation family: the
  observe/act/verify loop, declarative plans composed as typed Dart
  (YAML snapshots for agents), intent routing, screencast recording, and
  humanized input dynamics (ADR-0044 behavior profiles). Use when a task
  needs UI automation, browser driving, plan-based testing, or
  app-intent invocation — via the `universal-automation` CLI, the
  `automation_*` MCP tools, or a Dart plan file.
---

# Universal Automation Toolkit

One vocabulary for the observe/act/verify loop across browser and OS
tiers (ADR 0046). Attach-only: it never spawns or stops processes —
launch targets yourself (or point at oka-published session handles) and
aim the toolkit at the debug endpoint.

**Dart is the source of truth; YAML/JSON documents are snapshots** (the
agent interchange). Code steps make plans first-class code: terminal
commands, oka calls, arbitrary checks.

## Linked tiers

| Tier                       | Transport         | Notes                                                                                                                             |
| -------------------------- | ----------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Chromium / Flutter web AOT | `cdp`             | snapshots, semantic clicks, profiles, `record`; full page, size cap, JPEG, tab selection                                          |
| Safari / WebDriver ends    | `webdriver`       | actions + screenshots; no a11y tree; no full page, resize, or JPEG (W3C has none)                                                 |
| macOS apps                 | `osAccessibility` | focused app; Accessibility (+Screen Recording) TCC; `navigate` opens the system browser (ADR 0003); size cap + JPEG, no full page |
| Linux apps                 | `osAccessibility` | session D-Bus AT-SPI; `navigate` opens the system browser                                                                         |
| Windows apps               | `osAccessibility` | UIA sidecar binary; `navigate` opens the system browser                                                                           |
| Flutter JIT (debug)        | `vmService`       | inject `DriverFactory` (composition root)                                                                                         |

## MCP tools (plugin server mounted)

| Tool                         | Purpose                                                                                                                                                                                                                                                             |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `automation_capabilities`    | What this server can reach — default transport, per-tier endpoints + reachability probe, verb matrix, routing + handle config. Call first when unsure which tier a verb will take.                                                                                  |
| `automation_observe`         | Semantic snapshot of a surface (read-only). Pass `view` (`{subtreeOf, identifierPrefix, fields, maxNodes, panes}`) for a rendered, ref-stable observation instead of the raw tree; `diff: true` adds +/-/~ rows against the previous viewed observation (ADR 0052). |
| `automation_act`             | navigate/click/type/key/scroll/evaluate/invoke; optional `profile` (ADR-0044 humanized delivery) + `seed`; `returnState: true` attaches the post-action state render — act + observe in one call.                                                                   |
| `automation_verify`          | Checks: `{exists: {role?, name?}}`, `{absent: …}`, `{value: {locator, equals/contains}}`, `{urlContains: s}`.                                                                                                                                                       |
| `automation_screenshot`      | PNG to a local path (opt-in pixels; the semantic channel is primary). `fullPage`, `maxPx`, `format`/`quality` choose how much and how large; `targetId`/`targetUrl`/`targetTitle` pick the browser tab.                                                             |
| `automation_list_apps`       | macOS tier: running, anchorable apps — feed a row into any OS call's `app` argument (background observe/act, ADR 0064).                                                                                                                                             |
| `automation_request_consent` | Ask the OS for a grant the tier needs (`accessibility` for the app tree, `screenRecording` for pixels). The OS shows its own prompt; a capture never raises it by itself.                                                                                           |
| `automation_validate_plan`   | Fail-closed snapshot validation.                                                                                                                                                                                                                                    |
| `automation_run_plan`        | Run a scenario; structured JSON report + receipts.                                                                                                                                                                                                                  |

Ad-hoc tools take a `transport` (`cdp | webdriver | osAccessibility`)
plus an `endpoint` (HTTP base); `osAccessibility` is the desktop tier —
it binds the **focused application** and needs no endpoint. Without
arguments the server uses its `serve` default (`--cdp <base>`, or
`--os` for the desktop tier). A browser with several tabs open takes
`targetId` / `targetUrl` / `targetTitle` to name the one you mean.

## Cold start (first call)

1. `automation_capabilities` — one read-only call: the default
   transport, whether a browser tier is configured (and reachable), the
   verb matrix. No trial-and-error.
2. Desktop work: `automation_list_apps` → anchor via `app: {pid}` →
   `automation_observe` with a `view` → act with `returnState: true`.
3. Browser work: with a browser tier configured, `navigate`/`evaluate`/
   `invoke` attach to it automatically (`routedTo` in the result says
   so). With none configured, desktop `navigate` opens the OS default
   browser — an **untracked** surface: observe it by anchoring the
   browser app, drive it by configuring a tier (below).

## Optional browser tier (ADR 0003)

Flag beats env beats handle artifact:

```bash
universal-automation serve --os --cdp http://127.0.0.1:9222   # flags
UNIVERSAL_AUTOMATION_CDP=http://127.0.0.1:9222 ... serve --os # env (mcp.json)
universal-automation serve --os --handles-dir ~/.oka/handles --browser-handle moli
```

The handle artifact is the oka/moli route: something else starts the
browser (e.g. `moli serve` or `chromium --remote-debugging-port=9222`)
and publishes `<handles-dir>/<name>` containing the absolute URI; the
toolkit attaches and never owns the process.

### Which tab? (browser with several open)

A browser session lists **every** open tab, so attaching to "the first page"
is a guess. Name the tab you mean, and the attach refuses rather than
guessing when the choice is ambiguous:

```bash
universal-automation screenshot --cdp http://127.0.0.1:9222 \
  --target-url /checkout --out /tmp/checkout.png
```

`--target-id`, `--target-url`, `--target-title` (CLI) and `targetId` /
`targetUrl` / `targetTitle` (MCP) pick the tab. In a plan, the same choice
rides the session URI: `http://127.0.0.1:9222#targetUrl=/checkout`.

## Captures that a model can actually use

`automation_screenshot` (and the `screenshot` plan step) take options that
decide _how much_ and _how large_:

| Option                           | Effect                                              | Who honors it |
| -------------------------------- | --------------------------------------------------- | ------------- |
| `fullPage: true`                 | the whole scrollable surface, not just the viewport | CDP           |
| `maxPx: 1024`                    | cap the long side in pixels                         | CDP, macOS    |
| `format: "jpeg"` + `quality: 80` | much smaller for UI content                         | CDP, macOS    |

A tier that cannot honor an option **refuses and names the route out** — it
never quietly returns something else.

`maxPx` is a _budget_, not a fidelity loss: the image is scaled by the
browser **at capture time**, and a vision model downsamples large images to
its own input budget anyway, so capping there keeps every pixel the model
would have seen. A cap smaller than that resolution does discard detail, so
the cap is your explicit choice.

macOS pixels additionally need the **Screen Recording** grant. When it is
missing, ask for it — the OS shows its own prompt:

```
automation_request_consent {kind: "screenRecording"}
```

Accessibility (`kind: "accessibility"`) is the grant for reading and driving
the app tree. A capture never raises either prompt by itself.

## The loop (semantic-first)

Observe through a `view`, act with `returnState`, verify — the agent
reads refs and deltas, not pixels. Each rendered node carries a stable
`ref`; `diff: true` returns only what changed. Screenshots are opt-in
enrichment, and coordinates are the fallback tier (canvas, games,
surfaces no accessibility tree can see), not the primary path.

## Dart plans (primary)

```dart
final plan = AutomationPlan(
  sessions: [
    cdp('browser', uri: Uri.parse('http://127.0.0.1:9222')),
    SessionBinding(name: 'mac', transport: AutomationTransport.osAccessibility),
  ],
  profiles: {'humanish': BehaviorProfile.humanPrior(7)},
  intents: IntentRegistry.fromFiles(['app.intents.json']),
  scenarios: [
    scenario('checkout', steps: [
      navigate(Uri.parse('https://example.com/cart')),
      waitFor([exists(role: 'button', name: 'Checkout')]),
      intent('app', 'fill-email', args: {'text': 'a@b.c'}),
      click(name: 'Checkout', profile: 'humanish', seed: 42),
      exec('flutter', args: ['test']),                    // terminal step
      code((context) async => {'oka': 'call anything'}),  // first-class code
      verifyThat([absent(name: 'Error')]),
      record(const Duration(seconds: 2), '/tmp/out'),      // screencast
      shot('/tmp/cart.png'),
      shot('/tmp/full.png', fullPage: true, maxPx: 1024),
    ]),
  ],
);
final report = await PlanRunner().run(plan, scenarioName: 'checkout');
```

Snapshot export (for agents; refuses code steps):
`planDocument(plan)` → YAML/JSON.

## CLI (snapshots + ad-hoc)

```bash
universal-automation observe  --cdp http://127.0.0.1:9222
universal-automation act      --cdp http://127.0.0.1:9222 --click-name Submit
universal-automation verify   --cdp http://127.0.0.1:9222 --exists role=button,name=Go
universal-automation actions  --cdp http://127.0.0.1:9222
universal-automation screenshot --cdp http://127.0.0.1:9222 --out /tmp/s.png
universal-automation screenshot --cdp http://127.0.0.1:9222 --out /tmp/full.png --full-page
universal-automation screenshot --cdp http://127.0.0.1:9222 --out /tmp/s.jpg --format jpeg --quality 80
universal-automation screenshot --cdp http://127.0.0.1:9222 --out /tmp/tab.png --target-url /checkout
universal-automation run      --plan plan.yaml --scenario checkout --out /tmp/out
universal-automation run      --plan plan.yaml --handles-dir ~/.oka/handles
universal-automation serve    --cdp http://127.0.0.1:9222   # MCP stdio
universal-automation serve    --http 8931                    # MCP POST /mcp

# Desktop tier (focused app; macOS AX / Linux AT-SPI / Windows UIA):
universal-automation observe  --os
universal-automation act      --os --click-name New\ Folder
universal-automation serve    --os                           # MCP over the desktop tier
```

Exit codes: 0 pass, 1 automation failure, 2 usage. Results are JSON on
stdout.

## MCP server setup

For an installed MCP client, use `plugin/mcp.json` as the template. Prefer
`command` `universal-automation` on PATH after `plugin/install.sh`, or set
`UNIVERSAL_AUTOMATION_BIN` to the packaged
`pkgs/universal_automation_toolkit/build/cli/<target>/bundle/bin/universal_automation`
executable. Keep `serve --os` for desktop automation. The AOT bundle is the
recommended route for the native tier because it carries linked native assets.

`plugin/install.sh` runs `dart pub get`, builds with
`dart build cli`, then links the resulting binary into `~/.local/bin` (or
`UNIVERSAL_AUTOMATION_BIN_DIR`). It does not install a source-mode fallback
when the build produces no binary; correct the build first. For source
development, run from `pkgs/universal_automation_toolkit`:

```bash
dart run bin/universal_automation.dart serve --os
```

That source command is a development route, not a fallback implied by the MCP
client configuration. Rebuild and repoint/restart MCP clients after changing
the toolkit or its native driver.

## House rules and gotchas

- **Fail closed**: every plan violation is reported before anything
  attaches; capability gaps fail loudly, never silently degrade.
- **Borrowed sessions**: detaching never closes the target's process.
- Locators are semantic (`role`/accessible `name`) first; CSS is the
  fallback tier. `wait` instead of sleeps — deep links may resolve on
  the previous page's load event.
- macOS tier needs the Accessibility TCC grant for the _host process_
  (the MCP client or terminal that spawned the binary), and the Screen
  Recording grant for pixels. `automation_request_consent` asks for either;
  the OS shows its own prompt.
- A tier that cannot honor a capture option refuses and names the route
  out — it never returns a cheaper capture than the one asked for.
- Multi-session scenarios: `onSession('name', steps)` or per-step
  `session:`; handle bindings resolve via `--set name=uri` or handle
  artifacts under `--handles-dir`.
- For hermetic tests, compose against the family's fake CDP server
  (`package:universal_browser_cdp/universal_browser_cdp_testing.dart`).


## Background browser without CDP (macOS, ADR 0065)

1. `automation_list_apps` → `app: {bundleId: "com.google.Chrome"}`
2. `automation_observe` with `preferWebContent: true` (default) and a `view`
3. `automation_preview` `{op: start, windowId, intervalMs, maxPx}` then `{op: frame, image: true}`
4. `setValue` / `click` by locator, or `clickAt` with `windowId` for window-local semantic hits (no focus steal)

## Computer-use loop (Codex parity, no CDP, ADR 0008)

When the model emits pixel `click(x,y)` / `screenshot` / `type` (not AX locators):

1. `automation_capabilities` — confirm `computerUse.osWindowPixelInjection` on macOS
2. `automation_request_consent` for `accessibility` and `screenRecording` if refusals say so (human approves the OS dialog once)
3. `automation_list_apps` → anchor with `app: {pid}` on every call
4. `automation_computer` `{action: bind}` (optional `windowId`; default = largest on-screen window)
5. `automation_computer` `{action: screenshot}` — image block + `width`/`height`/`scale`; coords are in that image space
6. `click` / `double_click` / `move` / `scroll` / `type` / `keypress` / `wait` on `automation_computer`
7. Rebuild native bridge after driver changes: `./plugin/install.sh`

Semantic `automation_observe` / `automation_act` remain preferred when roles and names exist.
