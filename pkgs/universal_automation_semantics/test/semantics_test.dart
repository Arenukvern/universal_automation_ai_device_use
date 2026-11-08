import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_automation_semantics/universal_automation_semantics.dart';

AxNode _node(
  String role, {
  String? name,
  String? value,
  String? identifier,
  List<AxNode> children = const [],
}) => AxNode(
  role: role,
  name: name,
  value: value,
  attributes: identifier == null ? const {} : {'identifier': identifier},
  children: children,
);

/// window
///   toolbar (identifier: toolbar)
///     button "New"
///     button "Open"
///   textbox "Email" value ""
///   button "Buy"
Snapshot _fixture({String emailValue = ''}) => Snapshot(
  roots: [
    _node(
      'window',
      name: 'Main',
      children: [
        _node(
          'toolbar',
          identifier: 'toolbar',
          children: [
            _node('button', name: 'New'),
            _node('button', name: 'Open'),
          ],
        ),
        _node('textbox', name: 'Email', value: emailValue),
        _node('button', name: 'Buy'),
      ],
    ),
  ],
  capturedAt: DateTime.parse('2026-10-08T12:00:00Z'),
  revision: 7,
);

void main() {
  test('refs number the full walk; views only decide what is shown', () {
    final observation = Observation.of(
      _fixture(),
      const SemanticView(subtreeOf: 's_1'), // the toolbar
    );
    // Full walk: window, toolbar, New, Open, Email, Buy = 6 nodes.
    expect(observation.walkedCount, 6);
    // Shown: toolbar + two buttons — but refs stay full-walk.
    expect(observation.nodes.map((n) => n.ref).toList(), [
      's_1',
      's_2',
      's_3',
    ]);
    final rendered = observation.render();
    expect(rendered, contains('# observation rev=7 walked=6 shown=3'));
    expect(rendered, contains('s_2 button "New"'));
    // Resolve works for any full-walk ref, shown or not.
    expect(observation.resolve('s_5').node.name, 'Buy');
  });

  test('identifier selectors and field shaping work', () {
    final observation = Observation.of(
      _fixture(),
      const SemanticView(
        subtreeOf: 'toolbar',
        fields: {SemanticField.role, SemanticField.name},
      ),
    );
    expect(observation.nodes.first.ref, 's_1');
    final rendered = observation.render();
    expect(rendered, isNot(contains('value=')));
  });

  test('trimming hides the tail, admits it in the header, never renumbers',
      () {
    final observation = Observation.of(
      _fixture(),
      const SemanticView(maxNodes: 2),
    );
    expect(observation.trimmed, isTrue);
    expect(observation.render(), contains('TRIMMED'));
    expect(observation.nodes.map((n) => n.ref).toList(), ['s_0', 's_1']);
  });

  test('panes nest their own walks with namespaced refs', () {
    final observation = Observation.of(
      _fixture(),
      const SemanticView(
        maxNodes: 1, // main shows only the window
        panes: {
          'toolbar': SemanticView(subtreeOf: 's_1'),
        },
      ),
    );
    final rendered = observation.render();
    expect(rendered, contains('# pane main'));
    expect(rendered, contains('# pane toolbar'));
    expect(rendered, contains('toolbar.s_1 button "New"'));
    expect(observation.resolve('toolbar.s_1').node.name, 'New');
    expect(observation.walkedCount, 6 + 3); // main walk + pane subtree
  });

  test('a pane selector naming an absent node renders an empty section',
      () {
    final observation = Observation.of(
      _fixture(),
      const SemanticView(panes: {
        'ghost': SemanticView(subtreeOf: 's_99'),
      }),
    );
    final rendered = observation.render();
    expect(rendered, contains('# pane ghost'));
    expect(rendered, isNot(contains('ghost.s_')));
  });

  test('diff reports added, removed, and value-changed rows', () {
    final view = const SemanticView();
    final before = Observation.of(_fixture(), view);
    // "Open" removed, a "Save" button added, Email gained a value.
    final after = Observation.of(
      Snapshot(
        roots: [
          _node(
            'window',
            name: 'Main',
            children: [
              _node(
                'toolbar',
                identifier: 'toolbar',
                children: [
                  _node('button', name: 'New'),
                  _node('button', name: 'Save'),
                ],
              ),
              _node('textbox', name: 'Email', value: 'a@b.c'),
              _node('button', name: 'Buy'),
            ],
          ),
        ],
        capturedAt: DateTime.parse('2026-10-08T12:00:01Z'),
        revision: 8,
      ),
      view,
    );
    final delta = after.diff(before);
    expect(delta.renderedNames(), {'added': ['Save'], 'removed': ['Open'], 'changed': ['Email']});
    expect(delta.render(), contains('+ '));
    expect(delta.render(), contains('- '));
    expect(delta.render(), contains('~ '));
    expect(delta.render(), contains('"a@b.c"'));
  });

  test('a pure reflow with unchanged structure reports no change', () {
    final view = const SemanticView();
    final before = Observation.of(_fixture(), view);
    final after = Observation.of(_fixture(), view); // same tree, new rev
    expect(after.diff(before).isEmpty, isTrue);
    expect(after.diff(before).render(), '# no change');
  });

  test('identified siblings match across reordering (keyed diffing)', () {
    final view = const SemanticView();
    AxNode toolbarNode({required List<AxNode> children}) => _node(
      'toolbar',
      identifier: 'toolbar',
      children: children,
    );
    final before = Observation.of(
      Snapshot(
        roots: [
          _node('window', name: 'Main', children: [
            toolbarNode(children: [
              _node('button', name: 'Save', identifier: 'btn.save'),
              _node('button', name: 'Open', identifier: 'btn.open'),
            ]),
          ]),
        ],
        capturedAt: DateTime.parse('2026-10-08T12:00:00Z'),
        revision: 1,
      ),
      view,
    );
    // Same two buttons, order swapped: identities pair by identifier.
    final after = Observation.of(
      Snapshot(
        roots: [
          _node('window', name: 'Main', children: [
            toolbarNode(children: [
              _node('button', name: 'Open', identifier: 'btn.open'),
              _node('button', name: 'Save', identifier: 'btn.save'),
            ]),
          ]),
        ],
        capturedAt: DateTime.parse('2026-10-08T12:00:01Z'),
        revision: 2,
      ),
      view,
    );
    expect(after.diff(before).render(), '# no change');
  });

  test('a value change on a reordered identified sibling still pairs', () {
    final view = const SemanticView();
    AxNode tree({required String saveValue}) => _node(
      'window',
      name: 'Main',
      children: [
        _node('textbox', name: 'Title', value: saveValue,
            identifier: 'field.title'),
        _node('button', name: 'Buy', identifier: 'btn.buy'),
      ],
    );
    final before = Observation.of(
      Snapshot(
        roots: [tree(saveValue: '')],
        capturedAt: DateTime.parse('2026-10-08T12:00:00Z'),
        revision: 1,
      ),
      view,
    );
    final after = Observation.of(
      Snapshot(
        roots: [
          // Reordered: the button moved before the field; the field's
          // value changed. Keyed matching reports one ~ row, not churn.
          _node('window', name: 'Main', children: [
            _node('button', name: 'Buy', identifier: 'btn.buy'),
            _node('textbox', name: 'Title', value: 'hello',
                identifier: 'field.title'),
          ]),
        ],
        capturedAt: DateTime.parse('2026-10-08T12:00:01Z'),
        revision: 2,
      ),
      view,
    );
    final delta = after.diff(before);
    expect(delta.added, isEmpty);
    expect(delta.removed, isEmpty);
    expect(delta.changed.single.current.ref, 's_2');
    expect(delta.render(), contains('"hello"'));
  });

  test('stale refs fail closed with a reobserve hint', () {
    final observation = Observation.of(
      _fixture(),
      const SemanticView(maxNodes: 1),
    );
    // Hidden-but-walked refs resolve (display ≠ resolution); a ref no
    // walk ever issued does not.
    expect(observation.resolve('s_5').node.name, 'Buy');
    expect(
      () => observation.resolve('s_99'),
      throwsA(
        isA<SemanticRefUnavailableException>().having(
          (error) => error.message,
          'message',
          contains('reobserve'),
        ),
      ),
    );
  });

  test('the wire form round-trips and speaks mcp_flutter filter keys', () {
    const view = SemanticView(
      fields: {SemanticField.role, SemanticField.value},
      subtreeOf: 's_1',
      identifierPrefix: 'nav.',
      maxNodes: 40,
      panes: {'header': SemanticView(maxNodes: 5)},
    );
    final json = view.toJson();
    // The mcp_flutter-compatible keys are exactly these.
    expect(json['subtreeOf'], 's_1');
    expect(json['identifierPrefix'], 'nav.');
    expect(json['fields'], ['role', 'value']);
    final restored = SemanticView.fromJson(json);
    expect(restored.fields, view.fields);
    expect(restored.subtreeOf, 's_1');
    expect(restored.identifierPrefix, 'nav.');
    expect(restored.maxNodes, 40);
    expect(restored.panes['header']!.maxNodes, 5);
    // And a bare mcp_flutter-style filter map parses directly.
    final bare = SemanticView.fromJson({
      'identifierPrefix': 'item-',
      'subtreeOf': '',
      'fields': ['role', 'name', 'value'],
    });
    expect(bare.identifierPrefix, 'item-');
    expect(bare.subtreeOf, isNull); // blank counts as unasked
  });

  test('unknown fields and non-integer caps fail closed', () {
    expect(
      () => SemanticView.fromJson({'fields': ['role', 'aura']}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => SemanticView.fromJson({'maxNodes': 'many'}),
      throwsA(isA<FormatException>()),
    );
  });

  group('nodeAt (bounds grounding, ADR 0053)', () {
    AxNode bounded(
      String role,
      String name,
      double left,
      double top,
      double width,
      double height, [
      List<AxNode> children = const [],
    ]) => AxNode(
      role: role,
      name: name,
      bounds: AxBounds(left: left, top: top, width: width, height: height),
      children: children,
    );

    Snapshot grounded() => Snapshot(
      roots: [
        bounded('window', 'Main', 0, 0, 400, 300, [
          bounded('toolbar', 'Bar', 0, 0, 400, 40),
          bounded('button', 'Buy', 300, 250, 80, 30),
        ]),
      ],
      capturedAt: DateTime.parse('2026-10-08T12:00:00Z'),
      revision: 3,
    );

    test('the innermost node containing the point wins', () {
      final observation = Observation.of(grounded(), const SemanticView());
      // The corner hits window, toolbar, and nothing else — the
      // smallest-area answer is the toolbar.
      expect(observation.nodeAt(2, 2).ref, 's_1');
      // The Buy button beats the window covering the same point.
      expect(observation.nodeAt(310, 260).node.name, 'Buy');
      // Window interior away from children resolves to the window.
      expect(observation.nodeAt(100, 150).node.name, 'Main');
    });

    test('a point no walked node covers fails closed', () {
      final observation = Observation.of(grounded(), const SemanticView());
      expect(
        () => observation.nodeAt(1000, 1000),
        throwsA(isA<SemanticRefUnavailableException>()),
      );
    });

    test('works through a trimmed view (refs stay full-walk)', () {
      final observation = Observation.of(
        grounded(),
        const SemanticView(subtreeOf: 's_1'),
      );
      // The toolbar view never shows the window, yet the point inside
      // the toolbar resolves; the button (not shown) still grounds.
      expect(observation.nodeAt(310, 260).node.name, 'Buy');
      expect(observation.nodeAt(2, 2).ref, 's_1');
    });
  });

  group('render quality (v0.4 compact format)', () {
    AxNode disabled(String name) => AxNode(
      role: 'button',
      name: name,
      attributes: const {'enabled': 'false'},
    );

    Snapshot rich() => Snapshot(
      roots: [
        AxNode(
          role: 'window',
          name: 'Main',
          bounds: AxBounds(left: 0, top: 0, width: 400, height: 300),
          children: [
            disabled('Buy now'),
            _node('button', name: 'Say "hi"'),
            _node('textbox', name: 'Email', value: 'a@b.c', identifier: 'email'),
          ],
        ),
      ],
      capturedAt: DateTime.parse('2026-11-08T12:00:00Z'),
      revision: 1,
    );

    test('lines carry [disabled] and #identifier; empty values vanish', () {
      final text = Observation.of(rich(), const SemanticView()).render();
      expect(text, contains('[disabled]'));
      expect(text, contains('#email'));
      expect(text, contains(r'"Say \"hi\""'));
      expect(text, isNot(contains('value=""')));
      expect(text, contains('value="a@b.c"'));
    });

    test('fields select what renders; ref is always present', () {
      final boundsView = const SemanticView(
        fields: {SemanticField.role, SemanticField.bounds},
      );
      final text = Observation.of(rich(), boundsView).render();
      expect(text, contains('@('));
      expect(text, isNot(contains('"Main"')));
      final roleOnly = const SemanticView(fields: {
        SemanticField.role,
      });
      final line = Observation.of(rich(), roleOnly)
          .render()
          .split('\n')
          .map((row) => row.trim())
          .firstWhere((row) => row.startsWith('s_1'));
      // State suffixes survive field restriction — they gate the control.
      expect(line, 's_1 button [disabled]');
    });

    test('the header accounts for trimming honestly (shown/matched)', () {
      final text = Observation.of(
        _fixture(),
        const SemanticView(maxNodes: 2),
      ).render();
      expect(text, contains('shown=2/6 TRIMMED'));
    });

    test('compact lens: codes, dropped container rows, refs intact', () {
      AxNode container() => AxNode(
        role: 'generic',
        children: [
          AxNode(
            role: 'button',
            name: 'Buy now',
            attributes: const {'enabled': 'false', 'identifier': 'buy'},
          ),
        ],
      );
      final snapshot = Snapshot(
        roots: [_node('window', name: 'Main', children: [container()])],
        capturedAt: DateTime.parse('2026-11-08T12:00:00Z'),
        revision: 2,
      );
      final text = Observation.of(
        snapshot,
        const SemanticView(),
      ).render(lens: SemanticLens.compact);
      expect(text, contains('lens=compact'));
      expect(text, contains('btn "Buy now" !dis #buy'));
      expect(text, isNot(contains(' generic')));
      // Refs survive so the hit line stays actionable.
      expect(text, matches(RegExp(r's_\d+ btn')));
    });

    test('design lens: geometry rows plus clustering footers', () {
      AxNode placed(double left, double top, double width, String name) =>
          AxNode(
            role: 'button',
            name: name,
            bounds: AxBounds(left: left, top: top, width: width, height: 32),
          );
      final snapshot = Snapshot(
        roots: [
          _node('window', name: 'Main', children: [
            placed(72, 100, 160, 'Alpha'),
            placed(72, 200, 160, 'Beta'),
            placed(280, 300, 160, 'Gamma'),
          ]),
        ],
        capturedAt: DateTime.parse('2026-11-08T12:00:00Z'),
        revision: 3,
      );
      final text = Observation.of(
        snapshot,
        const SemanticView(),
      ).render(lens: SemanticLens.design);
      expect(text, contains('lens=design'));
      expect(text, contains('@(72.0,100.0) 160.0x32.0'));
      // Repeated left edge x=72 (2 nodes) and width 160 (3 nodes) cluster.
      expect(text, contains('# cols 72×2'));
      expect(text, contains('# widths 160×3'));
    });

    test('delta rows say WHAT changed: value swap vs pure move', () {
      AxNode placed(double left, double top, {String? value}) => AxNode(
        role: 'slider',
        name: 'Volume',
        value: value,
        bounds: AxBounds(left: left, top: top, width: 10, height: 10),
      );
      final view = const SemanticView();
      final before = Observation.of(
        Snapshot(
          roots: [_node('window', name: 'Main', children: [placed(10, 20, value: '3')])],
          capturedAt: DateTime.parse('2026-11-08T12:00:00Z'),
          revision: 1,
        ),
        view,
      );
      final moved = Observation.of(
        Snapshot(
          roots: [_node('window', name: 'Main', children: [placed(30, 20, value: '3')])],
          capturedAt: DateTime.parse('2026-11-08T12:00:01Z'),
          revision: 2,
        ),
        view,
      );
      final movedDelta = moved.diff(before).render();
      expect(movedDelta, contains('# delta +0 -0 ~1'));
      expect(movedDelta, contains('moved (10.0,20.0) → (30.0,20.0)'));
      // No phantom value swap for a pure move (the row shows the current
      // value once, per the default fields — never `"" → ""`).
      expect(movedDelta, isNot(contains('value="3" →')));
      expect(movedDelta, isNot(contains('"" → ""')));

      final retuned = Observation.of(
        Snapshot(
          roots: [_node('window', name: 'Main', children: [placed(30, 20, value: '9')])],
          capturedAt: DateTime.parse('2026-11-08T12:00:02Z'),
          revision: 3,
        ),
        view,
      );
      final retunedDelta = retuned.diff(moved).render();
      expect(retunedDelta, contains('value="3" → "9"'));
      expect(retunedDelta, isNot(contains('moved')));
    });
  });
}

extension on ObservationDelta {
  Map<String, List<String>> renderedNames() => {
    'added': [for (final node in added) node.node.name ?? node.node.role],
    'removed': [for (final node in removed) node.node.name ?? node.node.role],
    'changed': [for (final change in changed) change.current.node.name ?? ''],
  };
}
