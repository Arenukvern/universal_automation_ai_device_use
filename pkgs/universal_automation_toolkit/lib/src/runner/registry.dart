import 'dart:io';

import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_browser_cdp/universal_browser_cdp.dart';
import 'package:universal_browser_webdriver/universal_browser_webdriver.dart';


export 'package:universal_automation_interface/universal_automation_interface.dart'
show DriverFactory, ResolvedSession;

/// A transport named in a plan has no linked driver binding in this
/// build — loud, per the family refuse-not-degrade rule.
class TransportNotLinkedException extends AutomationException {
  /// Creates the exception for [transport].
  TransportNotLinkedException(this.transport, {required String sessionName})
    : super(
        'transport "$transport" has no linked driver in this build '
        '(session "$sessionName"); link its family package or register a '
        'DriverFactory to enable it',
        details: {'transport': transport, 'session': sessionName},
      );

  @override
  String get kind => 'transportNotLinked';

  /// The unlinked transport name.
  final String transport;
}

/// Attaches plan session bindings to live drivers — lazily, cached per
/// binding (and per endpoint for ad-hoc use).
///
/// Attach-only: [ResolvedSession.detach] drops the client's connection
/// and never stops the process behind it (ADR 0037 house rule 2;
/// lifecycle belongs to oka). Transport coverage: CDP, WebDriver, and
/// the OS-native tier (macOS AX / Linux AT-SPI / Windows UIA sidecar)
/// are linked; `vmService` resolves through [factories] registered by
/// composition roots (the instrumented Flutter tier lives in
/// mcp_flutter — ADR 0036 one-way direction).
final class SessionRegistry {
  /// Creates a registry over [bindings]; [overrides] resolve handle
  /// bindings (handle name → endpoint URI); [factories] extend or
  /// replace the built-in per-transport factories.
  SessionRegistry({
    required Map<String, SessionBinding> bindings,
    this.overrides = const {},
    this.attachTimeout = const Duration(seconds: 10),
    Map<AutomationTransport, DriverFactory>? factories,
    this.handleBaseDirectory,
  }) : _bindings = bindings,
       _factories = {...?factories};

  final Map<String, SessionBinding> _bindings;

  /// Handle-name → URI overrides supplied by the caller (CLI `--set`).
  final Map<String, String> overrides;

  /// Attach deadline per session.
  final Duration attachTimeout;

  /// Directory scanned for handle artifacts
  /// (`session-<name>-handle` files holding the endpoint URI), when oka
  /// (or any lifecycle owner) publishes them there; `--set` overrides
  /// win over artifacts.
  final String? handleBaseDirectory;

  final Map<AutomationTransport, DriverFactory> _factories;
  final Map<String, ResolvedSession> _attached = {};
  final Map<String, ResolvedSession> _adHoc = {};

  /// The built-in factories; exposure is read-only.
  Map<AutomationTransport, DriverFactory> get factories =>
      Map.unmodifiable(_factories);

  /// Registers (or replaces) the factory for [transport].
  void registerFactory(AutomationTransport transport, DriverFactory factory) {
    _factories[transport] = factory;
  }

  /// Attaches (or returns the cached) session named [name].
  Future<ResolvedSession> attach(String name) async {
    final cached = _attached[name];
    if (cached != null) return cached;
    final binding = _bindings[name];
    if (binding == null) {
      throw EndpointUnreachableException(
        'unknown session "$name"',
        details: {'sessions': _bindings.keys.toList()},
      );
    }
    final resolved = await _resolve(binding);
    _attached[name] = resolved;
    return resolved;
  }

  /// Attaches (or returns the cached) ad-hoc session on an endpoint-free
  /// transport — the OS-native tier: the macOS AX driver binds the
  /// focused application, Linux AT-SPI and Windows UIA fall back to
  /// their session defaults. The `oka:focused` sentinel marks the
  /// binding so resolution never demands a URI; a driver still reads it
  /// when an optional refinement (a11y bus address, UIA sidecar binary).
  Future<ResolvedSession> attachFocused(AutomationTransport transport) {
    final key = '${transport.name}|focused';
    final cached = _adHoc[key];
    if (cached != null) return Future.value(cached);
    return _resolve(
      SessionBinding(
        name: key,
        transport: transport,
        uri: Uri.parse('oka:focused'),
      ),
    ).then((resolved) {
      _adHoc[key] = resolved;
      return resolved;
    });
  }

  /// Attaches (or returns the cached) ad-hoc session anchored to one
  /// running application — the ADR 0064 target anchoring. [pid] binds
  /// directly; [bundleId]/[name] resolve through the running-apps record
  /// at attach. No target means the focused binding (the convenience
  /// default, never a precondition). The anchor URI
  /// (`ax://pid/<n>` / `ax://bundle/<id>` / `ax://name/<name>`) is the
  /// plan-document shape too — a plan session with that uri lands here.
  Future<ResolvedSession> attachApp(
    AutomationTransport transport, {
    int? pid,
    String? bundleId,
    String? name,
  }) {
    if (transport != AutomationTransport.osAccessibility) {
      throw DriverUnsupportedException(
        'app targeting is the OS-tier anchor vocabulary (ADR 0064); '
        'transport "${transport.name}" has no application anchors — pass '
        'an endpoint instead',
      );
    }
    if (pid == null && bundleId == null && name == null) {
      return attachFocused(transport);
    }
    if (pid != null) {
      if (pid <= 0) {
        throw SpecViolationException(const ['app.pid must be a positive pid']);
      }
      return attachUri(Uri.parse('ax://pid/$pid'), transport);
    }
    final value = bundleId ?? name;
    if (value == null || value.isEmpty) {
      throw SpecViolationException(const [
        'app.bundleId / app.name must be non-empty when given',
      ]);
    }
    return attachUri(
      Uri.parse(bundleId != null ? 'ax://bundle/$value' : 'ax://name/$value'),
      transport,
    );
  }

  /// Attaches (or returns the cached) ad-hoc session at [uri] — the
  /// per-call endpoint override used by MCP tools.
  Future<ResolvedSession> attachUri(Uri uri, AutomationTransport transport) {
    final key = '${transport.name}|$uri';
    final cached = _adHoc[key];
    if (cached != null) return Future.value(cached);
    return _resolve(
      SessionBinding(name: key, transport: transport, uri: uri),
    ).then((resolved) {
      _adHoc[key] = resolved;
      return resolved;
    });
  }

  Future<ResolvedSession> _resolve(SessionBinding binding) async {
    final uri = resolveEndpoint(binding);
    final factory = _factories[binding.transport] ??
        _builtinFactory(binding.transport);
    if (factory == null) {
      throw TransportNotLinkedException(
        binding.transport.name,
        sessionName: binding.name,
      );
    }
    if (uri == null && !_endpointFree(binding.transport)) {
      throw EndpointUnreachableException(
        'session "${binding.name}" has no resolvable endpoint: handle '
        '"${binding.handle}" resolved to nothing; pass --set '
        '${binding.handle}=<uri>, publish the handle artifact under '
        'the handles directory, or use an endpoint-free binding',
        details: {'session': binding.name, 'handle': binding.handle},
      );
    }
    return factory(binding, uri ?? Uri.parse('oka:focused'), attachTimeout);
  }

  /// Endpoint-free transports (the macOS AX tier drives the focused
  /// application and needs no URI).
  static bool _endpointFree(AutomationTransport transport) =>
      transport == AutomationTransport.osAccessibility && Platform.isMacOS;

  /// Resolves a binding's endpoint: explicit uri, then `--set`-style
  /// overrides, then handle artifacts under [handleBaseDirectory].
  Uri? resolveEndpoint(SessionBinding binding) {
    if (binding.uri != null) return binding.uri;
    final handle = binding.handle;
    if (handle == null) return null;
    final override = overrides[handle];
    if (override != null) return Uri.tryParse(override);
    final base = handleBaseDirectory;
    if (base == null) return null;
    final artifact = File('$base/$handle');
    if (!artifact.existsSync()) return null;
    final value = artifact.readAsStringSync().trim();
    return value.isEmpty ? null : Uri.tryParse(value);
  }

  /// The built-in factories: the pure-Dart protocol tiers only (ADR
  /// 0004). The desktop OS tier is registered by the composition root
  /// (`desktopOsAccessibilityFactory`) — or replaced by an embedder's
  /// own tier; an unregistered transport is the loud
  /// [TransportNotLinkedException], never a silent fallback.
  DriverFactory? _builtinFactory(AutomationTransport transport) =>
      switch (transport) {
        AutomationTransport.cdp => _attachCdp,
        AutomationTransport.webdriver => _attachWebdriver,
        _ => null,
      };

  static Future<ResolvedSession> _attachCdp(
    SessionBinding binding,
    Uri endpoint,
    Duration timeout,
  ) async {
    final session = await CdpBrowserSession.attach(endpoint, timeout: timeout);
    return _CdpResolvedSession(binding, session);
  }

  static Future<ResolvedSession> _attachWebdriver(
    SessionBinding binding,
    Uri endpoint,
    Duration timeout,
  ) async {
    final client = WebDriverClient(endpoint);
    await client.newSession();
    return _WebdriverResolvedSession(binding, client);
  }

  /// Detaches every session this registry opened. Idempotent.
  Future<void> detachAll() async {
    for (final session in [
      ..._attached.values,
      ..._adHoc.values,
    ]) {
      await session.detach();
    }
    _attached.clear();
    _adHoc.clear();
  }
}


final class _WebdriverResolvedSession implements ResolvedSession {
  _WebdriverResolvedSession(this.binding, this.client)
    : driver = WebDriverDriver(client);

  final WebDriverClient client;

  @override
  final SessionBinding binding;

  @override
  final AutomationDriver driver;

  @override
  Uri? get url => null;

  @override
  BehavioralDriver? asBehavioral() => null;

  @override
  Future<void> detach() => client.deleteSession();
}


final class _CdpResolvedSession implements ResolvedSession {
  _CdpResolvedSession(this.binding, this.session) {
    // Track the live surface URL: the attach-time target info is a
    // snapshot and goes stale on the first navigation.
    final initial = session.page.target.url;
    _url = initial.isEmpty ? null : Uri.tryParse(initial);
    session.page.connection.on('Page.frameNavigated').listen((event) {
      final frame = event.params['frame'] as Map<String, Object?>?;
      if (frame == null || frame.containsKey('parentId')) return;
      final navigatedTo = frame['url'];
      if (navigatedTo is String && navigatedTo.isNotEmpty) {
        _url = Uri.tryParse(navigatedTo);
      }
    });
  }

  Uri? _url;

  final CdpBrowserSession session;
  BehavioralCdpDriver? _behavioral;

  @override
  final SessionBinding binding;

  @override
  AutomationDriver get driver => session.driver;

  @override
  Uri? get url => _url;

  @override
  BehavioralDriver? asBehavioral() =>
      // One behavioral face per session: pointer continuity persists
      // across a scenario's profiled steps.
      _behavioral ??= BehavioralCdpDriver(session.page);

  @override
  Future<void> detach() => session.detach();
}
