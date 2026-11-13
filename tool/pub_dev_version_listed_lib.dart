import 'dart:convert';

/// Whether [packageApiJson] (pub.dev `/api/packages/<name>` body) lists [version].
///
/// Pub.dev returns `versions` as an array of objects `{ "version": "…", … }`,
/// not a flat string list — `index($v)` on that array is always wrong.
bool pubDevPackageApiListsVersion(
  Map<String, dynamic> packageApiJson,
  String version,
) {
  final raw = packageApiJson['versions'];
  if (raw is! List<dynamic>) {
    return false;
  }
  for (final entry in raw) {
    if (entry is Map<String, dynamic>) {
      if (entry['version'] == version) {
        return true;
      }
    } else if (entry == version) {
      // Tolerate legacy/test fixtures that use a string list.
      return true;
    }
  }
  return false;
}

/// Parses a pub.dev package API JSON string and checks [version].
bool pubDevPackageApiBodyListsVersion(String body, String version) {
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  return pubDevPackageApiListsVersion(decoded, version);
}
