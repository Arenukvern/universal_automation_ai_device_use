import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'release_workflow_publish_structure_lib.dart';

const releasePublishScriptPinsRelPath =
    'tool/release_publish_script_pins.json';

const pinMismatchHelp =
    'update tool/release_publish_script_pins.json in the same PR';

List<String> validateReleasePublishScriptClosure(
  String repoRoot, {
  String? scriptOverlayDir,
}) {
  final errors = <String>[];
  final pinsPath = _resolvePinsPath(repoRoot, scriptOverlayDir);
  final pins = _loadPins(pinsPath);
  if (pins == null) {
    return ['missing $releasePublishScriptPinsRelPath'];
  }

  final required = releasePublishRequiredPinKeys();
  final pinKeys = pins.keys.toSet();
  if (!_pinKeySetsMatch(pinKeys, required)) {
    for (final key in required.difference(pinKeys)) {
      errors.add('release publish script pins missing key $key');
    }
    for (final key in pinKeys.difference(required)) {
      errors.add('release publish script pins extra key $key');
    }
    return errors;
  }

  final bodies = <String, String>{};
  for (final rel in required) {
    bodies[rel] = _readScriptBody(repoRoot, rel, scriptOverlayDir);
    final digest = sha256.convert(utf8.encode(bodies[rel]!)).toString();
    if (digest != pins[rel]) {
      errors.add(
        'release publish script pin mismatch for $rel: $pinMismatchHelp',
      );
    }
  }

  errors.addAll(_validateClosureReferences(bodies));
  errors.addAll(_validatePublishScriptGhWritePolicy(bodies));

  return errors;
}

bool _pinKeySetsMatch(Set<String> pins, Set<String> required) =>
    pins.length == required.length &&
    pins.containsAll(required) &&
    required.containsAll(pins);

String _resolvePinsPath(String repoRoot, String? overlayDir) {
  if (overlayDir != null && _overlayAllowsPinsReplacement(repoRoot, overlayDir)) {
    final overlay = '$overlayDir/release_publish_script_pins.json';
    if (File(overlay).existsSync()) {
      return overlay;
    }
  }
  return '$repoRoot/$releasePublishScriptPinsRelPath';
}

bool _overlayAllowsPinsReplacement(String repoRoot, String overlayDir) {
  final allowed =
      Directory('$repoRoot/tool/contracts/fixtures/release_publish_script_closure')
          .absolute
          .path;
  final absOverlay = Directory(overlayDir).absolute.path;
  return absOverlay == allowed ||
      absOverlay.startsWith('$allowed${Platform.pathSeparator}');
}

Map<String, String>? _loadPins(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) {
    return null;
  }
  return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
}

String _readScriptBody(String repoRoot, String rel, String? overlayDir) {
  if (overlayDir != null) {
    final overlay = '$overlayDir/${rel.split('/').last}';
    if (File(overlay).existsSync()) {
      return File(overlay).readAsStringSync();
    }
  }
  return File('$repoRoot/$rel').readAsStringSync();
}

final _closureRefPatterns = <RegExp>[
  RegExp(r'''bash\s+"\$SCRIPT_DIR/([a-z0-9_]+\.sh)"'''),
  RegExp(r'''bash\s+"\$script_dir/([a-z0-9_]+\.sh)"'''),
  RegExp(r'exec\s+"?\$\(cd[^)]+\)/([a-z0-9_]+\.sh)"'),
  RegExp(r'\bsource\s+[^\n]*tool/release/([a-z0-9_]+\.sh)'),
  RegExp(r'\bbash\s+[^"\n]*tool/release/([a-z0-9_]+\.sh)'),
];

List<String> _validateClosureReferences(Map<String, String> bodies) {
  final errors = <String>[];
  final pinned = bodies.keys.toSet();
  for (final entry in bodies.entries) {
    for (final re in _closureRefPatterns) {
      for (final m in re.allMatches(entry.value)) {
        final base = m.group(1);
        if (base == null) {
          continue;
        }
        final rel = 'tool/release/$base';
        if (!pinned.contains(rel)) {
          errors.add(
            'release publish script closure: ${entry.key} references '
            'unpinned $rel',
          );
        }
      }
    }
  }
  return errors;
}

List<String> _validatePublishScriptGhWritePolicy(Map<String, String> bodies) {
  final errors = <String>[];
  for (final entry in bodies.entries) {
    final name = entry.key.split('/').last;
    final body = entry.value;
    final hasReleaseEdit =
        RegExp(r'\bgh\s+release\s+edit\b', caseSensitive: false).hasMatch(body);
    final hasGhApi =
        RegExp(r'\bgh\s+api\b', caseSensitive: false).hasMatch(body);
    if (name == undraftAllowedScript) {
      if (!RegExp(r'--draft\s*=\s*false', caseSensitive: false)
          .hasMatch(body)) {
        errors.add('$undraftAllowedScript must undraft the GitHub release');
      }
      continue;
    }
    if (name == 'append_draft_release_binary_notes.sh') {
      if (hasReleaseEdit &&
          RegExp(r'--draft\s*=', caseSensitive: false).hasMatch(body)) {
        errors.add(
          'append_draft_release_binary_notes.sh must not change draft state',
        );
      }
      continue;
    }
    if (hasReleaseEdit || hasGhApi) {
      errors.add(
        'only $undraftAllowedScript may gh release edit or gh api '
        '(forbidden in $name)',
      );
    }
  }
  return errors;
}