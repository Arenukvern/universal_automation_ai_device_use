import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_automation_toolkit/src/package_version.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('toolkitPackageVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final doc = loadYaml(pubspec) as Map;
    expect(toolkitPackageVersion, doc['version']);
  });

  test('server.json version matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final doc = loadYaml(pubspec) as Map;
    final serverJson = jsonDecode(File('server.json').readAsStringSync())
        as Map<String, dynamic>;
    expect(serverJson['version'], doc['version']);
  });
}
