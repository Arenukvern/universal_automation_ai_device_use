// Benchmark: semantic snapshot compression formats — compactness vs
// findability.
//
// Reads the REAL captured snapshots under test/fixtures/, synthesizes
// medium/large trees with a realistic role mix, renders every tree in the
// candidate formats, and scores each on:
//
//   compactness  — bytes, estimated tokens (bytes/4 heuristic for English-
//                  shaped text), line count.
//   clutter      — share of lines that carry no locator value (unnamed,
//                  valueless container rows).
//   findability  — over every name/identifier query the tree exposes: was
//                  the target found at all, uniquely (one hit), actionable
//                  (the hit line carries its `s_N` ref, so the agent can act
//                  without a second call), and the median scan cost (char
//                  offset of the first hit — how much text the model reads
//                  before locating the target).
//
// Deterministic: fixed LCG seed for the synthetic trees, fixed fixture
// order. Run from the package root:
//
//   dart run tool/benchmark_compression.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_automation_semantics/universal_automation_semantics.dart';

void main() {
  final fixtures = [
    _real('screen1 (showcase home, real)', 'test/fixtures/showcase_snapshot.json'),
    _real('screen2 (reconstruct, real)', 'test/fixtures/showcase_screen2.json'),
    _synthetic('medium (synthetic, ~80 nodes)', 14),
    _synthetic('large (synthetic, ~400 nodes)', 62),
  ];
  for (final fixture in fixtures) {
    _report(fixture);
  }
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final class _Fixture {
  _Fixture(this.label, this.snapshot);
  final String label;
  final Snapshot snapshot;
}

_Fixture _real(String label, String path) {
  final raw =
      jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  final roots = (raw['roots'] as List<Object?>? ?? const [])
      .whereType<Map<String, Object?>>()
      .map(AxNode.fromJson)
      .toList();
  return _Fixture(
    label,
    Snapshot(
      roots: roots,
      capturedAt: DateTime.parse('2026-11-08T00:00:00Z'),
      revision: 1,
    ),
  );
}

_Fixture _synthetic(String label, int seed) {
  var state = seed;
  int next(int mod) {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    return state % mod;
  }

  const roles = <String, double>{
    'text': .30,
    'button': .20,
    'generic': .20,
    'textbox': .10,
    'heading': .08,
    'image': .04,
    'checkbox': .05,
    'slider': .03,
  };
  const names = [
    'Email address', 'Billing plan', 'Payment method', 'Save changes',
    'Filter by status', 'Export report', 'Notification settings', 'Profile',
    'Team members', 'Invite colleague', 'Usage this month', 'Downgrade',
    'API keys', 'Webhooks', 'Security', 'Two-factor authentication',
  ];
  const values = ['', '', '', 'a@b.c', '42', 'Professional', 'Enabled'];
  AxNode grow(int depth) {
    final roll = next(100) / 100;
    var acc = 0.0;
    var role = 'generic';
    for (final entry in roles.entries) {
      acc += entry.value;
      if (roll <= acc) {
        role = entry.key;
        break;
      }
    }
    final named = role == 'generic' ? next(3) == 0 : next(10) > 1;
    final children = <AxNode>[
      if (depth < 5 && next(100) < 40 + depth * 15)
        for (var i = next(4); i >= 0; i--) grow(depth + 1),
    ];
    return AxNode(
      role: role,
      name: named ? '${names[next(names.length)]} ${next(90) + 10}' : null,
      value: role == 'textbox' || role == 'slider' ? values[next(values.length)] : null,
      bounds: AxBounds(
        left: next(600).toDouble(),
        top: next(800).toDouble(),
        width: (60 + next(200)).toDouble(),
        height: (16 + next(40)).toDouble(),
      ),
      children: children,
    );
  }

  return _Fixture(
    label,
    Snapshot(
      roots: [for (var i = 0; i < 3; i++) grow(0)],
      capturedAt: DateTime.parse('2026-11-08T00:00:00Z'),
      revision: seed,
    ),
  );
}

// ---------------------------------------------------------------------------
// Formats
// ---------------------------------------------------------------------------

final class _Format {
  _Format(this.name, this.render);
  final String name;
  final String Function(Snapshot) render;
}

String _jsonFormat(Snapshot snapshot) {
  String node(AxNode n) => jsonEncode({
        'role': n.role,
        if (n.name != null) 'name': n.name,
        if (n.value != null) 'value': n.value,
        if (n.attributes['identifier'] != null)
          'identifier': n.attributes['identifier'],
        if (n.bounds != null)
          'bounds': [
            n.bounds!.left, n.bounds!.top, n.bounds!.width, n.bounds!.height,
          ],
        'children': [for (final c in n.children) node(c)],
      });
  return '[${[for (final r in snapshot.roots) node(r)].join(',')}]';
}

String _v04(Snapshot snapshot, {bool bounds = false}) => Observation.of(
      snapshot,
      SemanticView(
        fields: bounds
            ? const {
                SemanticField.role, SemanticField.name, SemanticField.value,
                SemanticField.bounds,
              }
            : SemanticView.defaultFields,
      ),
    ).render();

/// Compact lens: now IN the package (`SemanticLens.compact`) so refs are
/// issued by the same observation walk — the benchmark consumes the real
/// API, not a local fork.
String _compact(Snapshot snapshot) =>
    Observation.of(snapshot, const SemanticView()).render(
      lens: SemanticLens.compact,
    );

/// Aria-style: indentation only, no refs — measures the act-cost penalty
/// of dropping stable handles.
String _ariaish(Snapshot snapshot) {
  final buffer = StringBuffer();
  void walk(AxNode node, int depth) {
    if (node.name != null || node.value != null) {
      buffer.write('${'  ' * depth}- ${node.role}');
      if (node.name != null) buffer.write(' "${_esc(node.name!)}"');
      if (node.value != null && node.value!.isNotEmpty) {
        buffer.write(': ${_esc(node.value!)}');
      }
      buffer.writeln();
    }
    for (final child in node.children) {
      walk(child, depth + 1);
    }
  }

  for (final root in snapshot.roots) {
    walk(root, 0);
  }
  return buffer.toString().trimRight();
}

String _esc(String text) =>
    text.replaceAll('\\', r'\\').replaceAll('"', r'\"');

// ---------------------------------------------------------------------------
// Metrics
// ---------------------------------------------------------------------------

void _report(_Fixture fixture) {
  final formats = [
    _Format('json (wire baseline)', _jsonFormat),
    _Format('v0.4 render', _v04),
    _Format('v0.4 + bounds', (s) => _v04(s, bounds: true)),
    _Format('compact (codes, no noise)', _compact),
    _Format('design (geometry+clusters)', (s) => Observation.of(
          s, const SemanticView()).render(lens: SemanticLens.design)),
    _Format('aria-ish (no refs)', _ariaish),
  ];

  // Queries: every name + identifier the tree exposes (lowercased).
  final queries = <String>{};
  void collect(AxNode node) {
    final name = node.name;
    if (name != null && name.length >= 4) queries.add(name.toLowerCase());
    final id = node.attributes['identifier'];
    if (id != null && id.isNotEmpty) queries.add(id.toLowerCase());
    for (final child in node.children) {
      collect(child);
    }
  }

  for (final root in fixture.snapshot.roots) {
    collect(root);
  }

  final baselineBytes = _jsonFormat(fixture.snapshot).length;
  print('\n=== ${fixture.label} — ${queries.length} locator queries ===');
  print(
    _pad('format', 28) + _pad('bytes', 8) + _pad('tok~', 6) +
        _pad('lines', 6) + _pad('noise%', 7) + _pad('found%', 7) +
        _pad('uniq%', 7) + _pad('act%', 7) + _pad('scan%', 7) +
        _pad('vs json', 8),
  );
  for (final format in formats) {
    final text = format.render(fixture.snapshot);
    final bytes = text.length;
    final lines = text.split('\n').length;
    var noise = 0;
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      final hasName = trimmed.contains('"');
      final hasValue = RegExp(r'=\S').hasMatch(trimmed);
      final isContainer = trimmed.endsWith('g') || trimmed.endsWith('scr');
      if (trimmed.isNotEmpty && !hasName && !hasValue && isContainer) noise++;
    }
    var found = 0, unique = 0, actionable = 0;
    final scans = <double>[];
    for (final query in queries) {
      final lower = text.toLowerCase();
      final index = lower.indexOf(query);
      if (index < 0) continue;
      found++;
      final lineStart = lower.lastIndexOf('\n', index) + 1;
      final lineEnd = lower.indexOf('\n', index);
      final line = lower.substring(
        lineStart,
        lineEnd < 0 ? lower.length : lineEnd,
      );
      if (RegExp(r'\bs_\d+\b').hasMatch(line)) actionable++;
      if (lower.indexOf(query, index + 1) < 0) unique++;
      scans.add(index / lower.length);
    }
    final total = queries.length;
    double pct(int n) => total == 0 ? 100 : (100 * n / total);
    scans.sort();
    final medianScan = scans.isEmpty
        ? 0.0
        : (scans[(scans.length - 1) ~/ 2] * 100);
    print(
      _pad(format.name, 28) + _pad('$bytes', 8) + _pad('${(bytes / 4).round()}', 6) +
          _pad('$lines', 6) + _pad('${pct(noise).toStringAsFixed(0)}', 7) +
          _pad('${pct(found).toStringAsFixed(0)}', 7) +
          _pad('${pct(unique).toStringAsFixed(0)}', 7) +
          _pad('${pct(actionable).toStringAsFixed(0)}', 7) +
          _pad('${medianScan.toStringAsFixed(0)}', 7) +
          _pad('${(100 * bytes / baselineBytes).toStringAsFixed(0)}%', 8),
    );
  }
}

String _pad(String text, int width) => text.padRight(width);
