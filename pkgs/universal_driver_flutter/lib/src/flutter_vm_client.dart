import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart' as vm_io;

/// Service-extension names of the MCP toolkit wire (`ext.mcp.toolkit.<verb>`).
///
/// Literals mirror `flutter_mcp_toolkit_core.ToolkitExtensionNames` — the
/// registering side's contract source. A renamed verb surfaces here as a
/// loud `-32601` on a live app instead of silent drift.
abstract final class ToolkitWire {
  /// Service-extension prefix shared with the app side.
  static const String prefix = 'ext.mcp.toolkit';

  /// Semantic snapshot of the visible widget tree.
  static const String semanticSnapshot = '$prefix.semantic_snapshot';

  /// Taps a widget by snapshot ref.
  static const String tapWidget = '$prefix.tap_widget';

  /// Enters text into a widget by snapshot ref.
  static const String enterText = '$prefix.enter_text';

  /// Presses a keyboard key.
  static const String pressKey = '$prefix.press_key';

  /// Scrolls by direction.
  static const String scroll = '$prefix.scroll';

  /// Navigates a registered named route.
  static const String navigate = '$prefix.navigate';

  /// Base64 screenshots of all views; `compress: false` keeps PNG bytes.
  static const String viewScreenshots = '$prefix.view_screenshots';
}

/// Call signature of one VM service extension invocation — the seam tests
/// answer with canned envelopes instead of a live VM.
typedef ExtensionCall =
    Future<Map<String, dynamic>> Function(
      String name, {
      Map<String, Object?> args,
    });

/// Owns the VM-service connection to one running Flutter app and binds to
/// the isolate that registered the MCP toolkit.
///
/// Reconnection law (measured in flutter_mcp_harness 2026-10-05): heavy
/// `view_screenshots` traffic drops the websocket while the app lives on;
/// every later call then throws the local `Service connection disposed`.
/// [callExtension] therefore re-establishes the socket ONCE per call on a
/// connection-level failure, and re-binds on a `-32601` (an early attach
/// can land on an isolate that registers the toolkit later).
final class FlutterVmClient {
  FlutterVmClient._(this.httpUri, this._service, this._mainIsolate);

  /// The http VM-service URI this client (re)connects through.
  final Uri httpUri;

  vm.VmService _service;
  vm.IsolateRef _mainIsolate;

  /// The isolate id this client is bound to (diagnostics).
  String? get boundIsolateId => _mainIsolate.id;

  /// Connects to an `http://…/TOKEN=` (or already-`ws://`) VM service URI
  /// and binds to the toolkit isolate. Throws
  /// [EndpointUnreachableException] when nothing answers or no isolate
  /// carries the toolkit registration (the app must bind the MCP toolkit
  /// in debug or profile mode) — typed and loud, per the family rule.
  static Future<FlutterVmClient> connect(Uri endpoint) async {
    final vm.VmService service;
    try {
      service = await vm_io.vmServiceConnectUri(
        canonicalVmServiceWsUri(endpoint).toString(),
      );
    } on Exception catch (error) {
      throw EndpointUnreachableException(
        'no VM service answering at $endpoint ($error)',
        details: {'endpoint': '$endpoint'},
      );
    }
    final vmName;
    try {
      vmName = await service.getVM();
    } on Exception catch (error) {
      await service.dispose();
      throw EndpointUnreachableException(
        'VM at $endpoint stopped answering ($error)',
        details: {'endpoint': '$endpoint'},
      );
    }
    for (final ref in [...?vmName.isolates]) {
      try {
        final isolate = await service.getIsolate(ref.id!);
        final extensions = List<String>.from(isolate.extensionRPCs ?? const []);
        if (extensions.any((name) => name.startsWith(ToolkitWire.prefix))) {
          return FlutterVmClient._(endpoint, service, ref);
        }
      } on vm.RPCError {
        continue;
      }
    }
    await service.dispose();
    throw EndpointUnreachableException(
      'no MCP toolkit isolate at $endpoint — the app must bind the MCP '
      'toolkit (debug or profile mode)',
      details: {'endpoint': '$endpoint'},
    );
  }

  /// Per-attempt wire bound: a hung handler surfaces as
  /// [TimeoutException] instead of wedging an unattended driver.
  static const Duration _callTimeout = Duration(seconds: 30);

  /// Calls a registered service extension and returns its JSON response.
  ///
  /// Args must be JSON-encodable; the app side validates types. Three
  /// recoveries, each ONE retry before rethrowing: a `-32601` re-binds to
  /// the (late-registering) toolkit isolate; a connection-level failure
  /// reconnects the dropped websocket; a [StateError] from a disposed
  /// connection takes the same reconnect path.
  Future<Map<String, dynamic>> callExtension(
    String name, {
    Map<String, Object?> args = const <String, Object?>{},
  }) async {
    try {
      return await _callExtension(name, args).timeout(_callTimeout);
    } on vm.RPCError catch (error) {
      if (error.code == -32601) {
        await _rebindToToolkitIsolate();
        return _callExtension(name, args).timeout(_callTimeout);
      }
      if (!_isConnectionLevel(error)) rethrow;
      await _reconnect();
      return _callExtension(name, args).timeout(_callTimeout);
    } on StateError {
      await _reconnect();
      return _callExtension(name, args).timeout(_callTimeout);
    }
  }

  Future<Map<String, dynamic>> _callExtension(
    String name,
    Map<String, Object?> args,
  ) async {
    final response = await _service.callServiceExtension(
      name,
      isolateId: _mainIsolate.id,
      args: args,
    );
    return response.json ?? <String, dynamic>{};
  }

  /// True when [error] names a dead connection rather than an app-side
  /// refusal (the local disposed error, the protocol's
  /// `kConnectionDisposed`, or a socket failure).
  bool _isConnectionLevel(vm.RPCError error) {
    if (error.code == -32010) return true;
    if (error.code == -32000 &&
        error.message.contains('Service connection disposed')) {
      return true;
    }
    final message = error.message.toLowerCase();
    return message.contains('connection closed') ||
        message.contains('websocket') ||
        message.contains('socket');
  }

  Future<void> _reconnect() async {
    _service = await vm_io.vmServiceConnectUri(
      canonicalVmServiceWsUri(httpUri).toString(),
    );
    await _rebindToToolkitIsolate();
  }

  /// Re-scans the VM's isolates and re-binds to one carrying the MCP
  /// toolkit registration. No-op when none does — callers keep seeing the
  /// original error.
  Future<void> _rebindToToolkitIsolate() async {
    final vmName = await _service.getVM();
    for (final ref in [...?vmName.isolates]) {
      try {
        final isolate = await _service.getIsolate(ref.id!);
        final extensions = List<String>.from(isolate.extensionRPCs ?? const []);
        if (extensions.any((name) => name.startsWith(ToolkitWire.prefix))) {
          _mainIsolate = ref;
          return;
        }
      } on vm.RPCError {
        continue;
      }
    }
  }

  /// Releases the VM-service connection. Idempotent; never stops the app.
  Future<void> dispose() async {
    _service.dispose();
  }
}

/// Converts an http VM service URI to the WebSocket form its clients dial:
/// `http://127.0.0.1:PORT/TOKEN=` → `ws://127.0.0.1:PORT/TOKEN/ws`.
/// Idempotent: a URI already in ws shape must not grow a second `/ws`.
Uri canonicalVmServiceWsUri(Uri httpUri) {
  final path = httpUri.path.endsWith('/')
      ? '${httpUri.path}ws'
      : httpUri.path.endsWith('/ws')
      ? httpUri.path
      : '${httpUri.path}/ws';
  return httpUri.replace(scheme: 'ws', path: path);
}
