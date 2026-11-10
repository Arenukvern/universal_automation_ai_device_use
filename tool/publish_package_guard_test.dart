import 'dart:io';

import 'package:test/test.dart';

import 'publish_package_guard_lib.dart';

void main() {
  group('parsePublishTagRef', () {
    test('accepts valid tag ref', () {
      final tag = parsePublishTagRef(
        'refs/tags/universal_automation_harness-v0.2.1',
      );
      expect(tag.packageName, 'universal_automation_harness');
      expect(tag.version, '0.2.1');
      expect(tag.pkgDir, 'pkgs/universal_automation_harness');
    });

    test('rejects branch ref', () {
      expect(
        () => parsePublishTagRef('refs/heads/main'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects wrong package prefix', () {
      expect(
        () => parsePublishTagRef('refs/tags/foo-v1.0.0'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('validatePublishablePackageAtTag', () {
    late Directory repoRoot;

    setUp(() {
      repoRoot = Directory.systemTemp.createTempSync('pub-guard-test');
      final pkgDir = Directory('${repoRoot.path}/pkgs/universal_foo');
      pkgDir.createSync(recursive: true);
      File('${pkgDir.path}/pubspec.yaml').writeAsStringSync('''
name: universal_foo
version: 1.2.3
environment:
  sdk: ^3.13.0
''');
    });

    tearDown(() {
      repoRoot.deleteSync(recursive: true);
    });

    test('passes matching name and version', () {
      final tag = parsePublishTagRef('refs/tags/universal_foo-v1.2.3');
      expect(
        () => validatePublishablePackageAtTag(repoRoot: repoRoot, tag: tag),
        returnsNormally,
      );
    });

    test('fails version mismatch', () {
      final tag = parsePublishTagRef('refs/tags/universal_foo-v9.9.9');
      expect(
        () => validatePublishablePackageAtTag(repoRoot: repoRoot, tag: tag),
        throwsA(isA<StateError>()),
      );
    });

    test('fails publish_to none', () {
      File('${repoRoot.path}/pkgs/universal_foo/pubspec.yaml')
          .writeAsStringSync('''
name: universal_foo
version: 1.2.3
publish_to: none
environment:
  sdk: ^3.13.0
''');
      final tag = parsePublishTagRef('refs/tags/universal_foo-v1.2.3');
      expect(
        () => validatePublishablePackageAtTag(repoRoot: repoRoot, tag: tag),
        throwsA(isA<StateError>()),
      );
    });
  });
}
