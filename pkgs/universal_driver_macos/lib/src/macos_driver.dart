import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'driver_bridge.dart';
import 'macos_app.dart';

/// The host refuses to answer AX queries until the user grants
/// Accessibility (System Settings → Privacy & Security). Fixable
/// environment state; retry after [MacosDriver.requestTrust] succeeds.
final class AccessibilityPermissionRequiredException
    extends AutomationException {
  /// Creates the exception.
  const AccessibilityPermissionRequiredException()
    : super(
        'Accessibility permission required for universal_driver_macos; '
        'grant it in System Settings (or call requestTrust once)',
      );

  @override
  String get kind => 'permissionRequired';
}

/// [Screen Recording] consent is a separate TCC grant from
/// Accessibility: tree reads and input injection need the latter, any
/// pixel capture needs the former. The typed exceptions keep the two
/// fixable states apart.
final class ScreenRecordingPermissionRequiredException
    extends AutomationException {
  /// Creates the exception.
  const ScreenRecordingPermissionRequiredException()
    : super(
        'Screen Recording permission required for capture; request it '
        'in process (call requestScreenCaptureConsent once) or grant it in '
        'System Settings → Privacy & Security → Screen & System Audio',
      );

  @override
  String get kind => 'permissionRequired';
}

/// [AutomationDriver] over the macOS accessibility tree (AXUIElement) and
/// CGEvent input synthesis.
///
/// Observe: the focused application's tree (or, when [targetPid] is
/// anchored, that application's tree — the background read), depth-
/// bounded, mapped onto the family's [Snapshot]; plus
/// [elementAtPosition] hit-testing for hover affordances (the Vosges
/// use case). Act: AXPress for semantic clicks, `setValue` /
/// advertised element actions as the semantic write path (ADR 0064 —
/// valid on background targets), CGEvent for typing, keys, and
/// scrolling. Verify: snapshot deltas.
///
/// The ADR 0064 focus contract is structural: semantic verbs act below
/// the focus layer on the anchored target; global-event verbs (type,
/// key, scroll, the coordinate verbs) route through the OS event stream
/// and are refused with `ForegroundRequiredException` unless the
/// frontmost application is the one this session observed — without the
/// check, a mid-session focus switch would silently drive the wrong app.
///
/// One rung pierces that contract honestly (ADR 0064): in an anchored
/// session (`targetPid` set), `TypeAction` and `KeyPressAction` post
/// their keyboard events straight to the target's event queue
/// (`CGEventPostToPid`) — the user's focus never moves. Delivery is
/// fire-and-forget; apps that drop events while inactive fall back to
/// the explicit `foreground: true` ladder. Pointer and scroll verbs
/// stay focus-bound — they carry global screen coordinates, so posting
/// them to a pid would act on whatever sits under the cursor.
///
/// Element handles cached by the native bridge are invalidated by every
/// new observation; a click on a stale handle transparently re-observes
/// once before giving up.
class MacosDriver
    implements
        AutomationDriver,
        OsAppCatalog,
        OsActivator,
        OsWindowCapture,
        OsDisplayCapture,
        ConfigurableCapture,
        OsConsentRequester {
  /// Creates a driver. [snapshotDepth] and [snapshotMaxNodes] bound the
  /// tree walk (AX trees of real apps can be enormous; hover needs only
  /// the visible surface). [targetPid] anchors every observation to that
  /// application instead of the focused one (`ax://pid/<pid>` sessions,
  /// ADR 0064); `null` keeps the focused-app binding.
  MacosDriver({
    AxDriverBridge? bridge,
    this.targetPid,
    this.snapshotDepth = 12,
    this.snapshotMaxNodes = 600,
    this.preferWebContent = true,
    Future<void> Function(Uri url)? openUrl,
  }) : bridge = bridge ?? NativeAxDriverBridge(),
       // An anchored session observes its target by construction — the
       // focus contract has a reference point before the first walk.
       _observedPid = targetPid,
       _openUrl = openUrl ?? openUrlViaSystem;

  /// The native bridge seam.
  final AxDriverBridge bridge;

  /// The application every observation binds (`null` = focused app).
  final int? targetPid;

  /// The system-browser navigation seam (ADR 0003): `NavigateAction`
  /// hands the URL to the OS handler — an untracked surface. Tests
  /// inject a recording no-op; production uses [openUrlViaSystem].
  final Future<void> Function(Uri url) _openUrl;

  /// Maximum tree depth per snapshot.
  final int snapshotDepth;

  /// Maximum node count per snapshot.
  final int snapshotMaxNodes;

  /// Web-first AX walk for browser hosts (ADR 0065).
  bool preferWebContent;

  /// Walk metadata from the latest snapshot root (ADR 0065).
  Map<String, Object?>? get lastWalkMeta {
    final roots = _lastSnapshot?.roots;
    if (roots == null || roots.isEmpty) return null;
    final attrs = roots.first.attributes;
    if (attrs == null || attrs['uaWebRootFound'] == null) return null;
    return {
      'preferWebContent': attrs['uaPreferWebContent'] == 'true',
      'webRootFound': attrs['uaWebRootFound'] == 'true',
      'webTrimmed': attrs['uaWebTrimmed'] == 'true',
      if (attrs['uaWebRootRole'] != null) 'webRootRole': attrs['uaWebRootRole'],
      if (attrs['uaWebRootName'] != null) 'webRootName': attrs['uaWebRootName'],
    };
  }

  bool _closed = false;
  int _revision = 0;
  Snapshot? _lastSnapshot;
  DateTime? _lastObservationAt;

  /// The ADR 0064 focus contract reference point, maintained by
  /// [snapshot] / [snapshotOfApp] / [ensureForeground].
  int? _observedPid;

  /// Whether [action] routes through the global OS event stream and is
  /// therefore bound by the focus contract (ADR 0064).
  static bool requiresForeground(AutomationAction action) => switch (action) {
    ClickAtAction(:final windowId) when windowId != null => false,
    TypeAction() ||
    KeyPressAction() ||
    ScrollAction() ||
    ClickAtAction() ||
    MoveAction() ||
    DragAction() => true,
    NavigateAction() ||
    ClickAction() ||
    SetValueAction() ||
    ElementAction() ||
    EvaluateAction() ||
    InvokeAction() => false,
  };

  /// The focus contract gate (ADR 0064): refuse [action] unless the
  /// frontmost application is the one this session last observed —
  /// global-event verbs reach whatever owns the event stream, and
  /// without this check a mid-session focus switch would silently drive
  /// the wrong app. With no observation yet, the frontmost app at
  /// dispatch IS the target and is recorded as such. Semantic verbs
  /// (locator press/setValue/element actions) never reach this gate.
  Future<void> ensureForeground(AutomationAction action) async {
    final app = await frontmost();
    final observed = _observedPid;
    if (observed == null) {
      _observedPid = app.pid;
      return;
    }
    if (app.pid != observed) {
      throw ForegroundRequiredException(
        verb: action.runtimeType.toString(),
        targetPid: observed,
        frontmostPid: app.pid,
      );
    }
  }

  @override
  DriverCapabilities get capabilities => const DriverCapabilities(
    screenshot: true,
    a11yTree: true,
    inputSynthesis: true,
    pointerCoordinates: true,
    semanticWrite: true,
    pidScopedEvents: true,
    navigate: true,
  );

  /// When the last snapshot was taken — the reference point for the
  /// behavior layer's reaction floor.
  DateTime? get lastObservationAt => _lastObservationAt;

  /// Whether the process may query the accessibility tree right now.
  bool get axTrusted {
    _ensureOpen();
    return bridge.axTrusted();
  }

  /// Whether the Accessibility grant is held right now (never prompts) —
  /// the [OsConsentRequester] spelling of [axTrusted].
  @override
  bool get accessibilityTrusted => axTrusted;

  /// Whether the Screen Recording grant is held right now (never
  /// prompts).
  ///
  /// Screen Recording is a second TCC grant, separate from
  /// Accessibility: a capture needs it, a tree read does not.
  @override
  bool get screenCaptureTrusted {
    _ensureOpen();
    if (bridge case final ScreenCaptureConsentBridge consent) {
      return consent.screenCaptureTrusted();
    }
    throw const DriverUnsupportedException(
      'This bridge does not expose the Screen Recording consent state',
    );
  }

  /// Raises the system consent prompt when untrusted; returns the
  /// resulting status (a manual System Settings step may still be needed).
  bool requestTrust() {
    _ensureOpen();
    return bridge.requestTrust();
  }

  /// Raises the system Accessibility prompt; returns the resulting
  /// status.
  @override
  bool requestAccessibilityConsent() => requestTrust();

  /// Raises the system Screen Recording prompt; returns the resulting
  /// status.
  ///
  /// Explicit user action only: a capture never triggers the prompt, it
  /// refuses with the typed permission exception instead.
  @override
  bool requestScreenCaptureConsent() {
    _ensureOpen();
    if (bridge case final ScreenCaptureConsentBridge consent) {
      return consent.requestScreenCapture();
    }
    throw const DriverUnsupportedException(
      'This bridge does not expose the Screen Recording consent request',
    );
  }

  // -- APP MANAGEMENT (the macOS rung: manage APPLICATIONS, not only
  // whatever currently holds focus) --

  /// The running, Dock-able applications — the discovery record every
  /// app-targeted call consumes.
  @override
  Future<List<MacosApp>> runningApps() async {
    _ensureOpen();
    final result = bridge.appsJson();
    if (result.code != 0) {
      throw ProtocolException('runningApps failed', code: result.code);
    }
    return MacosApp.listFromJson(result.json);
  }

  /// The application that currently owns the key window.
  Future<MacosApp> frontmost() async {
    _ensureOpen();
    final result = bridge.frontmostJson();
    if (result.code == 2) {
      throw const ElementNotFoundException('frontmostApplication', 'frontmost');
    }
    if (result.code != 0) {
      throw ProtocolException('frontmost failed', code: result.code);
    }
    final decoded = jsonDecode(result.json);
    if (decoded is! Map<String, Object?>) {
      throw const ProtocolException('frontmost returned a non-object');
    }
    return MacosApp.fromJson(decoded);
  }

  /// Brings the application with [pid] to the front.
  @override
  Future<void> activate(int pid) async {
    _ensureOpen();
    final code = bridge.activateApp(pid);
    if (code == 7) {
      throw ElementNotFoundException('application', 'activate pid=$pid');
    }
    if (code != 0) {
      throw ProtocolException('activate failed', code: code);
    }
  }

  /// Launches (or activates, if already running) [bundleId]; returns the
  /// application's pid.
  Future<int> launch(String bundleId) async {
    _ensureOpen();
    final pid = bridge.launchApp(bundleId);
    if (pid == -7) {
      throw ElementNotFoundException('application', 'launch $bundleId');
    }
    if (pid < 0) {
      throw ProtocolException('launch failed', code: pid);
    }
    return pid;
  }

  /// Asks the application with [pid] to quit (graceful terminate).
  Future<void> terminate(int pid) async {
    _ensureOpen();
    final code = bridge.terminateApp(pid);
    if (code == 7) {
      throw ElementNotFoundException('application', 'terminate pid=$pid');
    }
    if (code != 0) {
      throw ProtocolException('terminate failed', code: code);
    }
  }

  /// The on-screen, normal-layer windows owned by [pid]
  /// (0 = every regular app) — the discovery record window-scoped
  /// capture consumes.
  /// Set [onScreenOnly] to false for other Spaces and hidden helper windows.
  /// Custom bridges without that optional capability refuse this mode.
  @override
  Future<List<MacosWindow>> windows({
    int pid = 0,
    bool onScreenOnly = true,
  }) async {
    _ensureOpen();
    final BridgeJsonResult result;
    if (onScreenOnly) {
      result = bridge.windowsJson(pid: pid);
    } else if (bridge case final AllWindowListingBridge expanded) {
      result = expanded.allWindowsJson(pid: pid);
    } else {
      throw const DriverUnsupportedException(
        'This bridge does not support offscreen window discovery',
      );
    }
    if (result.code != 0) {
      throw ProtocolException('windows failed', code: result.code);
    }
    return MacosWindow.listFromJson(result.json);
  }

  /// Captures one window's PNG (occlusion included, exact window
  /// bounds); [maxPx] caps the long side when set. Needs Screen
  /// Recording consent, not Accessibility.
  ///
  /// The base OS facade carries only the PNG cap; [windowCapture] is
  /// the options-aware sibling (encoding included).
  @override
  Future<Uint8List> windowScreenshot(int windowId, {int? maxPx}) async {
    _ensureOpen();
    final result = bridge.screenshotWindowPng(
      windowId: windowId,
      maxPx: maxPx ?? 0,
    );
    if (result.code == 2) {
      throw ElementNotFoundException('window', 'screenshot #$windowId');
    }
    return _capturedBytes(result, 'window screenshot');
  }

  /// One window PNG plus device-pixel dimensions and scale (ADR 0008).
  ///
  /// [maxPx] downscales the returned image; [scale] maps returned image
  /// pixels back to window points (width / bounds.width).
  Future<({
    Uint8List bytes,
    int width,
    int height,
    double scale,
  })> windowCaptureFrame(int windowId, {int maxPx = 0}) async {
    final bytes = await windowScreenshot(windowId, maxPx: maxPx);
    final (width, height) = _pngDeviceSize(bytes);
    final window = await _windowById(windowId);
    final bounds = window.bounds;
    final scale = bounds == null || bounds.width <= 0
        ? 1.0
        : width / bounds.width;
    return (bytes: bytes, width: width, height: height, scale: scale);
  }

  /// Scroll wheel lines into the anchored application (pid-scoped).
  Future<void> scrollToAnchored({required double dx, required double dy}) async {
    final pid = targetPid ?? _observedPid;
    if (pid == null) {
      throw const ProtocolException(
        'scroll requires an anchored application (app: {pid})',
        code: 6,
      );
    }
    _pointerCheck(bridge.scrollToPid(pid, dx: dx, dy: dy), 'scroll');
  }

  /// Moves the pointer on the anchored pid at screen coordinates.
  Future<void> pointerMoveToAnchored(
    double screenX,
    double screenY, {
    List<String> modifiers = const [],
  }) async {
    final pid = _requireAnchorPid('pointer move');
    _pointerCheck(
      bridge.pointerMoveToPid(
        pid,
        x: screenX,
        y: screenY,
        modifiers: modifiers,
      ),
      'move pointer',
    );
  }

  /// Drag in window-local points via pid-scoped pointer events (ADR 0008).
  Future<void> dragWindowPixel({
    required int windowId,
    required double fromX,
    required double fromY,
    required double toX,
    required double toY,
    String button = 'left',
    List<String> modifiers = const [],
  }) async {
    final window = await _windowById(windowId);
    final anchorPid = targetPid ?? _observedPid ?? window.pid;
    final (sx0, sy0) = _screenPointForWindowLocal(window, fromX, fromY);
    final (sx1, sy1) = _screenPointForWindowLocal(window, toX, toY);
    for (final modifier in modifiers) {
      _check(
        bridge.keyDownToPid(anchorPid, modifierKeyName(modifier)),
        'hold ${modifierKeyName(modifier)}',
      );
    }
    _pointerCheck(
      bridge.pointerMoveToPid(
        anchorPid,
        x: sx0,
        y: sy0,
        modifiers: modifiers,
      ),
      'move pointer',
    );
    _pointerCheck(
      bridge.pointerButtonToPid(
        anchorPid,
        x: sx0,
        y: sy0,
        button: button,
        down: true,
        modifiers: modifiers,
      ),
      'press $button',
    );
    _pointerCheck(
      bridge.pointerMoveToPid(
        anchorPid,
        x: sx1,
        y: sy1,
        modifiers: modifiers,
      ),
      'drag carry',
    );
    _pointerCheck(
      bridge.pointerButtonToPid(
        anchorPid,
        x: sx1,
        y: sy1,
        button: button,
        down: false,
        modifiers: modifiers,
      ),
      'release $button',
    );
    for (final modifier in modifiers.reversed) {
      _check(
        bridge.keyUpToPid(anchorPid, modifierKeyName(modifier)),
        'release ${modifierKeyName(modifier)}',
      );
    }
  }

  /// Captures one window's frame honoring [options] — the options-aware
  /// sibling of [windowScreenshot] (the base OS facade carries only the
  /// PNG cap).
  Future<Uint8List> windowCapture(int windowId, CaptureOptions options) =>
      _captureWith(options, windowId: windowId);

  /// The accessibility element at top-left-origin screen coordinates
  /// (the same system CGEvent mouse coordinates use). This is the hover
  /// query: throttle it to pointer-cadence, never per frame.
  Future<AxNode> elementAtPosition(double x, double y) async {
    _ensureOpen();
    if (!bridge.axTrusted()) {
      throw const AccessibilityPermissionRequiredException();
    }
    final result = bridge.elementAtPositionJson(x: x, y: y);
    final node = _nodeFromResult(result, 'elementAtPosition');
    return node;
  }

  @override
  Future<Snapshot> snapshot() async {
    _ensureOpen();
    if (!bridge.axTrusted()) {
      throw const AccessibilityPermissionRequiredException();
    }
    if (targetPid != null) return snapshotOfApp(targetPid!);
    final result = bridge.snapshotJson(
      maxDepth: snapshotDepth,
      maxNodes: snapshotMaxNodes,
    );
    final snapshot = _snapshotFrom(result);
    // The bridge stamps the observed application's pid on the root —
    // the focus contract's reference point for focused sessions.
    _observedPid = int.tryParse(snapshot.roots.first.attributes['pid'] ?? '');
    return snapshot;
  }

  /// Observes ANY running application's tree by pid — the background-app
  /// read the focused-app-only [snapshot] could not do (7 = unknown pid).
  Future<Snapshot> snapshotOfApp(int pid) async {
    _ensureOpen();
    if (!bridge.axTrusted()) {
      throw const AccessibilityPermissionRequiredException();
    }
    final result = bridge.snapshotAppJson(
      maxDepth: snapshotDepth,
      maxNodes: snapshotMaxNodes,
      pid: pid,
      preferWebContent: preferWebContent ? 1 : 0,
    );
    if (result.code == 7) {
      throw ElementNotFoundException('application', 'snapshot pid=$pid');
    }
    final snapshot = _snapshotFrom(result);
    _observedPid = pid;
    return snapshot;
  }

  Snapshot _snapshotFrom(BridgeJsonResult result) {
    final root = _nodeFromResult(result, 'snapshot');
    _revision += 1;
    _lastObservationAt = DateTime.now();
    _lastSnapshot = Snapshot(
      roots: [root],
      capturedAt: DateTime.now().toUtc(),
      revision: _revision,
    );
    return _lastSnapshot!;
  }

  @override
  Future<void> perform(AutomationAction action) async {
    _ensureOpen();
    switch (action) {
      case ClickAction(:final css, :final role, :final name):
        if (css != null) {
          throw const DriverUnsupportedException(
            'macOS AX has no css locator; click by role or name '
            '(resolved against the latest snapshot)',
          );
        }
        await _click(role: role, name: name);
      case TypeAction(:final text, :final css, :final submit):
        if (css != null) {
          throw const DriverUnsupportedException(
            'macOS AX has no css locator; the focused control receives '
            'the text (focus one via ClickAction first)',
          );
        }
        final pid = targetPid;
        if (pid != null) {
          // Anchored session (ADR 0064 rung): keyboard events post
          // straight to the target's event queue — the user's focus
          // never moves. Fire-and-forget delivery.
          _check(bridge.typeTextToPid(pid, text), 'type text (pid $pid)');
          if (submit) {
            _check(bridge.keyPressToPid(pid, 'Enter'), 'press Enter');
          }
          break;
        }
        await ensureForeground(action);
        _check(bridge.typeText(text), 'type text');
        if (submit) _check(bridge.keyPress('Enter'), 'press Enter');
      case KeyPressAction(:final key, :final modifiers):
        final pid = targetPid;
        if (pid != null) {
          _pidScopedKeyPress(pid, key, modifiers);
          break;
        }
        await ensureForeground(action);
        if (modifiers.isEmpty) {
          final code = bridge.keyPress(key);
          if (code == 1) {
            throw DriverUnsupportedException(
              'key "$key" is not mapped by the macOS driver',
            );
          }
          _check(code, 'press key $key');
        } else {
          // The chord: hold the modifiers, tap the key, release in
          // reverse — each modifier key event announces its flag.
          for (final modifier in modifiers) {
            _check(
              bridge.keyDown(modifierKeyName(modifier)),
              'hold ${modifierKeyName(modifier)}',
            );
          }
          final code = bridge.keyPress(key);
          if (code == 1) {
            throw DriverUnsupportedException(
              'key "$key" is not mapped by the macOS driver',
            );
          }
          _check(code, 'press key $key');
          for (final modifier in modifiers.reversed) {
            _check(
              bridge.keyUp(modifierKeyName(modifier)),
              'release ${modifierKeyName(modifier)}',
            );
          }
        }
      case ScrollAction(:final direction, :final distance):
        if (targetPid != null) {
          final (dx, dy) = _scrollLines(direction, distance);
          await scrollToAnchored(dx: dx, dy: dy);
          break;
        }
        await ensureForeground(action);
        await _scroll(direction, distance);
      case NavigateAction(:final url):
        // ADR 0003: no AX navigation surface exists, so navigate hands
        // the URL to the OS default handler instead of refusing. The
        // opened browser is untracked — observe it by anchoring the
        // browser app, drive it through a CDP session.
        validateOpenableUrl(url);
        await _openUrl(url);
      case EvaluateAction(:final expression):
        throw DriverUnsupportedException(
          'AX cannot evaluate expressions (${expression.length} chars); '
          'evaluation is an instrumented-tier capability',
          details: const {
            'remedy':
                'configure a browser tier (serve --cdp, env '
                'UNIVERSAL_AUTOMATION_CDP, or --browser-handle) and '
                're-send with transport "cdp"',
          },
        );
      case InvokeAction(:final name):
        throw DriverUnsupportedException(
          'the AX tier has no surface action registry; '
          'InvokeAction("$name") needs the instrumented or CDP tier',
          details: const {
            'remedy':
                'use elementAction for AX-advertised actions, or '
                'configure a browser tier (serve --cdp, env '
                'UNIVERSAL_AUTOMATION_CDP, or --browser-handle)',
          },
        );
      case SetValueAction(:final value, :final css, :final role, :final name):
        if (css != null) {
          throw const DriverUnsupportedException(
            'macOS AX has no css locator; set the value by role or name '
            '(resolved against the latest snapshot)',
          );
        }
        await _setValue(value, role: role, name: name);
      case ElementAction(:final action, :final css, :final role, :final name):
        if (css != null) {
          throw const DriverUnsupportedException(
            'macOS AX has no css locator; act by role or name (resolved '
            'against the latest snapshot)',
          );
        }
        await _elementAction(action, role: role, name: name);
      case ClickAtAction(
        :final x,
        :final y,
        :final windowId,
        :final button,
        :final clickCount,
        :final modifiers,
        :final pixelInjection,
      ) when windowId != null && pixelInjection:
        await _clickAtWindowPixel(
          windowId: windowId,
          x: x,
          y: y,
          button: button,
          clickCount: clickCount,
          modifiers: modifiers,
        );
      case ClickAtAction(
        :final x,
        :final y,
        :final windowId,
        :final clickCount,
      ) when windowId != null:
        await _clickAtWindowSemantic(
          windowId: windowId,
          x: x,
          y: y,
          clickCount: clickCount,
        );
      case ClickAtAction(
        :final x,
        :final y,
        :final button,
        :final clickCount,
        :final modifiers,
      ):
        await ensureForeground(action);
        // Chord lowering (ADR 0053): the bridge posts the modifier key
        // events (each announces its CGEventFlag) and the pointer
        // events carry the same mask, so the host sees one chord.
        for (final modifier in modifiers) {
          _check(
            bridge.keyDown(modifierKeyName(modifier)),
            'hold ${modifierKeyName(modifier)}',
          );
        }
        _pointerCheck(
          bridge.pointerMove(x: x, y: y, modifiers: modifiers),
          'move pointer',
        );
        for (var press = 1; press <= clickCount.clamp(1, 3); press++) {
          _pointerCheck(
            bridge.pointerButton(
              x: x,
              y: y,
              button: button,
              down: true,
              clickCount: press,
              modifiers: modifiers,
            ),
            'press $button (click $press)',
          );
          _pointerCheck(
            bridge.pointerButton(
              x: x,
              y: y,
              button: button,
              down: false,
              clickCount: press,
              modifiers: modifiers,
            ),
            'release $button (click $press)',
          );
        }
        for (final modifier in modifiers.reversed) {
          _check(
            bridge.keyUp(modifierKeyName(modifier)),
            'release ${modifierKeyName(modifier)}',
          );
        }
      case MoveAction(:final x, :final y):
        await ensureForeground(action);
        _pointerCheck(bridge.pointerMove(x: x, y: y), 'move pointer');
      case DragAction(
        :final fromX,
        :final fromY,
        :final toX,
        :final toY,
        :final button,
        :final modifiers,
      ):
        await ensureForeground(action);
        for (final modifier in modifiers) {
          _check(
            bridge.keyDown(modifierKeyName(modifier)),
            'hold ${modifierKeyName(modifier)}',
          );
        }
        _pointerCheck(
          bridge.pointerMove(x: fromX, y: fromY, modifiers: modifiers),
          'drag approach',
        );
        _pointerCheck(
          bridge.pointerButton(
            x: fromX,
            y: fromY,
            button: button,
            down: true,
            modifiers: modifiers,
          ),
          'press $button',
        );
        // The bridge posts carried moves as dragged events while the
        // button is down, so this reads as one gesture on the host.
        _pointerCheck(
          bridge.pointerMove(x: toX, y: toY, modifiers: modifiers),
          'drag carry',
        );
        _pointerCheck(
          bridge.pointerButton(
            x: toX,
            y: toY,
            button: button,
            down: false,
            modifiers: modifiers,
          ),
          'release $button',
        );
        for (final modifier in modifiers.reversed) {
          _check(
            bridge.keyUp(modifierKeyName(modifier)),
            'release ${modifierKeyName(modifier)}',
          );
        }
    }
  }

  /// The modifier-chord path over pid-scoped delivery (ADR 0064 rung):
  /// hold the modifiers, tap the key, release in reverse — same event
  /// shape as the focused path, each event posted to [pid].
  void _pidScopedKeyPress(int pid, String key, List<String> modifiers) {
    for (final modifier in modifiers) {
      _check(
        bridge.keyDownToPid(pid, modifierKeyName(modifier)),
        'hold ${modifierKeyName(modifier)}',
      );
    }
    final code = bridge.keyPressToPid(pid, key);
    if (code == 1) {
      throw DriverUnsupportedException(
        'key "$key" is not mapped by the macOS driver',
      );
    }
    _check(code, 'press key $key');
    for (final modifier in modifiers.reversed) {
      _check(
        bridge.keyUpToPid(pid, modifierKeyName(modifier)),
        'release ${modifierKeyName(modifier)}',
      );
    }
  }

  /// Captures the main display; [maxPx] caps the long side when set
  /// (the agent-facing image budget). Needs Screen Recording consent.
  @override
  Future<Uint8List> screenshot({int? maxPx}) async {
    _ensureOpen();
    final result = bridge.screenshotPng(maxPx: maxPx ?? 0);
    return _capturedBytes(result, 'screenshot');
  }

  /// Captures one frame of the main display honoring [options] — the
  /// macOS lowering of [ConfigurableCapture].
  ///
  /// The macOS tier captures a NATIVE surface: the main display, or one
  /// window through [windowCapture]. Such a surface has no scroll
  /// extent, so `fullPage` has nothing to reach and is refused loudly
  /// rather than silently reduced to the visible frame. The size cap
  /// and the encoding are honored natively.
  @override
  Future<Uint8List> capture(CaptureOptions options) => _captureWith(options);

  /// The one capture path behind [capture] and [windowCapture].
  Future<Uint8List> _captureWith(
    CaptureOptions options, {
    int? windowId,
  }) async {
    _ensureOpen();
    // An invalid option set is the caller's mistake, not a tier gap:
    // the family refuses it before any bridge call.
    options.ensureValid();
    if (options.fullPage) {
      throw const DriverUnsupportedException(
        'macOS captures a native display or window frame, which has no '
        'scroll extent: there is no beyond-the-viewport surface to '
        'capture (a scrolling tier serves full-page captures)',
      );
    }
    final maxPx = options.maxPx ?? 0;
    final quality = options.quality ?? 0;
    if (options.format == CaptureFormat.jpeg) {
      // The lossy path is a separate native verb, not a re-encode of
      // PNG bytes: a bridge without it refuses instead of shipping the
      // wrong encoding.
      if (bridge case final EncodedCaptureBridge encoded) {
        final result = windowId == null
            ? encoded.screenshotJpeg(maxPx: maxPx, quality: quality)
            : encoded.screenshotWindowJpeg(
                windowId: windowId,
                maxPx: maxPx,
                quality: quality,
              );
        if (windowId != null && result.code == 2) {
          throw ElementNotFoundException('window', 'screenshot #$windowId');
        }
        return _capturedBytes(
          result,
          windowId == null ? 'screenshot' : 'window screenshot',
        );
      }
      throw const DriverUnsupportedException(
        'This bridge cannot encode JPEG captures',
      );
    }
    final result = windowId == null
        ? bridge.screenshotPng(maxPx: maxPx)
        : bridge.screenshotWindowPng(windowId: windowId, maxPx: maxPx);
    if (windowId != null && result.code == 2) {
      throw ElementNotFoundException('window', 'screenshot #$windowId');
    }
    return _capturedBytes(
      result,
      windowId == null ? 'screenshot' : 'window screenshot',
    );
  }

  /// Maps the capture bridge's error codes onto the family's typed
  /// exceptions (10 = the Screen Recording grant is missing).
  Uint8List _capturedBytes(BridgeBytesResult result, String operation) {
    if (result.code == 10) {
      throw const ScreenRecordingPermissionRequiredException();
    }
    if (result.code != 0) {
      throw ProtocolException('$operation failed', code: result.code);
    }
    return result.bytes;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    bridge.releaseAll();
  }


  static (int width, int height) _pngDeviceSize(Uint8List bytes) {
    if (bytes.length < 24) return (0, 0);
    int read(int offset) =>
        (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    return (read(16), read(20));
  }

  int _requireAnchorPid(String verb) {
    final pid = targetPid ?? _observedPid;
    if (pid == null) {
      throw ProtocolException(
        '$verb requires an anchored application (app: {pid})',
        code: 6,
      );
    }
    return pid;
  }

  Future<MacosWindow> _windowById(int windowId) async {
    final anchorPid = targetPid ?? _observedPid;
    final windows = await this.windows(pid: anchorPid ?? 0);
    for (final candidate in windows) {
      if (candidate.windowId == windowId) return candidate;
    }
    throw ElementNotFoundException('window', '#$windowId');
  }

  (double screenX, double screenY) _screenPointForWindowLocal(
    MacosWindow window,
    double x,
    double y,
  ) {
    final bounds = window.bounds;
    if (bounds == null) {
      throw ElementNotFoundException('window', 'bounds #${window.windowId}');
    }
    return (bounds.left + x, bounds.top + y);
  }

  Future<void> _clickAtWindowPixel({
    required int windowId,
    required double x,
    required double y,
    required String button,
    required int clickCount,
    required List<String> modifiers,
  }) async {
    final window = await _windowById(windowId);
    final anchorPid = targetPid ?? _observedPid ?? window.pid;
    if (targetPid != null && window.pid != targetPid) {
      throw ProtocolException(
        'window #$windowId belongs to pid ${window.pid}, expected $targetPid',
        code: 6,
      );
    }
    final (screenX, screenY) = _screenPointForWindowLocal(window, x, y);
    for (final modifier in modifiers) {
      _check(
        bridge.keyDownToPid(anchorPid, modifierKeyName(modifier)),
        'hold ${modifierKeyName(modifier)}',
      );
    }
    _pointerCheck(
      bridge.pointerMoveToPid(
        anchorPid,
        x: screenX,
        y: screenY,
        modifiers: modifiers,
      ),
      'move pointer',
    );
    for (var press = 1; press <= clickCount.clamp(1, 3); press++) {
      _pointerCheck(
        bridge.pointerButtonToPid(
          anchorPid,
          x: screenX,
          y: screenY,
          button: button,
          down: true,
          clickCount: press,
          modifiers: modifiers,
        ),
        'press $button (click $press)',
      );
      _pointerCheck(
        bridge.pointerButtonToPid(
          anchorPid,
          x: screenX,
          y: screenY,
          button: button,
          down: false,
          clickCount: press,
          modifiers: modifiers,
        ),
        'release $button (click $press)',
      );
    }
    for (final modifier in modifiers.reversed) {
      _check(
        bridge.keyUpToPid(anchorPid, modifierKeyName(modifier)),
        'release ${modifierKeyName(modifier)}',
      );
    }
  }

  Future<void> _clickAtWindowSemantic({
    required int windowId,
    required double x,
    required double y,
    required int clickCount,
  }) async {
    final anchorPid = targetPid ?? _observedPid;
    final windows = await this.windows(pid: anchorPid ?? 0);
    MacosWindow? window;
    for (final candidate in windows) {
      if (candidate.windowId == windowId) {
        window = candidate;
        break;
      }
    }
    if (window == null || window.bounds == null) {
      throw ElementNotFoundException('window', '#$windowId');
    }
    final bounds = window.bounds!;
    final screenX = bounds.left + x;
    final screenY = bounds.top + y;
    final node = await elementAtPosition(screenX, screenY);
    final hitPid = int.tryParse(node.attributes['pid'] ?? '');
    if (anchorPid != null && hitPid != null && hitPid != anchorPid) {
      throw ProtocolException(
        'window-local clickAt hit pid $hitPid, expected anchored pid $anchorPid',
        code: 6,
      );
    }
    final handle = int.tryParse(node.attributes['axid'] ?? '');
    if (handle == null) {
      throw ElementNotFoundException('position', '$x,$y');
    }
    for (var press = 1; press <= clickCount.clamp(1, 3); press++) {
      _check(bridge.press(handle), 'press (window-local)');
    }
  }

  Future<void> _click({String? role, String? name}) async {
    var handle = _resolveHandle(role: role, name: name);
    if (handle == null) {
      // Locators go stale as surfaces change; re-observe once before
      // declaring the element missing.
      await snapshot();
      handle = _resolveHandle(role: role, name: name);
    }
    if (handle == null) {
      throw ElementNotFoundException(
        role != null ? 'role' : 'name',
        role ?? name ?? '',
      );
    }
    final code = bridge.press(handle);
    if (code == 5) {
      // Stale native handle (surface rebuilt between snapshot and press).
      await snapshot();
      final retry = _resolveHandle(role: role, name: name);
      if (retry == null) {
        throw ElementNotFoundException(
          role != null ? 'role' : 'name',
          role ?? name ?? '',
        );
      }
      _check(bridge.press(retry), 'press');
      return;
    }
    _check(code, 'press');
  }

  /// Resolves [role]/[name] against the latest snapshot, re-observing
  /// once when the locators went stale.
  Future<int> _handleFor({String? role, String? name}) async {
    var handle = _resolveHandle(role: role, name: name);
    if (handle == null) {
      await snapshot();
      handle = _resolveHandle(role: role, name: name);
    }
    if (handle == null) {
      throw ElementNotFoundException(
        role != null ? 'role' : 'name',
        role ?? name ?? '',
      );
    }
    return handle;
  }

  /// Retries [apply] once through a fresh observation when the native
  /// handle went stale between snapshot and use.
  Future<void> _withFreshHandle(
    int Function(int handle) apply, {
    required String operation,
    required String? role,
    required String? name,
  }) async {
    final handle = await _handleFor(role: role, name: name);
    var code = apply(handle);
    if (code == 5) {
      await snapshot();
      final retry = _resolveHandle(role: role, name: name);
      if (retry == null) {
        throw ElementNotFoundException(
          role != null ? 'role' : 'name',
          role ?? name ?? '',
        );
      }
      code = apply(retry);
    }
    if (code == 0) return;
    if (code == 3) {
      throw ProtocolException(
        '$operation refused by the host for this element (unadvertised '
        'action or not settable?)',
        code: code,
      );
    }
    _check(code, operation);
  }

  /// The semantic write path (ADR 0064): sets the element's value
  /// attribute in background — no keyboard focus, no event stream.
  Future<void> _setValue(String value, {String? role, String? name}) =>
      _withFreshHandle(
        (handle) => bridge.setValue(handle, value),
        operation: 'set value',
        role: role,
        name: name,
      );

  /// Performs one advertised element action (ADR 0064) — the general
  /// form of AXPress; valid on background targets.
  Future<void> _elementAction(String action, {String? role, String? name}) =>
      _withFreshHandle(
        (handle) => bridge.performElementAction(handle, action),
        operation: 'element action "$action"',
        role: role,
        name: name,
      );

  int? _resolveHandle({String? role, String? name}) {
    final snapshot = _lastSnapshot;
    if (snapshot == null) return null;
    final matches = snapshot.nodes
        .where(
          (node) =>
              (role == null || node.role == role.toLowerCase()) &&
              (name == null || node.name == name),
        )
        .toList(growable: false);
    if (matches.length > 1) {
      throw ProtocolException(
        'Ambiguous native element locator',
        details: {'role': role, 'name': name, 'matches': matches.length},
      );
    }
    if (matches.isEmpty) return null;
    final raw = matches.single.attributes['axid'];
    return raw == null ? null : int.tryParse(raw);
  }

  (double, double) _scrollLines(String direction, double? distance) {
    final normalized = direction.toLowerCase();
    final lines = (distance ?? 30) / 10; // ~10 px per wheel line.
    final dx = switch (normalized) {
      'right' => lines,
      'left' => -lines,
      _ => 0.0,
    };
    final dy = switch (normalized) {
      'up' => lines,
      'down' => -lines,
      _ => 0.0,
    };
    if (dx == 0 && dy == 0) {
      throw DriverUnsupportedException(
        'scroll direction "$direction" is not one of up/down/left/right',
      );
    }
    return (dx, dy);
  }

  Future<void> _scroll(String direction, double? distance) async {
    final (dx, dy) = _scrollLines(direction, distance);
    final normalized = direction.toLowerCase();
    _check(bridge.scroll(dx, dy), 'scroll $normalized');
  }

  AxNode _nodeFromResult(BridgeJsonResult result, String operation) {
    switch (result.code) {
      case 0:
        break;
      case 2:
        throw ElementNotFoundException('focusedApplication', operation);
      case 4:
        throw ElementNotFoundException('position', operation);
      case 10:
        throw const AccessibilityPermissionRequiredException();
      default:
        throw ProtocolException('$operation failed', code: result.code);
    }
    final decoded = jsonDecode(result.json);
    if (decoded is! Map<String, Object?>) {
      throw ProtocolException('$operation returned a non-object payload');
    }
    return AxNode.fromJson(decoded);
  }

  void _check(int code, String operation) {
    if (code == 0) return;
    if (code == 5) {
      throw ProtocolException(
        '$operation hit a stale element handle',
        code: code,
      );
    }
    throw ProtocolException('$operation failed', code: code);
  }

  /// Pointer-verb bridge codes map to the same table, with the
  /// Accessibility grant surfacing as the typed permission exception.
  void _pointerCheck(int code, String operation) {
    if (code == 0) return;
    if (code == 10) {
      throw const AccessibilityPermissionRequiredException();
    }
    if (code == 1) {
      throw DriverUnsupportedException(
        '$operation: the macOS bridge does not map that button name '
        '(use left, right, or middle)',
      );
    }
    throw ProtocolException('$operation failed', code: code);
  }

  void _ensureOpen() {
    if (_closed) throw StateError('MacosDriver is closed');
  }
}
