part of 'mcp_server.dart';

/// Bound window for the OpenAI-style computer-use loop (UA ADR 0008).
final class ComputerBind {
  /// Creates a bind record.
  const ComputerBind({
    required this.windowId,
    required this.pid,
    required this.scale,
    required this.frameWidth,
    required this.frameHeight,
  });

  /// CGWindow id for capture and coordinate mapping.
  final int windowId;

  /// Anchored application pid pointer events post to.
  final int pid;

  /// Image pixels per window point for the last capture.
  final double scale;

  /// Width of the last screenshot image in pixels.
  final int frameWidth;

  /// Height of the last screenshot image in pixels.
  final int frameHeight;
}

/// Wire names for OS consent on the computer lane (mirrors
/// `automationComputerUseOsKinds` in `xsoulspace_permission_core`).
const computerUseOsConsentWireNames = [
  PermissionKind.accessibility,
  PermissionKind.screenRecording,
];

/// Permission remedy payload agents should route through
/// [automation_request_consent].
Map<String, Object?> consentRemedy(PermissionKind kind) => {
  'remedy': 'automation_request_consent',
  'consentKind': kind.wireName,
};

/// Runs one `automation_computer` action against [driver].
///
/// Returns the next bind state (unchanged on failures) and the MCP payload.
/// [image] is set when the action produced a screenshot frame.
Future<
  ({
    ComputerBind? bind,
    Map<String, Object?> payload,
    Uint8List? image,
  })
>
handleComputerUseAction({
  required String action,
  required Map<String, Object?> arguments,
  required MacosDriver driver,
  ComputerBind? bind,
  Future<void> Function(PermissionKind kind, String title)? requireConsent,
}) async {
  switch (action) {
    case 'bind':
      return _bind(driver, arguments, bind, requireConsent);
    case 'unbind':
      return (
        bind: null,
        payload: {'ok': true, 'bound': false},
        image: null,
      );
    case 'screenshot':
      return _screenshot(driver, arguments, bind, requireConsent);
    case 'click':
    case 'double_click':
      return _click(
        driver,
        arguments,
        bind,
        requireConsent,
        clickCount: action == 'double_click' ? 2 : 1,
      );
    case 'move':
      return _pointer(driver, arguments, bind, requireConsent);
    case 'drag':
      return _drag(driver, arguments, bind, requireConsent);
    case 'scroll':
      return _scroll(driver, arguments, bind, requireConsent);
    case 'type':
      return _type(driver, arguments, bind, requireConsent);
    case 'keypress':
      return _keypress(driver, arguments, bind, requireConsent);
    case 'wait':
      return _wait(arguments, bind);
    default:
      throw McpToolError('unknown automation_computer action: $action');
  }
}

Future<
  ({
    ComputerBind? bind,
    Map<String, Object?> payload,
    Uint8List? image,
  })
>
_bind(
  MacosDriver driver,
  Map<String, Object?> arguments,
  ComputerBind? previous,
  Future<void> Function(PermissionKind kind, String title)? requireConsent,
) async {
  await requireConsent?.call(
    PermissionKind.accessibility,
    'Bind a window for computer use',
  );
  if (!driver.axTrusted) {
    throw McpToolError(
      'Accessibility permission required for computer bind',
      details: consentRemedy(PermissionKind.accessibility),
    );
  }
  final anchorPid = driver.targetPid;
  final windowId = arguments['windowId'];
  final windows = await driver.windows(pid: anchorPid ?? 0);
  MacosWindow? chosen;
  if (windowId is int) {
    for (final window in windows) {
      if (window.windowId == windowId) {
        chosen = window;
        break;
      }
    }
    if (chosen == null) {
      throw McpToolError('windowId $windowId not found for anchored app');
    }
  } else {
    chosen = _largestOnScreen(windows, anchorPid);
    if (chosen == null) {
      throw const McpToolError('computer bind needs a visible window');
    }
  }
  if (anchorPid != null && chosen.pid != anchorPid) {
    throw McpToolError(
      'window ${chosen.windowId} belongs to pid ${chosen.pid}, '
      'expected anchor $anchorPid',
    );
  }
  await requireConsent?.call(
    PermissionKind.screenRecording,
    'Capture the bound window for computer use',
  );
  final frame = await _capture(driver, chosen.windowId, arguments);
  final next = ComputerBind(
    windowId: chosen.windowId,
    pid: anchorPid ?? chosen.pid,
    scale: frame.scale,
    frameWidth: frame.width,
    frameHeight: frame.height,
  );
  return (
    bind: next,
    payload: {
      'ok': true,
      'bound': true,
      'windowId': next.windowId,
      'pid': next.pid,
      'width': next.frameWidth,
      'height': next.frameHeight,
      'scale': next.scale,
    },
    image: null,
  );
}

MacosWindow? _largestOnScreen(List<MacosWindow> windows, int? anchorPid) {
  MacosWindow? best;
  var bestArea = 0.0;
  for (final window in windows) {
    if (anchorPid != null && window.pid != anchorPid) continue;
    if (window.onScreen == false) continue;
    final bounds = window.bounds;
    final area = bounds == null
        ? 1.0
        : bounds.width * bounds.height;
    if (area > bestArea) {
      bestArea = area;
      best = window;
    }
  }
  return best;
}

Future<
  ({
    ComputerBind? bind,
    Map<String, Object?> payload,
    Uint8List? image,
  })
>
_screenshot(
  MacosDriver driver,
  Map<String, Object?> arguments,
  ComputerBind? bind,
  Future<void> Function(PermissionKind kind, String title)? requireConsent,
) async {
  await requireConsent?.call(
    PermissionKind.screenRecording,
    'Screenshot the bound window for computer use',
  );
  final active = bind ?? await _requireBind(driver, arguments, requireConsent);
  final maxPx = arguments['maxPx'] is int ? arguments['maxPx']! as int : 0;
  final frame = await _capture(driver, active.windowId, arguments, maxPx: maxPx);
  final next = ComputerBind(
    windowId: active.windowId,
    pid: active.pid,
    scale: frame.scale,
    frameWidth: frame.width,
    frameHeight: frame.height,
  );
  return (
    bind: next,
    payload: {
      'ok': true,
      'windowId': next.windowId,
      'width': next.frameWidth,
      'height': next.frameHeight,
      'scale': next.scale,
      'bytes': frame.bytes.length,
    },
    image: frame.bytes,
  );
}

Future<({Uint8List bytes, int width, int height, double scale})> _capture(
  MacosDriver driver,
  int windowId,
  Map<String, Object?> arguments, {
  int maxPx = 0,
}) async {
  if (arguments['maxPx'] is int) {
    maxPx = arguments['maxPx']! as int;
  }
  try {
    return await driver.windowCaptureFrame(windowId, maxPx: maxPx);
  } on ScreenRecordingPermissionRequiredException {
    throw McpToolError(
      'Screen Recording permission required for computer screenshot',
      details: consentRemedy(PermissionKind.screenRecording),
    );
  }
}

Future<ComputerBind> _requireBind(
  MacosDriver driver,
  Map<String, Object?> arguments,
  Future<void> Function(PermissionKind kind, String title)? requireConsent,
) async {
  final windowId = arguments['windowId'];
  if (windowId is int) {
    final result = await _bind(
      driver,
      {'windowId': windowId},
      null,
      requireConsent,
    );
    return result.bind!;
  }
  throw const McpToolError(
    'automation_computer needs bind first (action bind) or windowId',
  );
}

(double, double) _imageToWindowLocal(ComputerBind bind, double x, double y) {
  final scale = bind.scale <= 0 ? 1.0 : bind.scale;
  return (x / scale, y / scale);
}

Future<
  ({
    ComputerBind? bind,
    Map<String, Object?> payload,
    Uint8List? image,
  })
>
_click(
  MacosDriver driver,
  Map<String, Object?> arguments,
  ComputerBind? bind,
  Future<void> Function(PermissionKind kind, String title)? requireConsent, {
  required int clickCount,
}) async {
  await requireConsent?.call(
    PermissionKind.accessibility,
    'Pointer actuation for computer use',
  );
  final active = bind ?? await _requireBind(driver, arguments, requireConsent);
  final x = _num(arguments['x'], 'x');
  final y = _num(arguments['y'], 'y');
  final (wx, wy) = _imageToWindowLocal(active, x, y);
  final button = arguments['button'] is String ? arguments['button']! as String : 'left';
  await driver.perform(
    ClickAtAction(
      wx,
      wy,
      windowId: active.windowId,
      pixelInjection: true,
      button: button,
      clickCount: clickCount,
      modifiers: _modifiers(arguments),
    ),
  );
  return (
    bind: active,
    payload: {
      'ok': true,
      'action': clickCount == 2 ? 'double_click' : 'click',
      'x': x,
      'y': y,
      'windowId': active.windowId,
    },
    image: null,
  );
}

Future<
  ({
    ComputerBind? bind,
    Map<String, Object?> payload,
    Uint8List? image,
  })
>
_pointer(
  MacosDriver driver,
  Map<String, Object?> arguments,
  ComputerBind? bind,
  Future<void> Function(PermissionKind kind, String title)? requireConsent,
) async {
  await requireConsent?.call(
    PermissionKind.accessibility,
    'Pointer actuation for computer use',
  );
  final active = bind ?? await _requireBind(driver, arguments, requireConsent);
  final x = _num(arguments['x'], 'x');
  final y = _num(arguments['y'], 'y');
  final (wx, wy) = _imageToWindowLocal(active, x, y);
  final window = await driver.windows(pid: active.pid);
  final record = window.firstWhere(
    (w) => w.windowId == active.windowId,
    orElse: () => throw McpToolError('window ${active.windowId} missing'),
  );
  final bounds = record.bounds;
  if (bounds == null) {
    throw McpToolError('window ${active.windowId} has no bounds');
  }
  final screenX = bounds.left + wx;
  final screenY = bounds.top + wy;
  await driver.pointerMoveToAnchored(screenX, screenY, modifiers: _modifiers(arguments));
  return (
    bind: active,
    payload: {'ok': true, 'action': 'move', 'x': x, 'y': y},
    image: null,
  );
}

Future<
  ({
    ComputerBind? bind,
    Map<String, Object?> payload,
    Uint8List? image,
  })
>
_drag(
  MacosDriver driver,
  Map<String, Object?> arguments,
  ComputerBind? bind,
  Future<void> Function(PermissionKind kind, String title)? requireConsent,
) async {
  await requireConsent?.call(
    PermissionKind.accessibility,
    'Pointer actuation for computer use',
  );
  final active = bind ?? await _requireBind(driver, arguments, requireConsent);
  final fromX = _num(arguments['fromX'] ?? arguments['x'], 'fromX');
  final fromY = _num(arguments['fromY'] ?? arguments['y'], 'fromY');
  final toX = _num(arguments['toX'], 'toX');
  final toY = _num(arguments['toY'], 'toY');
  final (wx0, wy0) = _imageToWindowLocal(active, fromX, fromY);
  final (wx1, wy1) = _imageToWindowLocal(active, toX, toY);
  await driver.dragWindowPixel(
    windowId: active.windowId,
    fromX: wx0,
    fromY: wy0,
    toX: wx1,
    toY: wy1,
    modifiers: _modifiers(arguments),
  );
  return (
    bind: active,
    payload: {'ok': true, 'action': 'drag'},
    image: null,
  );
}

Future<
  ({
    ComputerBind? bind,
    Map<String, Object?> payload,
    Uint8List? image,
  })
>
_scroll(
  MacosDriver driver,
  Map<String, Object?> arguments,
  ComputerBind? bind,
  Future<void> Function(PermissionKind kind, String title)? requireConsent,
) async {
  await requireConsent?.call(
    PermissionKind.accessibility,
    'Scroll actuation for computer use',
  );
  final active = bind ?? await _requireBind(driver, arguments, requireConsent);
  final dx = _num(arguments['dx'] ?? 0, 'dx');
  final dy = _num(arguments['dy'] ?? arguments['deltaY'] ?? 0, 'dy');
  await driver.scrollToAnchored(dx: dx, dy: dy);
  return (
    bind: active,
    payload: {'ok': true, 'action': 'scroll', 'dx': dx, 'dy': dy},
    image: null,
  );
}

Future<
  ({
    ComputerBind? bind,
    Map<String, Object?> payload,
    Uint8List? image,
  })
>
_type(
  MacosDriver driver,
  Map<String, Object?> arguments,
  ComputerBind? bind,
  Future<void> Function(PermissionKind kind, String title)? requireConsent,
) async {
  await requireConsent?.call(
    PermissionKind.accessibility,
    'Keyboard actuation for computer use',
  );
  final active = bind ?? await _requireBind(driver, arguments, requireConsent);
  final text = arguments['text'];
  if (text is! String || text.isEmpty) {
    throw const McpToolError('type needs text');
  }
  await driver.perform(TypeAction(text));
  return (
    bind: active,
    payload: {'ok': true, 'action': 'type', 'chars': text.length},
    image: null,
  );
}

Future<
  ({
    ComputerBind? bind,
    Map<String, Object?> payload,
    Uint8List? image,
  })
>
_keypress(
  MacosDriver driver,
  Map<String, Object?> arguments,
  ComputerBind? bind,
  Future<void> Function(PermissionKind kind, String title)? requireConsent,
) async {
  await requireConsent?.call(
    PermissionKind.accessibility,
    'Keyboard actuation for computer use',
  );
  final active = bind ?? await _requireBind(driver, arguments, requireConsent);
  final key = arguments['key'] ?? arguments['keys'];
  if (key is! String || key.isEmpty) {
    throw const McpToolError('keypress needs key');
  }
  await driver.perform(
    KeyPressAction(key, modifiers: _modifiers(arguments)),
  );
  return (
    bind: active,
    payload: {'ok': true, 'action': 'keypress', 'key': key},
    image: null,
  );
}

Future<
  ({
    ComputerBind? bind,
    Map<String, Object?> payload,
    Uint8List? image,
  })
>
_wait(
  Map<String, Object?> arguments,
  ComputerBind? bind,
) async {
  final ms = arguments['ms'] is int
      ? arguments['ms']! as int
      : (arguments['durationMs'] is int ? arguments['durationMs']! as int : 500);
  final capped = ms.clamp(0, 5000);
  await Future<void>.delayed(Duration(milliseconds: capped));
  return (
    bind: bind,
    payload: {'ok': true, 'action': 'wait', 'ms': capped},
    image: null,
  );
}

double _num(Object? value, String name) {
  if (value is num) return value.toDouble();
  throw McpToolError('automation_computer needs $name as a number');
}

List<String> _modifiers(Map<String, Object?> arguments) {
  final raw = arguments['modifiers'];
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is String) item.toLowerCase(),
  ];
}
