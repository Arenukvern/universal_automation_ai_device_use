import 'dart:convert';

import 'package:test/test.dart';

import 'release_github_release_lookup_lib.dart';

void main() {
  test('draft-only release satisfies exists check (paginate semantics)', () {
    final page = parseGithubReleasesPage(jsonEncode([
      {
        'tag_name': 'universal_automation_toolkit-v0.6.1',
        'draft': true,
      },
      {
        'tag_name': 'other-v1.0.0',
        'draft': false,
      },
    ]));
    expect(
      githubReleaseExistsForTag([page], 'universal_automation_toolkit-v0.6.1'),
      isTrue,
    );
    expect(
      githubReleaseExistsForTag([page], 'missing-v0.0.0'),
      isFalse,
    );
  });

  test('published release satisfies exists check', () {
    final page = parseGithubReleasesPage(jsonEncode([
      {'tag_name': 'universal_automation_toolkit-v0.6.1', 'draft': false},
    ]));
    expect(
      githubReleaseExistsForTag([page], 'universal_automation_toolkit-v0.6.1'),
      isTrue,
    );
  });
}