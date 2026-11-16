import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'release_publish_script_pins_lib.dart';
import 'workspace_pub_constraints_sync.dart';

void main() {
  late String repoRoot;
  late String allowedRoot;

  setUp(() {
    repoRoot = findWorkspaceRepoRoot().path;
    allowedRoot = Directory(
      p.join(repoRoot, releasePublishScriptClosureFixturesRel),
    ).resolveSymbolicLinksSync();
  });

  test('accepts a real subdirectory of the closure fixtures dir', () {
    final inside = p.join(
      repoRoot,
      releasePublishScriptClosureFixturesRel,
      'negative_pins_missing_upload_key',
    );
    expect(isOverlayWithinAllowedRoot(allowedRoot, inside), isTrue);
  });

  test('rejects dotdot traversal outside the allowed dir', () {
    final escape = p.normalize(
      p.join(
        allowedRoot,
        'negative_pins_missing_upload_key',
        '..',
        '..',
        '..',
        '..',
        '..',
        'tmp',
        'pins_overlay_escape',
      ),
    );
    expect(isOverlayWithinAllowedRoot(allowedRoot, escape), isFalse);
  });

  test('rejects symlink that resolves outside the allowed dir', () {
    final tmp = Directory.systemTemp.createTempSync('pins_overlay_symlink_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final outside = Directory(p.join(tmp.path, 'outside'))..createSync();
    final allowed = Directory(p.join(tmp.path, 'allowed'))..createSync();
    final link = Link(p.join(allowed.path, 'escape_link'));
    link.createSync(outside.path);
    expect(isOverlayWithinAllowedRoot(allowed.path, link.path), isFalse);
  });
}