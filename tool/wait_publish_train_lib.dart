import 'dart:convert';

/// Tags to watch from release-please `paths_released` outputs.
List<String> releasePleasePublishTags({
  required Map<String, dynamic> outputs,
}) {
  final pathsRaw = outputs['paths_released'];
  if (pathsRaw == null ||
      pathsRaw == '' ||
      pathsRaw == '[]' ||
      pathsRaw == false) {
    return [];
  }
  final paths = jsonDecode(pathsRaw as String) as List<dynamic>;
  final tags = <String>[];
  for (final path in paths) {
    final p = path as String;
    final created = outputs['$p--release_created'];
    if (created != true && created != 'true') {
      continue;
    }
    final tag = outputs['$p--tag_name'] as String?;
    if (tag != null && tag.isNotEmpty) {
      tags.add(tag);
    }
  }
  return tags;
}

/// Failures safe to retry once (idempotent publish skip + transient CI).
bool isRetryablePublishFailure(String? conclusion, String? status) {
  if (status != 'completed') {
    return false;
  }
  return conclusion == 'failure' || conclusion == 'cancelled';
}
