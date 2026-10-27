@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:xsoulspace_tooling_runtime/src/owned_session_launch_embed.dart';

void main() {
  test('embedded owned leader is byte-identical to .pl after shebang', () async {
    final entry = Uri.parse(
      'package:xsoulspace_tooling_runtime/xsoulspace_tooling_runtime.dart',
    );
    final lib = await Isolate.resolvePackageUri(entry);
    final packageRoot = File.fromUri(lib!).parent.parent;
    final pl = File('${packageRoot.path}/tool/owned_session_p1_leader.pl');
    expect(pl.existsSync(), isTrue);
    final lines = pl.readAsStringSync().split('\n');
    expect(lines.first.startsWith('#!'), isTrue);
    expect(ownedSessionLaunchEmbed, lines.sublist(1).join('\n'));
  });
}
