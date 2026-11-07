// Canned-extension tests: every wire shape here mirrors the MCP toolkit's
// service-extension envelopes (`flutter_mcp_toolkit_core` is the contract
// source on the registering side).
import 'dart:convert';

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_driver_flutter/universal_driver_flutter.dart';

final class _Canned {
  final calls = <(String, Map<String, Object?>)>[];
  Map<String, Object?> respond(String name, Map<String, Object?> args) =>
      switch (name) {
        ToolkitWire.semanticSnapshot => const {
          'data': {
            'snapshot_id': 7,
            'nodes': [
              {
                'ref': 's_1',
                'type': 'textField',
                'label': 'Email address',
                'identifier': 'email',
                'enabled': true,
                'children': ['s_2'],
              },
              {'ref': 's_2', 'type': 'tappable', 'label': 'Submit form'},
            ],
          },
        },
        ToolkitWire.viewScreenshots => const {
          'data': {'images': ['aGVsbG8=']},
        },
        ToolkitWire.navigate => {'data': {'success': false, 'error': 'unknown'}},
        ToolkitWire.pressKey => const {'data': {'success': true}},
        ToolkitWire.scroll => {'data': {'success': false, 'error': 'bad', 'hint': 'use down'}},
        _ => const {'data': {'success': true}},
      };

  ExtensionCall get call => (name, {args = const {}}) async {
    calls.add((name, args));
    return respond(name, args);
  };
}

Future<FlutterVmDriver> driver(_Canned canned) async =>
    FlutterVmDriver.custom(canned.call);

void main() {
  test('snapshot rebuilds the tree from flat ref-linked nodes', () async {
    final canned = _Canned();
    final d = await driver(canned);
    final snapshot = await d.snapshot();
    expect(snapshot.revision, 7);
    expect(snapshot.roots, hasLength(1));
    final root = snapshot.roots.single;
    // textField maps to the family's protocol-agnostic role.
    expect(root.role, 'textbox');
    expect(root.name, 'Email address');
    expect(root.attributes['ref'], 's_1');
    expect(root.attributes['enabled'], 'true');
    expect(root.children.single.role, 'generic');
  });

  test('click by ref taps the widget', () async {
    final canned = _Canned();
    final d = await driver(canned);
    await d.perform(const ClickAction(css: 's_2'));
    expect(
      canned.calls.map((c) => c.$1),
      containsAll([ToolkitWire.semanticSnapshot, ToolkitWire.tapWidget]),
    );
    final tap = canned.calls.last;
    expect(tap.$1, ToolkitWire.tapWidget);
    expect(tap.$2, {'ref': 's_2'});
  });

  test('click by label substring resolves the ref', () async {
    final canned = _Canned();
    final d = await driver(canned);
    await d.perform(const ClickAction(css: 'submit'));
    expect(canned.calls.last.$2, {'ref': 's_2'});
  });

  test('role and name compose', () async {
    final canned = _Canned();
    final d = await driver(canned);
    // Only a textbox labeled Email exists; role must not degrade to
    // name-only matching.
    await d.perform(const ClickAction(role: 'textbox', name: 'email'));
    expect(canned.calls.last.$2, {'ref': 's_1'});
    expect(
      () => d.perform(const ClickAction(role: 'button', name: 'email')),
      throwsA(isA<ElementNotFoundException>()),
    );
  });

  test('type enters text by ref; submit presses Enter', () async {
    final canned = _Canned();
    final d = await driver(canned);
    await d.perform(const TypeAction('a@b.c', css: 'email', submit: true));
    expect(
      canned.calls.map((c) => c.$1),
      containsAll([ToolkitWire.enterText, ToolkitWire.pressKey]),
    );
    final enter = canned.calls.where((c) => c.$1 == ToolkitWire.enterText).single;
    expect(enter.$2, {'ref': 's_1', 'text': 'a@b.c'});
  });

  test('type without a locator is refused', () async {
    final canned = _Canned();
    final d = await driver(canned);
    expect(
      () => d.perform(const TypeAction('hello')),
      throwsA(isA<DriverUnsupportedException>()),
    );
  });

  test('scroll refusal carries the app-side error and hint', () async {
    final canned = _Canned();
    final d = await driver(canned);
    expect(
      () => d.perform(const ScrollAction(direction: 'up')),
      throwsA(
        isA<ProtocolException>().having(
          (e) => e.message,
          'message',
          contains('bad — use down'),
        ),
      ),
    );
  });

  test('navigate to an unregistered route is refused loudly', () async {
    final canned = _Canned();
    final d = await driver(canned);
    expect(
      () => d.perform(NavigateAction(Uri.parse('/missing'))),
      throwsA(isA<DriverUnsupportedException>()),
    );
  });

  test('screenshot decodes the first view PNG', () async {
    final canned = _Canned();
    final d = await driver(canned);
    final png = await d.screenshot();
    expect(png, base64Decode('aGVsbG8='));
  });

  test('coordinate verbs are refused loudly, not silently', () async {
    final canned = _Canned();
    final d = await driver(canned);
    expect(
      () => d.perform(const ClickAtAction(10, 20)),
      throwsA(isA<DriverUnsupportedException>()),
    );
  });
}
