import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'webdriver_client.dart';

/// [AutomationDriver] over a W3C WebDriver session.
///
/// The classic WebDriver protocol has no accessibility-tree endpoint, so
/// `capabilities.a11yTree` is declared `false` and [snapshot] refuses
/// loudly — semantic snapshots for Safari arrive through the OS-native
/// tier, not through WebDriver.
///
/// The tier is also a [ConfigurableCapture], but the standard offers
/// exactly one capture verb: `GET /session/{id}/screenshot` returns a PNG
/// of the current viewport. There is no full-page scope, no size
/// parameter, and no encoding choice, so every capture option beyond the
/// plain viewport PNG refuses loudly rather than silently handing back a
/// cheaper frame.
class WebDriverDriver implements AutomationDriver, ConfigurableCapture {
  /// Creates a driver over a started session.
  WebDriverDriver(this._client);

  final WebDriverClient _client;
  bool _closed = false;

  @override
  DriverCapabilities get capabilities => const DriverCapabilities(
    screenshot: true,
    inputSynthesis: true,
    pointerCoordinates: true,
    semanticWrite: true,
    navigate: true,
  );

  /// The underlying client.
  WebDriverClient get client => _client;

  @override
  Future<Snapshot> snapshot() async {
    throw const DriverUnsupportedException(
      'classic WebDriver has no accessibility-tree endpoint; '
      'use the OS-native tier for semantic snapshots',
    );
  }

  @override
  Future<void> perform(AutomationAction action) async {
    switch (action) {
      case NavigateAction(:final url):
        // ADR 0003: the scheme allowlist binds NavigateAction on every
        // tier, protocol ones included.
        validateOpenableUrl(url);
        await _client.navigate(url);
      case ClickAction(:final css, :final name):
        final element = css != null
            ? await _client.findElementByCss(css)
            : await _client.findElement('link text', name!);
        await _client.elementClick(element);
      case TypeAction(:final text, :final css, :final submit):
        final element = await _client.findElementByCss(css ?? 'body');
        await _client.sendKeys(element, text);
        if (submit) await _client.keyPress('\n');
      case ScrollAction():
        throw const DriverUnsupportedException(
          'surface scrolling is not part of this driver\'s protocol; '
          'it refuses loudly instead of silently dropping it',
        );
      case KeyPressAction(:final key, :final modifiers):
        if (modifiers.isEmpty) {
          final wireKey = _wireKeys[key];
          if (wireKey == null) {
            throw DriverUnsupportedException(
              'WebDriver: key "$key" is not in the supported set '
              '(${_wireKeys.keys.toList()})',
            );
          }
          await _client.keyPress(wireKey);
        } else {
          // A chord is one keyboard source: modifiers down, the key,
          // modifiers up (release order mirrors the press).
          await _client.runInputSources([
            {
              'type': 'key',
              'id': 'keyboard',
              'actions': [
                for (final modifier in modifiers)
                  {'type': 'keyDown', 'value': _wireKey(modifier)},
                {'type': 'keyDown', 'value': _wireKey(key)},
                {'type': 'keyUp', 'value': _wireKey(key)},
                for (final modifier in modifiers.reversed)
                  {'type': 'keyUp', 'value': _wireKey(modifier)},
              ],
            },
          ]);
        }
      case EvaluateAction(:final expression):
        throw DriverUnsupportedException(
          'classic WebDriver has no script endpoint; got '
          '${expression.length} chars',
        );
      case ClickAtAction(
        :final x,
        :final y,
        :final button,
        :final clickCount,
        :final modifiers,
      ):
        // W3C pointer actions carry no click state; multi-clicks are
        // adjacent down/up pairs, which remotes fold into their
        // double/triple-click recognition.
        await _dispatchPointerChord(
          _client,
          modifiers,
          [
            _pointerMove(x, y),
            for (var press = 1; press <= clickCount.clamp(1, 3); press++) ...[
              {'type': 'pointerDown', 'button': _w3cButton(button)},
              {'type': 'pointerUp', 'button': _w3cButton(button)},
            ],
          ],
        );
      case MoveAction(:final x, :final y):
        await _client.runPointerActions([_pointerMove(x, y)]);
      case DragAction(
        :final fromX,
        :final fromY,
        :final toX,
        :final toY,
        :final button,
        :final modifiers,
      ):
        await _dispatchPointerChord(
          _client,
          modifiers,
          [
            _pointerMove(fromX, fromY),
            {'type': 'pointerDown', 'button': _w3cButton(button)},
            _pointerMove(toX, toY),
            {'type': 'pointerUp', 'button': _w3cButton(button)},
          ],
        );
      case InvokeAction(:final name):
        throw DriverUnsupportedException(
          'the WebDriver tier has no surface action registry; '
          'InvokeAction("$name") needs the instrumented or CDP tier',
        );
      case SetValueAction(:final value, :final css) when css != null:
        // Set-value semantics: replace, not append — clear first.
        final element = await _client.findElementByCss(css);
        await _client.clearElement(element);
        await _client.sendKeys(element, value);
      case SetValueAction():
        throw const DriverUnsupportedException(
          'the WebDriver tier sets values by css selector; role/name '
          'semantic writes need the OS or instrumented tier (ADR 0064)',
        );
      case ElementAction(:final action):
        throw DriverUnsupportedException(
          'the WebDriver protocol has no advertised-action surface '
          '(got "$action"); the OS tier is the element-action path',
        );
    }
  }

  @override
  Future<Uint8List> screenshot() => _client.screenshot();

  /// Captures one frame honoring [options].
  ///
  /// Only the plain viewport PNG is servable: the standard's screenshot
  /// verb takes no parameters, so the tier cannot extend the frame, cap
  /// its size, or re-encode it. Each of those refuses with
  /// [DriverUnsupportedException] and names the CDP tier as the route
  /// out; an invalid option set is rejected by [CaptureOptions.ensureValid]
  /// before anything is requested.
  @override
  Future<Uint8List> capture(CaptureOptions options) async {
    options.ensureValid();
    if (options.fullPage) {
      throw const DriverUnsupportedException(
        'the W3C standard has no full-page screenshot: '
        'GET /session/{id}/screenshot captures the viewport only; '
        'use a CDP endpoint (--cdp) for full-page capture',
        details: {
          'remedy': 'use the CDP tier (serve --cdp) for full-page capture',
        },
      );
    }
    if (options.maxPx != null) {
      throw const DriverUnsupportedException(
        'the W3C standard cannot resize a screenshot: '
        'GET /session/{id}/screenshot has no scale parameter; '
        'use a CDP endpoint (--cdp) for a size-capped capture',
        details: {
          'remedy': 'use the CDP tier (serve --cdp) for a size-capped capture',
        },
      );
    }
    if (options.format != CaptureFormat.png) {
      throw const DriverUnsupportedException(
        'the W3C standard returns PNG only: '
        'GET /session/{id}/screenshot has no encoding parameter; '
        'use a CDP endpoint (--cdp) for a JPEG capture',
        details: {
          'remedy': 'use the CDP tier (serve --cdp) for a JPEG capture',
        },
      );
    }
    // The plain viewport PNG is what the standard serves; the driver's
    // own screenshot() is that frame.
    final bytes = await screenshot();
    return bytes;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _client.deleteSession();
  }
}

Map<String, Object?> _pointerMove(double x, double y) => {
  'type': 'pointerMove',
  'duration': 0,
  'x': x,
  'y': y,
  'origin': 'viewport',
};

/// Family button names → W3C pointer-button codes (`left` 0, `middle` 1,
/// `right` 2).
int _w3cButton(String button) => switch (button.toLowerCase()) {
  'middle' => 1,
  'right' => 2,
  _ => 0,
};

/// The family's logical key names → W3C Unicode PUA wire keys, modifier
/// chord names included.
const _wireKeys = <String, String>{
  'Enter': '\uE007',
  'Tab': '\uE004',
  'Escape': '\uE00C',
  'Backspace': '\uE003',
  'ArrowLeft': '\uE012',
  'ArrowUp': '\uE013',
  'ArrowRight': '\uE014',
  'ArrowDown': '\uE015',
  'Shift': '\uE008',
  'Control': '\uE009',
  'Alt': '\uE00A',
  'Meta': '\uE03D',
};

String _wireKey(String key) {
  // Modifiers travel lowercase through the family vocabulary; named
  // keys are capitalized. Look up either shape.
  final wire =
      _wireKeys[key] ??
      _wireKeys[key.isEmpty ? key : key[0].toUpperCase() + key.substring(1)];
  if (wire == null) {
    throw DriverUnsupportedException(
      'WebDriver: key "$key" is not in the supported set '
      '(${_wireKeys.keys.toList()})',
    );
  }
  return wire;
}

/// Lowers one pointer gesture, holding a keyboard source with
/// [modifiers] alongside it when a chord is asked for.
///
/// Tick alignment (W3C dispatches sources tick by tick, idle past a
/// source's list): the key downs land in the opening ticks, then
/// `pause` actions idle the keyboard until the pointer's last tick has
/// passed, so the key ups strictly follow the release.
Future<void> _dispatchPointerChord(
  WebDriverClient client,
  List<String> modifiers,
  List<Map<String, Object?>> pointerActions,
) async {
  if (modifiers.isEmpty) {
    await client.runPointerActions(pointerActions);
    return;
  }
  final keyActions = [
    for (final modifier in modifiers)
      {'type': 'keyDown', 'value': _wireKey(modifier)},
    for (var i = 0; i < pointerActions.length - 1; i++)
      {'type': 'pause', 'duration': 0},
    for (final modifier in modifiers.reversed)
      {'type': 'keyUp', 'value': _wireKey(modifier)},
  ];
  await client.runInputSources([
    {'type': 'key', 'id': 'keyboard', 'actions': keyActions},
    {
      'type': 'pointer',
      'id': 'mouse',
      'parameters': {'pointerType': 'mouse'},
      'actions': pointerActions,
    },
  ]);
}
