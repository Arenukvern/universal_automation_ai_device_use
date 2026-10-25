import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_automation_semantics/universal_automation_semantics.dart';
import 'package:xsoulspace_permission_core/xsoulspace_permission_core.dart';

import '../capture/capture_request.dart';
import '../consent/consent_gated_driver.dart';
import '../plan/checks.dart';
import '../plan/plan.dart';
import '../plan/steps.dart';
import '../runner/jobs.dart';
import '../runner/registry.dart';
import '../runner/runner.dart';

/// MCP protocol versions this server speaks; the client's advertised
/// version is echoed when supported, else the newest one is offered.
const mcpSupportedVersions = ['2024-11-05', '2025-03-26', '2025-06-18'];

/// Server identity advertised at `initialize`.
const mcpServerInfo = {
  'name': 'universal-automation-toolkit',
  'title': 'Universal Automation Toolkit',
  'version': '0.1.0',
};

/// The toolkit's MCP face: observe/act/verify ad-hoc verbs plus plan
/// tools, over newline-delimited JSON-RPC 2.0 on stdio.
///
/// The handler is separable from the stdio shell so tests exercise the
/// protocol in-process.
final class ToolkitMcpServer {
  final List<Map<String, Object?>> _outbound = [];

  /// Server-initiated notices queued by [handle]. The stdio loop writes
  /// them; callers that only use [handle] can read them here.
  List<Map<String, Object?>> takeOutbound() {
    if (_outbound.isEmpty) return const [];
    final copy = List<Map<String, Object?>>.of(_outbound);
    _outbound.clear();
    return copy;
  }

  /// Creates a server. [endpoints] is the per-transport endpoint
  /// registry backing ad-hoc verbs (ADR 0003): explicit per-call
  /// arguments win, then this registry, then [handlesDirectory] +
  /// [browserHandle] (an oka-published handle artifact holding an
  /// absolute URI — e.g. a moli `serve` CDP endpoint). [defaultEndpoint]
  /// is the pre-ADR 0003 convenience: it seeds the cdp tier when
  /// [endpoints] carries none. [defaultTransport] selects the tier
  /// verbs attach to when a call passes neither `transport` nor
  /// `endpoint`. [factories] extends or replaces the built-in
  /// per-transport drivers (the composition-root seam, e.g. the
  /// instrumented Flutter tier registered by mcp_flutter).
  /// [jobsDirectory] hosts the resident job plane's receipts (ADR 0064);
  /// `null` defaults to `~/.uatk/jobs`.
  ToolkitMcpServer({
    Uri? defaultEndpoint,
    Map<AutomationTransport, Uri> endpoints = const {},
    AutomationTransport defaultTransport = AutomationTransport.cdp,
    Map<String, String> overrides = const {},
    Map<AutomationTransport, DriverFactory>? factories,
    String? jobsDirectory,
    this.handlesDirectory,
    this.browserHandle,
    PermissionGate? consentGate,
    this.consentOrigin = 'universal-automation-mcp',
  }) : _defaultTransport = defaultTransport,
       _endpoints = {
         if (defaultEndpoint != null) AutomationTransport.cdp: defaultEndpoint,
         ...endpoints,
       },
       _overrides = overrides,
       _extraFactories = factories,
       _consentGate = consentGate,
       _jobsDirectory = jobsDirectory ?? _defaultJobsDirectory();

  /// The tier a call attaches to when it names neither `transport` nor
  /// `endpoint` (ADR 0003).
  final AutomationTransport _defaultTransport;

  /// Per-transport endpoints: CLI flags > env > handle artifacts,
  /// resolved by the composition root before the server exists.
  final Map<AutomationTransport, Uri> _endpoints;

  /// Directory of handle artifacts (`<handle>` files holding an
  /// absolute endpoint URI), published by oka or any lifecycle owner.
  final String? handlesDirectory;

  /// Handle name backing the browser tier when no `--cdp` endpoint is
  /// configured (ADR 0003's optional browser, e.g. a moli serve).
  final String? browserHandle;

  final Map<String, String> _overrides;
  final Map<AutomationTransport, DriverFactory>? _extraFactories;

  /// The OS-consent chain for automation surfaces (ADR 0064's contract
  /// half on the [ConsentGatedDriver]): when set, resolved sessions'
  /// drivers ask `accessibility` before snapshots/acts and
  /// `screenRecording` before screenshots. `null` composes no gate —
  /// the drivers' typed TCC exceptions remain the only consent surface.
  final PermissionGate? _consentGate;

  /// Attribution for consent requests this server raises.
  final String consentOrigin;
  final Map<String, Observation> _lastObservations = {};
  final String _jobsDirectory;
  SessionRegistry? _registry;
  JobQueue? _jobQueue;

  /// `~/.uatk/jobs`, or a temp sibling when HOME is unavailable.
  static String _defaultJobsDirectory() {
    final home = Platform.environment['HOME'];
    return home == null
        ? '${Directory.systemTemp.path}/uatk-jobs'
        : '$home/.uatk/jobs';
  }

  JobQueue get _jobs => _jobQueue ??= JobQueue(
    directory: _jobsDirectory,
    factories: _extraFactories,
    handlesDirectory: handlesDirectory,
  );

  SessionRegistry get _sessions {
    final existing = _registry;
    if (existing != null) return existing;
    final registry = SessionRegistry(
      bindings: const {},
      overrides: _overrides,
      factories: _extraFactories,
    );
    _registry = registry;
    return registry;
  }

  /// Handles one decoded JSON-RPC message; returns the full response
  /// (`{id, result}` or `{id, error}`), or `null` for notifications.
  Future<Map<String, Object?>?> handle(Map<String, Object?> message) async {
    final id = message['id'];
    final method = message['method'];
    if (method is! String) {
      return id == null ? null : _error(id, -32600, 'method missing');
    }
    final isNotification = id == null;
    final params = message['params'];
    try {
      switch (method) {
        case 'initialize':
          return _result(id, await _initialize(params));
        case 'notifications/initialized':
          _outbound.addAll([
            <String, Object?>{
              'jsonrpc': '2.0',
              'method': 'notifications/tools/list_changed',
            },
            <String, Object?>{
              'jsonrpc': '2.0',
              'method': 'notifications/resources/list_changed',
            },
            <String, Object?>{
              'jsonrpc': '2.0',
              'method': 'notifications/prompts/list_changed',
            },
          ]);
          return null;
        case 'notifications/cancelled':
          return null;
        case 'ping':
          return _result(id, <String, Object?>{});
        case 'tools/list':
          return _result(id, {'tools': toolDescriptors()});
        case 'resources/list':
          return _result(id, {'resources': <Object?>[]});
        case 'resources/templates/list':
          return _result(id, {'resourceTemplates': <Object?>[]});
        case 'prompts/list':
          return _result(id, {'prompts': <Object?>[]});
        case 'tools/call':
          if (isNotification) return null;
          return _result(id, await _toolsCall(params));
        default:
          if (isNotification) return null;
          return _error(id, -32601, 'unknown method: $method');
      }
    } on McpToolError catch (error) {
      return isNotification
          ? null
          : _result(id, {
              'content': [
                {'type': 'text', 'text': error.message},
                if (error.details != null && error.details!.isNotEmpty)
                  {'type': 'text', 'text': jsonEncode(error.details)},
              ],
              'isError': true,
            });
    } on Object catch (error) {
      return isNotification
          ? null
          : _error(id, -32603, 'internal error: $error');
    }
  }

  Map<String, Object?> _initialize(Object? params) {
    final requested = params is Map<String, Object?>
        ? params['protocolVersion']
        : null;
    final version = mcpSupportedVersions.contains(requested)
        ? requested! as String
        : mcpSupportedVersions.last;
    return {
      'protocolVersion': version,
      'capabilities': {
        'tools': {'listChanged': true},
        'resources': {'subscribe': false, 'listChanged': true},
        'prompts': {'listChanged': true},
      },
      'serverInfo': mcpServerInfo,
      'instructions':
          'Universal automation toolkit (observe/act/verify). Call '
          'automation_capabilities first: it reports which tiers this '
          'server has configured, which verbs work where, and how the '
          'browser tier is wired. Desktop tier (osAccessibility) works '
          'immediately; navigate opens the system browser there. Honor '
          'list-changed notices and call tools/list, resources/list, and '
          'prompts/list again.',
    };
  }

  Future<Map<String, Object?>> _toolsCall(Object? params) async {
    if (params is! Map<String, Object?>) {
      throw const McpToolError('tools/call params must be an object');
    }
    final name = params['name'];
    if (name is! String) throw const McpToolError('tools/call needs a name');
    final arguments =
        (params['arguments'] as Map<Object?, Object?>? ?? const {}).map(
          (key, value) => MapEntry('$key', value),
        );
    final Map<String, Object?> payload;
    try {
      payload = await switch (name) {
        'automation_observe' => _observe(arguments),
        'automation_act' => _act(arguments),
        'automation_verify' => _verify(arguments),
        'automation_screenshot' => _screenshot(arguments),
        'automation_list_apps' => _listApps(arguments),
        'automation_request_consent' => _requestConsent(arguments),
        'automation_validate_plan' => _validatePlan(arguments),
        'automation_run_plan' => _runPlan(arguments),
        'automation_run_background' => _runBackground(arguments),
        'automation_job' => _jobStatus(arguments),
        'automation_capabilities' => _capabilities(),
        _ => throw McpToolError('unknown tool: $name'),
      };
    } on FormatException catch (error) {
      throw McpToolError(error.message);
    } on AutomationException catch (error) {
      // Tool-level automation failures are results with isError, not
      // protocol errors (MCP contract). Details survive the boundary
      // (ADR 0003): the prose block stays first, a JSON block carries
      // kind + structured details (remedies, pids, violations).
      throw McpToolError(
        '${error.kind}: ${error.message}',
        details: {'kind': error.kind, ...error.details},
      );
    }
    // A screenshot with `image: true` rides as a second content block;
    // the reserved key never reaches the JSON text.
    final image = payload.remove('_imageContent');
    return {
      'content': [
        {'type': 'text', 'text': jsonEncode(payload)},
        if (image != null) image,
      ],
      'isError': false,
    };
  }

  /// Parses a per-call `transport` argument; `null` when absent, loud
  /// on an unknown name.
  static AutomationTransport? parseTransport(Object? value) {
    if (value == null) return null;
    final transport = switch ('$value') {
      'cdp' => AutomationTransport.cdp,
      'webdriver' => AutomationTransport.webdriver,
      'os' || 'osAccessibility' => AutomationTransport.osAccessibility,
      _ => null,
    };
    if (transport == null) {
      throw McpToolError(
        'unknown transport "$value" (cdp | webdriver | osAccessibility)',
      );
    }
    return transport;
  }

  Future<ResolvedSession> _session(
    Map<String, Object?> arguments, {
    String? affinityVerb,
  }) async {
    final session = await _attachSession(arguments, affinityVerb: affinityVerb);
    final gate = _consentGate;
    if (gate == null) return session;
    return _ConsentSession(
      session,
      ConsentGatedDriver(
        session.driver,
        gate: gate,
        requestOrigin: consentOrigin,
        subject: session.url?.toString(),
      ),
    );
  }

  /// The verbs that have no desktop-tier meaning (ADR 0003): when the
  /// caller names none of `transport`/`endpoint`, the default tier is
  /// the desktop, and a browser tier is configured, these attach to the
  /// browser instead — and the tool result reports `routedTo`.
  static const instrumentedAffinityVerbs = {'navigate', 'evaluate', 'invoke'};

  /// The configured browser tier, cdp preferred (ADR 0003): the
  /// endpoint registry first, then the `browserHandle` artifact under
  /// [handlesDirectory] (an oka-published handle — the file holds an
  /// absolute URI; the cdp tier is the default reading, matching moli
  /// and debug-port endpoints).
  ({AutomationTransport transport, Uri endpoint})? _configuredBrowser() {
    final cdp = _endpoints[AutomationTransport.cdp];
    if (cdp != null) return (transport: AutomationTransport.cdp, endpoint: cdp);
    final handle = browserHandle;
    final dir = handlesDirectory;
    if (handle != null && dir != null) {
      final artifact = File('$dir/$handle');
      if (artifact.existsSync()) {
        final value = artifact.readAsStringSync().trim();
        final uri = value.isEmpty ? null : Uri.tryParse(value);
        if (uri != null && uri.hasScheme) {
          return (transport: AutomationTransport.cdp, endpoint: uri);
        }
      }
    }
    final webdriver = _endpoints[AutomationTransport.webdriver];
    if (webdriver != null) {
      return (transport: AutomationTransport.webdriver, endpoint: webdriver);
    }
    return null;
  }

  /// True when this call's arguments would affinity-route to the
  /// browser tier (the same predicate [_attachSession] applies).
  bool _willRouteToBrowser(Map<String, Object?> arguments, String? verb) =>
      verb != null &&
      instrumentedAffinityVerbs.contains(verb) &&
      parseTransport(arguments['transport']) == null &&
      arguments['endpoint'] == null &&
      _defaultTransport == AutomationTransport.osAccessibility &&
      _configuredBrowser() != null;

  Future<ResolvedSession> _attachSession(
    Map<String, Object?> arguments, {
    String? affinityVerb,
  }) async {
    final transport = parseTransport(arguments['transport']);
    final endpointValue = arguments['endpoint'];
    if (transport == null &&
        endpointValue == null &&
        affinityVerb != null &&
        instrumentedAffinityVerbs.contains(affinityVerb) &&
        _defaultTransport == AutomationTransport.osAccessibility) {
      // ADR 0003 affinity routing: an instrumented-only verb on a
      // desktop-default server follows the configured browser tier.
      final browser = _configuredBrowser();
      if (browser != null) {
        return _sessions.attachUri(browser.endpoint, browser.transport);
      }
    }
    final resolvedTransport = transport ?? _defaultTransport;
    if (resolvedTransport == AutomationTransport.osAccessibility) {
      final app = arguments['app'];
      if (app is Map<Object?, Object?>) {
        // The ADR 0064 anchor: bind the named application, not focus.
        final pid = app['pid'];
        return _sessions.attachApp(
          resolvedTransport,
          pid: pid is int ? pid : (pid is num ? pid.toInt() : null),
          bundleId: app['bundleId'] is String
              ? app['bundleId'] as String
              : null,
          name: app['name'] is String ? app['name'] as String : null,
        );
      }
      if (endpointValue == null) {
        // No anchor: the desktop tier binds the focused application.
        return _sessions.attachFocused(resolvedTransport);
      }
    }
    Uri? uri;
    if (endpointValue != null) {
      uri = Uri.tryParse('$endpointValue');
      if (uri == null || !uri.hasScheme) {
        throw McpToolError('endpoint must be an absolute URI: $endpointValue');
      }
    }
    uri ??= _endpoints[resolvedTransport];
    if (uri == null) {
      throw McpToolError(
        'no endpoint for transport "${resolvedTransport.name}": start '
        'serve with --cdp/--webdriver/--os, set env '
        'UNIVERSAL_AUTOMATION_CDP (or --browser-handle for an '
        'oka-published browser), or pass "endpoint"/"transport" per '
        'call — automation_capabilities reports what this server sees',
        details: {
          'transport': resolvedTransport.name,
          'remedy': 'configure the tier or pass endpoint per call',
        },
      );
    }
    return _sessions.attachUri(
      _withTargetSelector(uri, arguments),
      resolvedTransport,
    );
  }

  /// The endpoint with the browser-tab selector folded in.
  ///
  /// The selector rides the endpoint URI (the same place the OS tier
  /// encodes its app anchor), so the choice reaches the browser tier
  /// without a second channel. It applies to the CDP tier only.
  Uri _withTargetSelector(Uri uri, Map<String, Object?> arguments) {
    final id = arguments['targetId'];
    final url = arguments['targetUrl'];
    final title = arguments['targetTitle'];
    if (id == null && url == null && title == null) {
      return uri;
    }
    return uri.replace(
      fragment: Uri(
        queryParameters: {
          if (id is String) 'targetId': id,
          if (url is String) 'targetUrl': url,
          if (title is String) 'targetTitle': title,
        },
      ).query,
    );
  }

  Future<Map<String, Object?>> _observe(Map<String, Object?> arguments) async {
    final session = await _session(arguments);
    final snapshot = await session.driver.snapshot();
    final base = {
      'endpoint':
          '${session.binding.resolveUri(_overrides) ?? _endpoints[session.binding.transport]}',
      'transport': session.binding.transport.name,
      'url': session.url?.toString(),
    };
    final viewValue = arguments['view'];
    final at = arguments['at'];
    if (viewValue == null && at is! Map<Object?, Object?>) {
      // No view, no grounding point: the raw tree (counts + full
      // snapshot JSON).
      return {...base, 'snapshot': snapshot.toJson()};
    }
    // A view asked: the rendered observation + ref index replace the
    // raw tree (token economy; omit `view` for the raw form). An `at`
    // point grounds to the innermost node covering it (ADR 0053).
    final observation = Observation.of(
      snapshot,
      viewValue == null
          ? const SemanticView()
          : SemanticView.fromJson(viewValue),
    );
    final key = session.binding.name;
    final previous = arguments['diff'] == true ? _lastObservations[key] : null;
    _lastObservations[key] = observation;
    return {
      ...base,
      'view': observation.toJson(),
      if (previous != null) 'delta': observation.diff(previous).render(),
      if (at is Map<Object?, Object?> && at['x'] is num && at['y'] is num)
        'at': _groundedAt(
          observation,
          (at['x']! as num).toDouble(),
          (at['y']! as num).toDouble(),
        ),
    };
  }

  /// The observe-at grounding read (ADR 0053): innermost walked node
  /// whose bounds contain the point; a miss fails the tool call.
  Map<String, Object?> _groundedAt(
    Observation observation,
    double x,
    double y,
  ) {
    final observed = observation.nodeAt(x, y);
    return {
      'ref': observed.ref,
      'role': observed.node.role,
      if (observed.node.name != null) 'name': observed.node.name,
      'x': x,
      'y': y,
    };
  }

  Future<Map<String, Object?>> _act(Map<String, Object?> arguments) async {
    final action = arguments['action'];
    if (action is! String) {
      throw const McpToolError('automation_act needs an action');
    }
    final actionBody = <String, Object?>{};
    switch (action) {
      case 'navigate':
        actionBody['navigate'] = {'url': arguments['url']};
      case 'click':
        actionBody['click'] = {
          if (arguments['css'] != null) 'css': arguments['css'],
          if (arguments['role'] != null) 'role': arguments['role'],
          if (arguments['name'] != null) 'name': arguments['name'],
        };
      case 'clickAt':
        actionBody['clickAt'] = {
          'x': arguments['x'],
          'y': arguments['y'],
          if (arguments['button'] != null) 'button': arguments['button'],
          if (arguments['clickCount'] != null)
            'clickCount': arguments['clickCount'],
          if (arguments['modifiers'] is List)
            'modifiers': arguments['modifiers'],
        };
      case 'moveTo':
        actionBody['moveTo'] = {'x': arguments['x'], 'y': arguments['y']};
      case 'drag':
        actionBody['drag'] = {
          'fromX': arguments['fromX'],
          'fromY': arguments['fromY'],
          'toX': arguments['toX'],
          'toY': arguments['toY'],
          if (arguments['button'] != null) 'button': arguments['button'],
          if (arguments['modifiers'] is List)
            'modifiers': arguments['modifiers'],
        };
      case 'type':
        actionBody['type'] = {
          'text': arguments['text'],
          if (arguments['css'] != null) 'css': arguments['css'],
          if (arguments['submit'] == true) 'submit': true,
        };
      case 'setValue':
        // The semantic write (ADR 0064): set an element's value in
        // background — no keyboard focus, no event stream.
        actionBody['setValue'] = {
          'value': arguments['value'],
          if (arguments['css'] != null) 'css': arguments['css'],
          if (arguments['role'] != null) 'role': arguments['role'],
          if (arguments['name'] != null) 'name': arguments['name'],
        };
      case 'elementAction':
        // One advertised element action (AXConfirm, AXShowMenu, …).
        actionBody['elementAction'] = {
          'action': arguments['elementAction'],
          if (arguments['css'] != null) 'css': arguments['css'],
          if (arguments['role'] != null) 'role': arguments['role'],
          if (arguments['name'] != null) 'name': arguments['name'],
        };
      case 'key':
        actionBody['key'] = {
          'key': arguments['key'],
          if (arguments['modifiers'] is List)
            'modifiers': arguments['modifiers'],
        };
      case 'scroll':
        actionBody['scroll'] = {
          if (arguments['direction'] != null)
            'direction': arguments['direction'],
          if (arguments['distance'] != null) 'distance': arguments['distance'],
        };
      case 'evaluate':
        actionBody['evaluate'] = arguments['expression'];
      case 'invoke':
        actionBody['invoke'] = {
          'name': arguments['name'],
          if (arguments['args'] is Map<Object?, Object?>)
            'args': arguments['args'],
        };
      default:
        throw McpToolError('unknown action: $action');
    }
    final automationAction = ActStep.actionFromJson(actionBody);
    // Affinity routing receipt (ADR 0003): computed before attach so
    // the payload can name the reroute honestly.
    final routedBrowser = _willRouteToBrowser(arguments, action)
        ? _configuredBrowser()
        : null;
    final session = await _session(arguments, affinityVerb: action);
    final profileName = arguments['profile'];
    Map<String, Object?> payload;
    if (profileName == null) {
      payload = {
        ...await _performWithLadder(session, automationAction, arguments),
        'action': action,
        if (routedBrowser != null)
          'routedTo': {
            'transport': routedBrowser.transport.name,
            'endpoint': '${routedBrowser.endpoint}',
            'reason':
                '"$action" has no desktop-tier surface; attached the '
                'configured browser tier (override per call with '
                '"transport"/"endpoint")',
          },
        if (action == 'navigate' &&
            session.binding.transport == AutomationTransport.osAccessibility)
          'navigate': {
            'surface': 'systemBrowser',
            'drivable': false,
            'hint':
                'the URL opened in the OS default browser — an untracked '
                'surface. Observe it: automation_list_apps + app:{pid} '
                'anchor. Drive it: attach a browser tier (serve --cdp, '
                'env UNIVERSAL_AUTOMATION_CDP, or --browser-handle) and '
                'navigate routes there automatically.',
          },
      };
    } else {
      final behavioral = session.asBehavioral();
      if (behavioral == null) {
        throw const McpToolError(
          'this transport cannot honor behavior profiles',
        );
      }
      final profile = profileName is String
          ? (profileName == 'humanPrior'
                ? BehaviorProfile.humanPrior(
                    (arguments['seed'] as int?) ??
                        DateTime.now().microsecondsSinceEpoch,
                  )
                : throw const McpToolError(
                    "string profile must be 'humanPrior'; pass a canonical "
                    'profile object for explicit facets',
                  ))
          : BehaviorProfile.fromJson(
              (profileName as Map<Object?, Object?>).map(
                (key, value) => MapEntry('$key', value),
              ),
            );
      final seed = arguments['seed'] as int?;
      final outcome = await behavioral.performWith(
        automationAction,
        profile,
        seed: seed,
      );
      payload = {'ok': true, 'action': action, 'behavior': outcome.toJson()};
    }
    if (arguments['returnState'] == true) {
      // The act loop's closing read: post-action state through the
      // default view, in the same tool result.
      final observation = Observation.of(
        await session.driver.snapshot(),
        const SemanticView(maxNodes: 200),
      );
      payload = {...payload, 'state': observation.render()};
    }
    return payload;
  }

  /// The ADR 0064 actuation ladder: semantic verbs act below the focus
  /// layer and dispatch directly; a global-event verb refused by the
  /// focus contract escalates ONLY when the caller explicitly asked
  /// (`foreground: true`) — activate the anchor, retry once, and record
  /// `focusContract: "activated"` so the cost stays visible. Default is
  /// refuse.
  Future<Map<String, Object?>> _performWithLadder(
    ResolvedSession session,
    AutomationAction automationAction,
    Map<String, Object?> arguments,
  ) async {
    try {
      await session.driver.perform(automationAction);
      return {'ok': true};
    } on ForegroundRequiredException catch (error) {
      if (arguments['foreground'] != true) rethrow;
      final driver = session.driver;
      if (driver is! OsActivator) rethrow;
      await (driver as OsActivator).activate(error.targetPid);
      await driver.perform(automationAction);
      return {'ok': true, 'focusContract': 'activated'};
    }
  }

  /// The anchor discovery record (ADR 0064): every running,
  /// anchorable application — the `app` argument of every OS-tier tool
  /// consumes one of these rows.
  Future<Map<String, Object?>> _listApps(Map<String, Object?> arguments) async {
    final session = await _session({
      ...arguments,
      'transport': 'osAccessibility',
    });
    final driver = session.driver;
    if (driver is! OsAppCatalog) {
      throw const McpToolError(
        'automation_list_apps needs an OS app catalog (macOS AX today); '
        'other OS transports do not expose an application record yet',
      );
    }
    final apps = await (driver as OsAppCatalog).runningApps();
    return {
      'apps': [
        for (final app in apps)
          {
            'pid': app.pid,
            'name': app.name,
            if (app.bundleId != null) 'bundleId': app.bundleId,
            'active': app.active,
            'hidden': app.hidden,
          },
      ],
    };
  }

  /// Asks the operating system for a consent grant the OS tier needs.
  ///
  /// A missing grant is otherwise a dead end: the tier refuses and the
  /// agent can only tell the user to open System Settings. This is the
  /// explicit ask — the OS shows its own prompt, and the result says
  /// whether the grant is now held.
  Future<Map<String, Object?>> _requestConsent(
    Map<String, Object?> arguments,
  ) async {
    final kind = arguments['kind'];
    if (kind != 'accessibility' && kind != 'screenRecording') {
      throw const McpToolError(
        'automation_request_consent needs kind '
        '"accessibility" or "screenRecording"',
      );
    }
    final session = await _session({
      ...arguments,
      'transport': 'osAccessibility',
    });
    final driver = session.driver;
    if (driver is! OsConsentRequester) {
      throw const McpToolError(
        'automation_request_consent needs the OS tier (transport '
        '"osAccessibility"); other tiers hold no OS consent',
      );
    }
    final requester = driver as OsConsentRequester;
    final granted = switch (kind) {
      'accessibility' => requester.requestAccessibilityConsent(),
      _ => requester.requestScreenCaptureConsent(),
    };
    return {
      'kind': kind,
      'granted': granted,
      if (!granted)
        'remedy':
            'the grant was not given; enable it in System Settings -> '
            'Privacy & Security',
    };
  }

  Future<Map<String, Object?>> _verify(Map<String, Object?> arguments) async {
    final rawChecks = arguments['checks'];
    if (rawChecks is! List<Object?> || rawChecks.isEmpty) {
      throw const McpToolError('automation_verify needs a checks list');
    }
    final checks = [for (final raw in rawChecks) VerifyCheck.fromJson(raw)];
    final session = await _session(arguments);
    final snapshot = await session.driver.snapshot();
    final failures = [
      for (final check in checks)
        if (check.evaluate(snapshot, url: session.url) case final reason?)
          reason,
    ];
    return {
      'ok': failures.isEmpty,
      if (failures.isNotEmpty) 'failures': failures,
      'checks': checks.length,
    };
  }

  Future<Map<String, Object?>> _screenshot(
    Map<String, Object?> arguments,
  ) async {
    final session = await _session(arguments);
    final driver = session.driver;
    final maxPx = arguments['maxPx'] is int ? arguments['maxPx']! as int : 0;
    final imageBlocks = <Map<String, Object?>>[];

    if (arguments['listWindows'] == true) {
      if (driver is! OsWindowCapture) {
        throw const McpToolError(
          'listWindows needs the OS tier (transport "osAccessibility")',
        );
      }
      final pid = arguments['pid'] is int ? arguments['pid']! as int : 0;
      final windows = await (driver as OsWindowCapture).windows(pid: pid);
      return {
        'windows': [
          for (final window in windows)
            {
              'windowId': window.windowId,
              'pid': window.pid,
              'name': window.name,
              if (window.bounds != null)
                'bounds': {
                  'left': window.bounds!.left,
                  'top': window.bounds!.top,
                  'width': window.bounds!.width,
                  'height': window.bounds!.height,
                },
            },
        ],
      };
    }

    final path = arguments['path'];
    Uint8List bytes;
    if (arguments['windowId'] != null) {
      if (arguments['windowId'] is! int) {
        throw const McpToolError('windowId must be an integer');
      }
      if (driver is! OsWindowCapture) {
        throw const McpToolError(
          'windowId needs the OS tier (transport "osAccessibility")',
        );
      }
      if (path is! String || path.isEmpty) {
        throw const McpToolError('automation_screenshot needs a path');
      }
      bytes = await (driver as OsWindowCapture).windowScreenshot(
        arguments['windowId']! as int,
        maxPx: maxPx,
      );
    } else {
      if (path is! String || path.isEmpty) {
        throw const McpToolError('automation_screenshot needs a path');
      }
      // The options are the agent's explicit request: a tier that cannot
      // honor one refuses (and names the route out) rather than quietly
      // returning a cheaper frame.
      final request = CaptureRequest.fromArguments(arguments);
      try {
        bytes = await request.capture(driver);
      } on DriverUnsupportedException catch (error) {
        throw McpToolError(
          'automation_screenshot: ${error.message}',
          details: error.details,
        );
      } on SpecViolationException catch (error) {
        throw McpToolError(
          'automation_screenshot: ${error.violations.join("; ")}',
        );
      }
    }

    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    // Opt-in image block (ADR 0052: images are enrichment, not the
    // primary channel) — agents that render them read it from content,
    // everyone else ignores it.
    if (arguments['image'] == true) {
      imageBlocks.add({
        'type': 'image',
        'mimeType': 'image/png',
        'data': base64Encode(bytes),
      });
    }
    return {
      'ok': true,
      'path': file.path,
      'bytes': bytes.length,
      if (imageBlocks.isNotEmpty) '_imageContent': imageBlocks.single,
    };
  }

  Future<Map<String, Object?>> _validatePlan(
    Map<String, Object?> arguments,
  ) async {
    final path = _planPath(arguments);
    try {
      final plan = await AutomationPlan.load(path);
      return {
        'ok': true,
        'plan': path,
        'scenarios': plan.scenarios.keys.toList(),
      };
    } on SpecViolationException catch (error) {
      return {'ok': false, 'plan': path, 'violations': error.violations};
    }
  }

  Future<Map<String, Object?>> _runPlan(Map<String, Object?> arguments) async {
    final path = _planPath(arguments);
    final plan = await AutomationPlan.load(path);
    final overrides = (arguments['set'] as Map<Object?, Object?>? ?? const {})
        .map((key, value) => MapEntry('$key', '$value'));
    final report = await PlanRunner().run(
      plan,
      scenarioName: arguments['scenario'] as String?,
      sessionOverrides: overrides,
      outDir: arguments['out'] as String?,
    );
    return report.toJson();
  }

  String _planPath(Map<String, Object?> arguments) {
    final path = arguments['plan'];
    if (path is! String || path.isEmpty) {
      throw const McpToolError('a plan file path is required');
    }
    return path;
  }

  /// Submit-and-detach plan execution (ADR 0064's resident job plane):
  /// the call returns a jobId immediately; the serve process runs the
  /// job FIFO and persists every transition under the jobs directory.
  Future<Map<String, Object?>> _runBackground(
    Map<String, Object?> arguments,
  ) async {
    final path = _planPath(arguments);
    final overrides = (arguments['set'] as Map<Object?, Object?>? ?? const {})
        .map((key, value) => MapEntry('$key', '$value'));
    final job = _jobs.submit(
      planPath: path,
      scenario: arguments['scenario'] is String
          ? arguments['scenario'] as String
          : null,
      overrides: overrides,
      outDir: arguments['out'] is String ? arguments['out'] as String : null,
    );
    return {
      'jobId': job.id,
      'status': job.status,
      'jobsDirectory': _jobsDirectory,
    };
  }

  /// One job's record: status while in flight, the full run report when
  /// done. Reads persisted receipts too, so results survive a serve
  /// restart.
  Future<Map<String, Object?>> _jobStatus(
    Map<String, Object?> arguments,
  ) async {
    final id = arguments['jobId'];
    if (id is! String || id.isEmpty) {
      throw const McpToolError('automation_job needs a jobId');
    }
    final job = _jobs.status(id);
    if (job == null) {
      throw McpToolError('unknown job: $id');
    }
    return job.toJson();
  }

  /// The self-description surface (ADR 0003): what tiers this server
  /// sees, which verbs work where, how the browser tier is configured.
  /// Read-only, attaches nothing, prompts no TCC consent. The one call
  /// that replaces capability discovery by trial-and-error.
  Future<Map<String, Object?>> _capabilities() async {
    final browser = _configuredBrowser();
    final cdp = _endpoints[AutomationTransport.cdp];
    String? handleEndpoint;
    if (cdp == null && browserHandle != null && handlesDirectory != null) {
      handleEndpoint = browser?.endpoint.toString();
    }
    return {
      'serve': {
        'defaultTransport': _defaultTransport.name,
        'platform': Platform.operatingSystem,
        'affinity':
            'instrumented-only verbs (${instrumentedAffinityVerbs.join(", ")}) '
            'attach to the configured browser tier when the default is '
            'the desktop tier; override per call with transport/endpoint',
      },
      'tiers': {
        'cdp': await _tierRecord(
          AutomationTransport.cdp,
          probePath: '/json/version',
          browserField: 'Browser',
        ),
        'webdriver': await _tierRecord(
          AutomationTransport.webdriver,
          probePath: '/status',
        ),
        'osAccessibility': {
          'endpointFree': true,
          'verbs': [
            'observe',
            'click',
            'setValue',
            'elementAction',
            'clickAt',
            'moveTo',
            'drag',
            'type',
            'key',
            'scroll',
            'navigate (opens the system browser — untracked)',
            'screenshot',
            'listApps',
            'listWindows',
          ],
          'refuses': ['evaluate', 'invoke'],
        },
      },
      'routing': {
        'instrumentedAffinityVerbs': instrumentedAffinityVerbs.toList(),
        'browserTierConfigured': browser != null,
        if (browser != null)
          'browserTier': {
            'transport': browser.transport.name,
            'endpoint': '${browser.endpoint}',
          },
      },
      'openUrl': {
        'supported': Platform.isMacOS || Platform.isLinux || Platform.isWindows,
        'schemes': systemOpenUrlSchemes.toList(),
      },
      if (browserHandle != null || handlesDirectory != null)
        'handles': {
          if (handlesDirectory != null) 'dir': handlesDirectory,
          if (browserHandle != null) 'browserHandle': browserHandle,
          if (handleEndpoint != null) 'resolvedEndpoint': handleEndpoint,
        },
      'coldStart':
          'Desktop tier works immediately (macOS AX needs the '
          'Accessibility TCC grant for the host process). For a drivable '
          'browser: start one with a debug port (e.g. chromium '
          '--remote-debugging-port=9222, or moli serve) and configure '
          'it via --cdp, env UNIVERSAL_AUTOMATION_CDP, or '
          '--handles-dir + --browser-handle.',
    };
  }

  /// One tier's configuration + liveness record. The probe is a single
  /// short GET (2 s); an unreachable endpoint is an honest fact, not an
  /// error — the tier simply cannot be attached until it answers.
  Future<Map<String, Object?>> _tierRecord(
    AutomationTransport transport, {
    required String probePath,
    String? browserField,
  }) async {
    final endpoint = _endpoints[transport];
    if (endpoint == null) return {'configured': false};
    Map<String, Object?> probe;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      try {
        final request = await client
            .getUrl(endpoint.replace(path: probePath))
            .timeout(const Duration(seconds: 2));
        final response = await request.close().timeout(
          const Duration(seconds: 2),
        );
        final body = await utf8.decoder.bind(response).join();
        probe = {
          'reachable': response.statusCode == 200,
          'status': response.statusCode,
          if (response.statusCode == 200 && browserField != null)
            ...() {
              try {
                final decoded = jsonDecode(body);
                final browserName = decoded is Map<Object?, Object?>
                    ? decoded[browserField]
                    : null;
                return {if (browserName != null) 'browser': '$browserName'};
              } on FormatException {
                return const <String, Object?>{};
              }
            }(),
        };
      } finally {
        client.close(force: true);
      }
    } on Object catch (error) {
      probe = {'reachable': false, 'error': '$error'};
    }
    return {'configured': true, 'endpoint': '$endpoint', 'probe': probe};
  }

  /// The tool descriptors (name, description, JSON Schema input).
  static List<Map<String, Object?>> toolDescriptors() {
    final transportOverride = {
      'transport': {
        'type': 'string',
        'enum': ['cdp', 'webdriver', 'osAccessibility'],
        'description':
            'Overrides the serve transport for this call. '
            'osAccessibility is the desktop tier (macOS AX): semantic '
            'verbs (click/setValue/elementAction) act below the focus '
            'layer on background apps; global-event verbs (type/key/'
            'scroll/clickAt/moveTo/drag) need the target frontmost or an '
            'explicit foreground opt-in (ADR 0064).',
      },
      'app': {
        'type': 'object',
        'description':
            'OS tier: anchor to one running application instead of the '
            'focused one — {pid} | {bundleId} | {name}. Discover rows '
            'via automation_list_apps. Anchored sessions read and act on '
            'the app in background.',
        'properties': {
          'pid': {'type': 'integer'},
          'bundleId': {'type': 'string'},
          'name': {'type': 'string'},
        },
      },
      'endpoint': {
        'type': 'string',
        'description':
            'CDP/WebDriver HTTP base (e.g. http://127.0.0.1:9222); '
            'defaults to the serve --cdp endpoint',
      },
      // The browser-tab selector: which page target the CDP tier attaches
      // to. A browser with several tabs open lists them all, so "the
      // first one" is a guess — the selector makes the choice explicit
      // and refuses when it cannot be resolved.
      'targetId': {
        'type': 'string',
        'description':
            'CDP tier: attach to this page target id (a browser tab).',
      },
      'targetUrl': {
        'type': 'string',
        'description':
            'CDP tier: attach to the page target whose URL contains this.',
      },
      'targetTitle': {
        'type': 'string',
        'description':
            'CDP tier: attach to the page target whose title contains this.',
      },
    };
    Map<String, Object?> tool(
      String name,
      String description,
      Map<String, Object?> inputSchema,
    ) => {'name': name, 'description': description, 'inputSchema': inputSchema};
    return [
      tool(
        'automation_observe',
        'Capture a semantic (accessibility) snapshot of an automated '
            'surface. Read-only; the observe half of observe/act/verify. '
            'Over the desktop tier this is the focused application\'s tree. '
            'Pass `view` (identifierPrefix/subtreeOf/fields/maxNodes/panes) '
            'to get a rendered, ref-stable observation instead of the raw '
            'tree; pass `diff: true` to also get +/-/~ rows against the '
            'session\'s previous viewed observation.',
        {
          'type': 'object',
          'properties': {
            ...transportOverride,
            'at': {
              'type': 'object',
              'properties': {
                'x': {'type': 'number'},
                'y': {'type': 'number'},
              },
              'required': ['x', 'y'],
              'description':
                  'Ground this surface point to the innermost node '
                  'covering it (ADR 0053)',
            },
            'view': {
              'type': 'object',
              'description':
                  'SemanticView wire form: fields (role/name/value/'
                  'bounds), subtreeOf (a ref like s_3 or an identifier), '
                  'identifierPrefix, maxNodes, panes {name: view}.',
            },
            'diff': {
              'type': 'boolean',
              'description':
                  'With view: also return the delta against this '
                  "session's previous viewed observation.",
            },
          },
        },
      ),
      tool(
        'automation_act',
        'Perform one intent-level action: navigate | click | type | '
            'setValue | elementAction | key | scroll | evaluate | invoke. '
            'setValue/elementAction are the semantic write path (ADR 0064): '
            'they act on the element below the focus layer, valid on '
            'background applications — prefer them over type/key for text '
            'and confirmations. Global-event verbs on a background target '
            'refuse with foregroundRequired unless foreground: true (then '
            'the anchor is activated and the retry recorded). Tier notes: '
            'navigate/evaluate/invoke have no desktop-tier surface — on an '
            'osAccessibility server they affinity-route to a configured '
            'browser tier (routedTo says so); with none configured navigate '
            'opens the OS default browser (untracked surface) and '
            'evaluate/invoke refuse. Optional behavior profile dispatches '
            'with ADR 0044 dynamics (event-stream verbs only). returnState '
            'attaches the post-action state render — the act loop\'s '
            'closing read in one call.',
        {
          'type': 'object',
          'required': ['action'],
          'properties': {
            'action': {
              'type': 'string',
              'enum': [
                'navigate',
                'click',
                'clickAt',
                'moveTo',
                'drag',
                'type',
                'setValue',
                'elementAction',
                'key',
                'scroll',
                'evaluate',
                'invoke',
              ],
            },
            'url': {
              'type': 'string',
              'description':
                  'navigate: absolute URL (desktop tier opens it in the '
                  'system browser; schemes http/https/file/mailto only)',
            },
            'css': {'type': 'string'},
            'role': {'type': 'string'},
            'text': {'type': 'string'},
            'value': {
              'type': 'string',
              'description':
                  'setValue: the full replacement value for the element',
            },
            'elementAction': {
              'type': 'string',
              'description':
                  'elementAction: the advertised action name (AXConfirm, '
                  'AXShowMenu, …) — read axActions from the snapshot',
            },
            'foreground': {
              'type': 'boolean',
              'description':
                  'Explicit opt-in to steal focus: activate the anchored '
                  'app and retry a focus-refused global verb once '
                  '(ADR 0064 ladder; default false = refuse)',
            },
            'submit': {'type': 'boolean'},
            'key': {'type': 'string'},
            'direction': {
              'type': 'string',
              'enum': ['up', 'down', 'left', 'right'],
            },
            'distance': {'type': 'number'},
            'expression': {'type': 'string'},
            'x': {
              'type': 'number',
              'description': 'clickAt/moveTo: viewport X coordinate',
            },
            'y': {
              'type': 'number',
              'description': 'clickAt/moveTo: viewport Y coordinate',
            },
            'fromX': {'type': 'number', 'description': 'drag: press X'},
            'fromY': {'type': 'number', 'description': 'drag: press Y'},
            'toX': {'type': 'number', 'description': 'drag: release X'},
            'toY': {'type': 'number', 'description': 'drag: release Y'},
            'button': {
              'type': 'string',
              'enum': ['left', 'right', 'middle'],
              'description': 'pointer button for coordinate verbs',
            },
            'clickCount': {
              'type': 'integer',
              'description': 'clickAt: 2 = double-click, 3 = triple',
            },
            'modifiers': {
              'type': 'array',
              'items': {
                'type': 'string',
                'enum': ['shift', 'control', 'alt', 'meta'],
              },
              'description': 'Keyboard chord for clickAt/drag/key (ADR 0053)',
            },
            'name': {
              'type': 'string',
              'description':
                  'click accessible name, or catalog action name for invoke',
            },
            'args': {'type': 'object'},
            'returnState': {
              'type': 'boolean',
              'description':
                  'Return the post-action semantic state render with the '
                  'result.',
            },
            ...transportOverride,
            'profile': {
              'description':
                  "'humanPrior' or a canonical BehaviorProfile object",
            },
            'seed': {'type': 'integer'},
          },
        },
      ),
      tool(
        'automation_verify',
        'Assert post-conditions against one fresh snapshot: checks are '
            '{exists: {role?, name?, nameContains?}} | {absent: {...}} | '
            '{value: {locator: {...}, equals?|contains?}} | {urlContains: s}.',
        {
          'type': 'object',
          'required': ['checks'],
          'properties': {
            'checks': {
              'type': 'array',
              'items': {'type': 'object'},
            },
            ...transportOverride,
          },
        },
      ),
      tool(
        'automation_screenshot',
        'Capture one PNG frame to a local file path. `windowId` scopes '
            'the capture to one window (OS tier); `image` attaches the PNG '
            'as an opt-in image content block; `maxPx` caps the long side '
            'in pixels. `fullPage` captures beyond the viewport (a '
            'scrolling tier only); `format`/`quality` choose the encoding '
            '(png is lossless, jpeg is smaller). A tier that cannot honor '
            'an option refuses and names the route out.',
        {
          'type': 'object',
          'required': ['path'],
          'properties': {
            'path': {'type': 'string'},
            'windowId': {
              'type': 'integer',
              'description':
                  'Capture this window instead of the display '
                  '(OS tier; discover ids via listWindows)',
            },
            'listWindows': {
              'type': 'boolean',
              'description':
                  'List capturable windows (OS tier) instead '
                  'of capturing',
            },
            'image': {
              'type': 'boolean',
              'description':
                  'Attach the PNG as an image content block '
                  '(opt-in; many agents prefer the semantic channel)',
            },
            'maxPx': {
              'type': 'integer',
              'description':
                  'Cap the long side in pixels (e.g. 1024). The image is '
                  'scaled at capture time, so this is quality-preserving: '
                  'a vision model resizes large images down anyway.',
            },
            'fullPage': {
              'type': 'boolean',
              'description':
                  'Capture the whole scrollable surface, not just the '
                  'visible viewport (a scrolling tier only).',
            },
            'format': {
              'type': 'string',
              'enum': ['png', 'jpeg'],
              'description':
                  'Encoding of the capture. png is lossless (default); '
                  'jpeg is much smaller for UI content.',
            },
            'quality': {
              'type': 'integer',
              'description':
                  'JPEG quality 1..100 (jpeg only). Higher keeps more '
                  'detail at the cost of size.',
            },
            ...transportOverride,
          },
        },
      ),
      tool(
        'automation_list_apps',
        'List running, anchorable applications (macOS tier): pid, name, '
            'bundleId, active, hidden. Feed a row into any OS-tier call\'s '
            '`app` argument to anchor that application — observation and '
            'semantic actions then work in background without stealing '
            'focus (ADR 0064).',
        {
          'type': 'object',
          'properties': {...transportOverride},
        },
      ),
      tool(
        'automation_request_consent',
        'Ask the operating system for a consent grant the OS tier needs '
            '(macOS: "accessibility" for reading and driving the app tree, '
            '"screenRecording" for capturing pixels). The OS shows its own '
            'prompt; the result reports whether the grant is now held. '
            'Explicit by design — a capture never triggers the prompt '
            'itself.',
        {
          'type': 'object',
          'required': ['kind'],
          'properties': {
            'kind': {
              'type': 'string',
              'enum': ['accessibility', 'screenRecording'],
              'description': 'Which OS grant to ask for.',
            },
            ...transportOverride,
          },
        },
      ),
      tool(
        'automation_validate_plan',
        'Validate a declarative plan document (.yaml/.yml/.json) '
            'fail-closed: every violation is reported, nothing attaches.',
        {
          'type': 'object',
          'required': ['plan'],
          'properties': {
            'plan': {'type': 'string'},
          },
        },
      ),
      tool(
        'automation_run_plan',
        'Run a scenario of a declarative plan: sessions attach lazily, '
            'steps run in order, the report is structured JSON with per-step '
            'status and behavior receipts.',
        {
          'type': 'object',
          'required': ['plan'],
          'properties': {
            'plan': {'type': 'string'},
            'scenario': {'type': 'string'},
            'out': {
              'type': 'string',
              'description': 'output directory for screenshots and receipts',
            },
            'set': {
              'type': 'object',
              'description':
                  'session handle overrides: {handleName: endpointUri}',
            },
          },
        },
      ),
      tool(
        'automation_run_background',
        'Submit a plan run to the resident job plane and detach '
            '(ADR 0064): returns a jobId immediately; the serve process '
            'executes jobs FIFO and persists receipts. Poll with '
            'automation_job. This is the background-connection shape: the '
            'client is a control plane, the serve process owns execution.',
        {
          'type': 'object',
          'required': ['plan'],
          'properties': {
            'plan': {'type': 'string'},
            'scenario': {'type': 'string'},
            'out': {
              'type': 'string',
              'description': 'output directory for screenshots and receipts',
            },
            'set': {
              'type': 'object',
              'description':
                  'session handle overrides: {handleName: endpointUri}',
            },
          },
        },
      ),
      tool(
        'automation_capabilities',
        'Report what this server can reach before any attach: the default '
            'transport, per-tier endpoints with a short reachability probe '
            '(cdp /json/version, webdriver /status), the desktop tier\'s '
            'verb set (navigate opens the system browser there), the '
            'instrumented-affinity routing set (navigate/evaluate/invoke '
            'follow a configured browser tier), open-url scheme allowlist, '
            'and handle configuration. Read-only; call this first when '
            'unsure which tier a verb will take.',
        {'type': 'object', 'properties': <String, Object?>{}},
      ),
      tool(
        'automation_job',
        'One background job\'s record: status (queued|running|succeeded|'
            'failed) while in flight, the full run report when done. Reads '
            'persisted receipts, so results survive a serve restart.',
        {
          'type': 'object',
          'required': ['jobId'],
          'properties': {
            'jobId': {'type': 'string'},
          },
        },
      ),
    ];
  }

  static Map<String, Object?> _result(Object? id, Object? result) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  };

  static Map<String, Object?> _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };
}

/// A tool-level failure surfaced as an MCP result with `isError: true`.
class McpToolError implements Exception {
  /// Creates the error. [details] rides as a second JSON content block
  /// (ADR 0003) so agents get machine-readable remedies, not just prose.
  const McpToolError(this.message, {this.details});

  /// Human-readable message.
  final String message;

  /// Structured details (kind, remedy, locator, …); may be empty.
  final Map<String, Object?>? details;

  @override
  String toString() => message;
}

/// Runs the stdio loop: reads newline-delimited JSON-RPC from [stdin],
/// writes responses to [stdout]. Returns when stdin closes.
Future<void> serveMcpStdio({
  Uri? defaultEndpoint,
  Map<AutomationTransport, Uri> endpoints = const {},
  AutomationTransport defaultTransport = AutomationTransport.cdp,
  Map<String, String> overrides = const {},
  Map<AutomationTransport, DriverFactory>? factories,
  String? jobsDirectory,
  String? handlesDirectory,
  String? browserHandle,
}) async {
  final server = ToolkitMcpServer(
    defaultEndpoint: defaultEndpoint,
    endpoints: endpoints,
    defaultTransport: defaultTransport,
    overrides: overrides,
    factories: factories,
    jobsDirectory: jobsDirectory,
    handlesDirectory: handlesDirectory,
    browserHandle: browserHandle,
  );
  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
  await for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    Map<String, Object?> message;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, Object?>) {
        stdout.writeln(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': null,
            'error': {'code': -32600, 'message': 'not a request object'},
          }),
        );
        continue;
      }
      message = decoded;
    } on FormatException catch (error) {
      stdout.writeln(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': null,
          'error': {'code': -32700, 'message': 'parse error: ${error.message}'},
        }),
      );
      continue;
    }
    final response = await server.handle(message);
    for (final notice in server.takeOutbound()) {
      stdout.writeln(jsonEncode(notice));
    }
    if (response != null) {
      stdout.writeln(jsonEncode(response));
    }
    await stdout.flush();
  }
}

/// Binds a loopback HTTP server exposing the same toolkit as MCP over
/// HTTP: `POST /mcp` with one JSON-RPC message per request, one JSON
/// response per reply (the stateless shape of the MCP streamable-HTTP
/// transport). Stdio writes list-changed notices; HTTP accepts
/// `notifications/initialized` with 202 and does not push them.
///
/// Loopback only. For remote clients (e.g. the ChatGPT connector, which
/// requires a public HTTPS origin) front it with a tunnel deliberately —
/// the surface can drive real UIs.
Future<HttpServer> startMcpHttp({
  required int port,
  Uri? defaultEndpoint,
  Map<AutomationTransport, Uri> endpoints = const {},
  AutomationTransport defaultTransport = AutomationTransport.cdp,
  Map<String, String> overrides = const {},
  Map<AutomationTransport, DriverFactory>? factories,
  String? jobsDirectory,
  String? handlesDirectory,
  String? browserHandle,
}) async {
  final server = ToolkitMcpServer(
    defaultEndpoint: defaultEndpoint,
    endpoints: endpoints,
    defaultTransport: defaultTransport,
    overrides: overrides,
    factories: factories,
    jobsDirectory: jobsDirectory,
    handlesDirectory: handlesDirectory,
    browserHandle: browserHandle,
  );
  final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  httpServer.listen((request) => _handleHttpMessage(server, request));
  return httpServer;
}

Future<void> _handleHttpMessage(
  ToolkitMcpServer server,
  HttpRequest request,
) async {
  final respond = (int status, Object? body) async {
    request.response.statusCode = status;
    if (body != null) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
    }
    await request.response.close();
  };
  if (request.uri.path != '/mcp') {
    await respond(404, {
      'jsonrpc': '2.0',
      'id': null,
      'error': {'code': -32601, 'message': 'post to /mcp'},
    });
    return;
  }
  if (request.method != 'POST') {
    await respond(405, null);
    return;
  }
  final body = await utf8.decoder.bind(request).join();
  Map<String, Object?> message;
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>)
      throw const FormatException('not a request object');
    message = decoded;
  } on FormatException catch (error) {
    await respond(400, {
      'jsonrpc': '2.0',
      'id': null,
      'error': {'code': -32700, 'message': 'parse error: ${error.message}'},
    });
    return;
  }
  final response = await server.handle(message);
  server.takeOutbound();
  if (response == null) {
    // A notification (or malformed notification): accepted, no body.
    await respond(202, null);
    return;
  }
  await respond(200, response);
}

/// A resolved session whose driver face is the consent-gated decorator;
/// everything else (binding, detach, the behavioral face) delegates.
///
/// Non-claim: the behavioral face is NOT gated in v1 — ADR 0044
/// profiles ride the inner driver directly, so composing a gate and a
/// behavior profile on one session leaves the profile path ungated.
final class _ConsentSession implements ResolvedSession {
  _ConsentSession(this._inner, this._gated);

  final ResolvedSession _inner;
  final ConsentGatedDriver _gated;

  @override
  SessionBinding get binding => _inner.binding;

  @override
  AutomationDriver get driver => _gated;

  @override
  Uri? get url => _inner.url;

  @override
  BehavioralDriver? asBehavioral() => _inner.asBehavioral();

  @override
  Future<void> detach() => _inner.detach();
}
