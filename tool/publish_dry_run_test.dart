import 'package:test/test.dart';

import 'publish_dry_run_lib.dart';

void main() {
  group('publishDryRunGateFailed', () {
    test('accepts exit 0', () {
      expect(publishDryRunGateFailed(0), isFalse);
    });

    test('fails on exit 65 (warnings)', () {
      expect(publishDryRunGateFailed(pubPublishDryRunWarningsExitCode), isTrue);
    });

    test('fails on hard errors', () {
      expect(publishDryRunGateFailed(1), isTrue);
    });
  });

  group('formatPublishDryRunGateFailure', () {
    test('names package and warning text for exit 65', () {
      final text = formatPublishDryRunGateFailure(
        packageName: 'universal_foo',
        exitCode: 65,
        combinedOutput: 'Warning: title is not descriptive.\n',
      );
      expect(
        text,
        contains(
          '::error title=universal_foo::pub publish --dry-run failed: warnings (exit 65)',
        ),
      );
      expect(text, contains('Warning: title is not descriptive'));
    });

    test('release-PR gate fails when dry-run would exit 65 only', () {
      const exitCode = pubPublishDryRunWarningsExitCode;
      expect(publishDryRunGateFailed(exitCode), isTrue);
    });
  });
}