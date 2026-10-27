@TestOn('vm')
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xsoulspace_tooling_runtime/xsoulspace_tooling_runtime.dart';

void main() {
  final failureBytes = utf8.encode('marker:error:');

  test(
    'trailingPartialMarkerPrefixBytes matches only failure-marker prefix',
    () {
      expect(
        trailingPartialMarkerPrefixBytes(
          utf8.encode('log line\nerror:'),
          failureBytes,
        ),
        0,
        reason: 'internal marker substring is not a true prefix hold',
      );
      expect(
        trailingPartialMarkerPrefixBytes(
          utf8.encode('partial marker:e'),
          failureBytes,
        ),
        utf8.encode('marker:e').length,
      );
    },
  );
}
