import 'dart:io';

import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_driver_linux/universal_driver_linux.dart';
import 'package:universal_driver_macos/universal_driver_macos.dart';
import 'package:universal_driver_windows/universal_driver_windows.dart';

import '../runner/registry.dart';

/// The desktop OS-tier `DriverFactory` (ADR 0004): the ONLY place in the
/// toolkit that imports native driver packages. Composition roots that
/// want the real desktop tier register it explicitly
/// (`factories: {osAccessibility: desktopOsAccessibilityFactory}`); the
/// embeddable toolkit core (registry, runner, MCP face) stays
/// native-import-free, so a Flutter embed compiles without the desktop
/// drivers and registers its own tiers instead.
Future<ResolvedSession> desktopOsAccessibilityFactory(
  SessionBinding binding,
  Uri endpoint,
  Duration attachTimeout,
) async {
  if (Platform.isMacOS) {
    return _attachMacos(binding, endpoint);
  }
  if (Platform.isLinux) {
    final bus = DBusAtspiBus(
      a11yAddress: endpoint.scheme == 'unix' ? endpoint.path : null,
    );
    return _DriverSession(binding, AtspiDriver(bus));
  }
  if (Platform.isWindows) {
    return _DriverSession(
      binding,
      await UiaDriver.connect(
        binary: endpoint.scheme == 'file' ? endpoint.toFilePath() : null,
      ),
    );
  }
  throw TransportNotLinkedException(
    '${binding.transport.name} on ${Platform.operatingSystem}',
    sessionName: binding.name,
  );
}

/// The macOS attach: focused by default, or anchored to one running
/// application through an `ax://` URI (ADR 0064). Bundle/name anchors
/// resolve through the running-apps record at attach; an unknown
/// target is a loud element-not-found naming the search key.
Future<ResolvedSession> _attachMacos(
  SessionBinding binding,
  Uri endpoint,
) async {
  final anchor = _parseAxAnchor(endpoint);
  if (anchor == null) {
    return _MacosResolvedSession(binding, BehavioralMacosDriver());
  }
  final (kind, value) = anchor;
  var pid = switch (kind) {
    'pid' => int.tryParse(value),
    _ => null,
  };
  if (kind != 'pid') {
    final probe = MacosDriver();
    try {
      final apps = await probe.runningApps();
      MacosApp? match;
      switch (kind) {
        case 'bundle':
          match = apps.where((app) => app.bundleId == value).firstOrNull;
        case 'name':
          match = apps.where((app) => app.name == value).firstOrNull;
      }
      if (match == null) {
        throw ElementNotFoundException(
          'application',
          '$kind "$value" (running: '
              '${apps.map((app) => app.name).join(", ")})',
        );
      }
      pid = match.pid;
    } finally {
      await probe.close();
    }
  }
  if (pid == null || pid <= 0) {
    throw ElementNotFoundException('application', 'pid "$value"');
  }
  // Attaching an assistive client must enable the target's native tree.
  // Flutter creates that tree lazily; merely enumerating AXWindows can
  // otherwise return a window with no product controls. This request is
  // scoped to the explicit app anchor and never activates the application.
  requestAppAccessibility(pid);
  return _MacosResolvedSession(binding, BehavioralMacosDriver(targetPid: pid));
}

/// `(kind, value)` from an `ax://<kind>/<value>` anchor URI; `null`
/// for any other shape (the focused sentinel, a11y refinements). The
/// value percent-decodes (URIs encode spaces: `ax://name/Text%20Edit`).
(String, String)? _parseAxAnchor(Uri endpoint) {
  if (endpoint.scheme != 'ax') return null;
  final kind = endpoint.host;
  final raw = endpoint.path.startsWith('/')
      ? endpoint.path.substring(1)
      : endpoint.path;
  if (raw.isEmpty || !const {'pid', 'bundle', 'name'}.contains(kind)) {
    throw SpecViolationException([
      'ax:// anchors are ax://pid/<pid>, ax://bundle/<bundleId>, or '
          'ax://name/<name> (got $endpoint)',
    ]);
  }
  return (kind, Uri.decodeComponent(raw));
}

/// Driver-only resolved session (no behavioral face, no URL).
final class _DriverSession implements ResolvedSession {
  _DriverSession(this.binding, this.driver);

  @override
  final SessionBinding binding;

  @override
  final AutomationDriver driver;

  @override
  Uri? get url => null;

  @override
  BehavioralDriver? asBehavioral() => null;

  @override
  Future<void> detach() => driver.close();
}

final class _MacosResolvedSession implements ResolvedSession {
  _MacosResolvedSession(this.binding, BehavioralMacosDriver macosDriver)
    : macosDriver = macosDriver,
      driver = macosDriver;

  @override
  final SessionBinding binding;

  final BehavioralMacosDriver macosDriver;

  @override
  final AutomationDriver driver;

  @override
  Uri? get url => null;

  @override
  BehavioralDriver? asBehavioral() => macosDriver;

  @override
  Future<void> detach() => driver.close();
}
