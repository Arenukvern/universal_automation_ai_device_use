/// vmService driver over a running Flutter app's MCP toolkit service
/// extensions.
///
/// The instrumented tier's engine face for the `universal_automation_*`
/// CLI and MCP server: attach to a debug/profile Flutter app's Dart VM
/// service, observe its semantic snapshot, act by snapshot ref, and
/// capture background screenshots — in the same vocabulary as the CDP,
/// WebDriver, and OS-native drivers, so agents learn one grammar.
///
/// The wire contract is the MCP toolkit's public service-extension
/// surface (`ext.mcp.toolkit.<verb>`; canonical names live in
/// `flutter_mcp_toolkit_core.ToolkitExtensionNames` on the mcp_flutter
/// side). This package speaks the wire as literals and depends on no
/// mcp_flutter package (ADR 0036 one-way direction) — the same precedent
/// as `universal_capture_flutter`'s screenshot grabber.
///
/// ```dart
/// final session = await flutterVmServiceFactory(
///   binding, Uri.parse('http://127.0.0.1:8181/TOKEN='), timeout);
/// final snapshot = await session.driver.snapshot();
/// await session.driver.perform(ClickAction(css: 's_12'));
/// ```
///
/// Attach-only: [FlutterVmSession.detach] releases the VM-service
/// connection and never stops the app behind it.
library;

export 'src/flutter_vm_client.dart';
export 'src/flutter_vm_driver.dart';
export 'src/flutter_vm_session.dart';
