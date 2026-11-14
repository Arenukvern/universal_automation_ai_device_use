import 'dart:io';

import 'package:test/test.dart';

import 'pub_dev_version_listed_lib.dart';

void main() {
  group('pubDevPackageApiListsVersion', () {
    test('object versions array (real pub.dev shape)', () {
      final fixture = <String, dynamic>{
        'name': 'universal_automation_toolkit',
        'versions': [
          {'version': '0.5.0', 'retracted': false},
          {'version': '0.5.1', 'retracted': false},
        ],
      };
      expect(pubDevPackageApiListsVersion(fixture, '0.5.1'), isTrue);
      expect(pubDevPackageApiListsVersion(fixture, '0.3.2'), isFalse);
    });

    test('recorded universal_automation_harness excerpt', () {
      final body = File(
        'tool/test_fixtures/pub_dev_package_api_harness.json',
      ).readAsStringSync();
      expect(pubDevPackageApiBodyListsVersion(body, '0.3.0'), isTrue);
      expect(pubDevPackageApiBodyListsVersion(body, '9.9.9'), isFalse);
    });

    test('index-style string list fixtures still work', () {
      final fixture = <String, dynamic>{
        'versions': ['0.1.0', '0.2.0'],
      };
      expect(pubDevPackageApiListsVersion(fixture, '0.2.0'), isTrue);
    });
  });
}
