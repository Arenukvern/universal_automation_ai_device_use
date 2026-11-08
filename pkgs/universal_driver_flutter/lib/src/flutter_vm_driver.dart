import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'flutter_vm_client.dart';

/// [AutomationDriver] over the MCP toolkit's VM-service extensions — the
/// instrumented tier's observe/act/verify loop in the family vocabulary.
///
/// Locator grammar (the instrumented tier has no CSS):
/// - `css` — a snapshot ref from the latest [snapshot] (`"s_12"`), or a
///   label substring; refs are the stable instrumented element ids.
/// - `name` — first node whose label contains it (case-insensitive).
/// - `role` — first node whose semantic role matches (`button`,
///   `textbox`, …); role and name compose.
///
/// Navigation surface: the toolkit's *named routes* ([NavigateAction]'s
/// path becomes the route name). A URL that is not a registered route is
/// refused loudly — this driver never pretends to be a browser.
///
/// Every act resolves its locator against a fresh snapshot: refs are only
/// meaningful per snapshot, so acts observe first.
final class FlutterVmDriver implements AutomationDriver {
  /// Drives the app behind [client].
  FlutterVmDriver(FlutterVmClient client) : this.custom(client.callExtension);

  /// Drives through a custom [ExtensionCall] (tests, alternate transports).
  FlutterVmDriver.custom(this._call);

  final ExtensionCall _call;

  bool _closed = false;
  int _revision = 0;

  @override
  DriverCapabilities get capabilities => const DriverCapabilities(
    attach: true,
    screenshot: true,
    a11yTree: true,
    inputSynthesis: true,
  );

  @override
  Future<Snapshot> snapshot() async {
    _ensureOpen();
    final data = _unwrap(await _call(ToolkitWire.semanticSnapshot));
    _revision = (data['snapshot_id'] as num?)?.toInt() ?? _revision;
    final flat = <String, Map<String, Object?>>{
      for (final node in (data['nodes'] as List<Object?>? ?? const []))
        if (node is Map && node['ref'] is String)
          node['ref']! as String: _stringMap(node),
    };
    // The wire is flat; `children` holds refs. Nodes nobody links to are
    // the roots — nesting under them rebuilds the tree.
    final linked = <String>{
      for (final node in flat.values)
        ...(node['children'] as List<Object?>? ?? const []).whereType<String>(),
    };
    return Snapshot(
      roots: [
        for (final entry in flat.entries)
          if (!linked.contains(entry.key))
            _axNode(entry.key, entry.value, flat),
      ],
      capturedAt: DateTime.now().toUtc(),
      revision: _revision,
    );
  }

  @override
  Future<void> perform(AutomationAction action) async {
    _ensureOpen();
    switch (action) {
      case NavigateAction(:final url):
        await _navigate(url);
      case ClickAction(:final css, :final role, :final name):
        final ref = await _resolveRef(css: css, role: role, name: name);
        final raw = _unwrap(
          await _call(ToolkitWire.tapWidget, args: {'ref': ref}),
        );
        if (raw['success'] == false) {
          throw ProtocolException(
            'tap refused at ref "$ref": ${raw['error']} — '
            '${raw['hint'] ?? raw['message'] ?? 'no hint'}',
          );
        }
      case TypeAction(:final text, :final css, :final submit):
        if (css == null) {
          throw const DriverUnsupportedException(
            'FlutterVmDriver.type needs a locator (css = ref or label); '
            'the instrumented tier does not type into "whatever is '
            'focused"',
          );
        }
        final ref = await _resolveRef(css: css);
        final raw = _unwrap(
          await _call(ToolkitWire.enterText, args: {'ref': ref, 'text': text}),
        );
        if (raw['success'] == false) {
          throw ProtocolException(
            'enter_text refused at ref "$ref": ${raw['error']} — '
            '${raw['hint'] ?? raw['message'] ?? 'no hint'}',
          );
        }
        if (submit) await _pressKey('Enter');
      case KeyPressAction(:final key):
        await _pressKey(key);
      case ScrollAction(:final direction, :final distance):
        final raw = _unwrap(
          await _call(
            ToolkitWire.scroll,
            args: {
              'direction': direction.toLowerCase(),
              'distance': ?distance,
            },
          ),
        );
        if (raw['success'] == false) {
          throw ProtocolException(
            'scroll refused: ${raw['error']} — ${raw['hint'] ?? 'no hint'}',
          );
        }
      default:
        throw DriverUnsupportedException(
          'FlutterVmDriver does not support ${action.runtimeType} — the '
          'instrumented tier is ref/semantics-addressed (invoke, evaluate '
          'and coordinate verbs live with the composition root or other '
          'tiers)',
        );
    }
  }

  @override
  Future<Uint8List> screenshot() async {
    _ensureOpen();
    final raw = await _call(
      ToolkitWire.viewScreenshots,
      args: {'compress': false},
    );
    final images = (_unwrap(raw)['images'] as List<Object?>? ?? const [])
        .whereType<String>()
        .toList();
    if (images.isEmpty) {
      throw const ProtocolException('view_screenshots returned no images');
    }
    // Multi-view apps list every view; the first is the main one.
    return base64Decode(images.first);
  }

  @override
  Future<void> close() async {
    _closed = true;
  }

  Future<void> _navigate(Uri url) async {
    final route = url.path.isEmpty ? url.toString() : url.path;
    final Map<String, Object?> raw;
    try {
      raw = await _call(
        ToolkitWire.navigate,
        args: {'action': 'push', 'route': route},
      );
    } on Exception catch (error) {
      throw DriverUnsupportedException(
        'FlutterVmDriver refuses navigation to "$url": the app rejected '
        'route "$route" ($error)',
      );
    }
    if (_unwrap(raw)['success'] == false) {
      final error = _unwrap(raw)['error'];
      throw DriverUnsupportedException(
        'FlutterVmDriver refuses navigation to "$url": route "$route" is '
        'not a registered named route of this app${error == null ? '' : ' ($error)'}',
      );
    }
  }

  /// Resolves locators against a fresh snapshot. Order: exact ref, label
  /// substring, role+name compose.
  Future<String> _resolveRef({
    String? css,
    String? role,
    String? name,
  }) async {
    if (css == null && role == null && name == null) {
      throw const DriverUnsupportedException(
        'FlutterVmDriver needs a locator: css (ref or label), name, or role',
      );
    }
    final nodes = (await snapshot()).nodes.toList();
    if (css != null) {
      for (final node in nodes) {
        final candidate = node.attributes['ref'];
        if (candidate != null && candidate == css) return candidate;
      }
      for (final node in nodes) {
        final label = node.name;
        final ref = node.attributes['ref'];
        if (label != null &&
            ref != null &&
            label.toLowerCase().contains(css.toLowerCase())) {
          return ref;
        }
      }
      throw ElementNotFoundException('css', css);
    }
    for (final node in nodes) {
      final label = node.name;
      final ref = node.attributes['ref'];
      final roleOk = role == null || node.role == role;
      final nameOk = name == null ||
          (label != null && label.toLowerCase().contains(name.toLowerCase()));
      if (ref != null && roleOk && nameOk) return ref;
    }
    throw ElementNotFoundException(role != null ? 'role' : 'name', role ?? name!);
  }

  Future<void> _pressKey(String key) async {
    final raw = _unwrap(
      await _call(ToolkitWire.pressKey, args: {'key': key}),
    );
    if (raw['success'] == false) {
      throw ProtocolException(
        'press_key rejected "$key": ${raw['error']} — accepted names: '
        '${raw['acceptedNames'] ?? 'single characters'}',
      );
    }
  }

  /// Nests the flat ref-linked wire nodes into [AxNode]s.
  AxNode _axNode(
    String ref,
    Map<String, Object?> wire,
    Map<String, Map<String, Object?>> flat,
  ) {
    final type = wire['type'] as String?;
    final identifier = wire['identifier'] as String?;
    final bounds = wire['bounds'];
    return AxNode(
      role: _role(type),
      name: (wire['label'] as String?) ?? identifier,
      value: wire['value'] as String?,
      bounds: bounds is Map
          ? AxBounds(
              left: (bounds['left'] as num).toDouble(),
              top: (bounds['top'] as num).toDouble(),
              width: ((bounds['right'] as num) - (bounds['left'] as num))
                  .toDouble(),
              height: ((bounds['bottom'] as num) - (bounds['top'] as num))
                  .toDouble(),
            )
          : null,
      attributes: {
        'ref': ref,
        'type': ?type,
        'identifier': ?identifier,
        if (wire['enabled'] is bool) 'enabled': '${wire['enabled']}',
      },
      children: [
        for (final childRef
            in (wire['children'] as List<Object?>? ?? const [])
                .whereType<String>())
          if (flat[childRef] case final child?) _axNode(childRef, child, flat),
      ],
    );
  }

  /// Maps the toolkit's node classifier onto the family's lowercase
  /// protocol-agnostic roles; the raw type stays in `attributes.type`.
  static String _role(String? type) => switch (type) {
    'textField' => 'textbox',
    'header' => 'heading',
    'tappable' || 'longPressable' || 'widget' || null => 'generic',
    _ => type.toLowerCase(),
  };

  Map<String, Object?> _unwrap(Map<String, dynamic> raw) =>
      (raw['data'] ?? raw) as Map<String, Object?>;

  Map<String, Object?> _stringMap(Map<Object?, Object?> raw) => {
    for (final entry in raw.entries)
      if (entry.key is String) entry.key! as String: entry.value,
  };

  void _ensureOpen() {
    if (_closed) {
      throw StateError('FlutterVmDriver is closed');
    }
  }
}
