import 'dart:convert';

/// Release list lookup used by publish-stage assertions (draft + published).
bool githubReleaseExistsForTag(
  Iterable<List<Map<String, dynamic>>> releasePages,
  String tag,
) {
  for (final page in releasePages) {
    for (final release in page) {
      if (release['tag_name']?.toString() == tag) {
        return true;
      }
    }
  }
  return false;
}

/// Parse one JSON array page from `gh api --paginate repos/.../releases`.
List<Map<String, dynamic>> parseGithubReleasesPage(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! List) {
    return const [];
  }
  return decoded
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}