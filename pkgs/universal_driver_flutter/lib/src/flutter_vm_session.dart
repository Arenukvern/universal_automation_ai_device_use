import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'flutter_vm_client.dart';
import 'flutter_vm_driver.dart';

/// [ResolvedSession] over one VM-service connection — attach-only
/// teardown: [detach] releases the connection and never stops the app.
final class FlutterVmSession implements ResolvedSession {
  /// Creates the session over [client].
  FlutterVmSession(this.binding, FlutterVmDriver driver, this._client)
    : _driver = driver;

  @override
  final SessionBinding binding;

  final FlutterVmDriver _driver;
  final FlutterVmClient _client;

  @override
  AutomationDriver get driver => _driver;

  @override
  Uri? get url => null;

  @override
  BehavioralDriver? asBehavioral() => null;

  @override
  Future<void> detach() => _client.dispose();
}

/// The vmService [DriverFactory] — links the instrumented Flutter tier to
/// the CLI and MCP server (and can be overridden by a composition root's
/// own factory via [SessionRegistry.registerFactory]).
Future<ResolvedSession> flutterVmServiceFactory(
  SessionBinding binding,
  Uri endpoint,
  Duration timeout,
) async {
  final client = await FlutterVmClient.connect(endpoint);
  return FlutterVmSession(binding, FlutterVmDriver(client), client);
}
