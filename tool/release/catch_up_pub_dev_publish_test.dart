import 'package:test/test.dart';

import 'catch_up_pub_dev_publish_lib.dart';
import '../pub_dev_version_listed_lib.dart';

final class FakePubDevClient implements PubDevPackageClient {
  FakePubDevClient(this._responses);

  final Map<String, PubDevPackageFetch> _responses;

  @override
  Future<PubDevPackageFetch> fetch(String packageName) async {
    final r = _responses[packageName];
    if (r == null) {
      throw StateError('unexpected fetch for $packageName');
    }
    return r;
  }
}

void main() {
  const pkgA = 'universal_foo';
  const pkgB = 'universal_bar';

  final packages = [
    ReleasePleasePublishablePackage(
      configPath: 'pkgs/foo',
      packageName: pkgA,
    ),
    ReleasePleasePublishablePackage(
      configPath: 'pkgs/bar',
      packageName: pkgB,
    ),
  ];

  test('missing version on pub.dev is dispatched', () async {
    final plan = await planCatchUpPubDevPublish(
      packages: [
        ReleasePleasePublishablePackage(
          configPath: 'pkgs/foo',
          packageName: pkgA,
        ),
      ],
      allGitTags: ['${pkgA}-v1.0.0', '${pkgA}-v0.9.0', '${pkgA}-v1.0.0-beta.1'],
      dedupeTags: {},
      pubDev: FakePubDevClient({
        pkgA: PubDevPackageFound({
          'versions': [
            {'version': '0.9.0'},
          ],
        }),
      }),
    );
    expect(plan.dispatchTags, ['${pkgA}-v1.0.0']);
    expect(plan.skippedAlreadyOnPubDev, isEmpty);
  });

  test('published highest tag is not dispatched', () async {
    final plan = await planCatchUpPubDevPublish(
      packages: packages.sublist(0, 1),
      allGitTags: ['${pkgA}-v1.0.0'],
      dedupeTags: {},
      pubDev: FakePubDevClient({
        pkgA: PubDevPackageFound({
          'versions': [
            {'version': '1.0.0'},
          ],
        }),
      }),
    );
    expect(plan.dispatchTags, isEmpty);
    expect(plan.skippedAlreadyOnPubDev, ['${pkgA}-v1.0.0']);
  });

  test('new release tag is deduped', () async {
    final tag = '${pkgA}-v1.0.0';
    final plan = await planCatchUpPubDevPublish(
      packages: packages.sublist(0, 1),
      allGitTags: [tag],
      dedupeTags: {tag},
      pubDev: FakePubDevClient({
        pkgA: PubDevPackageFound({'versions': []}),
      }),
    );
    expect(plan.dispatchTags, isEmpty);
    expect(plan.skippedDeduped, [tag]);
  });

  test('network error fails without dispatch tags', () async {
    await expectLater(
      planCatchUpPubDevPublish(
        packages: packages.sublist(0, 1),
        allGitTags: ['${pkgA}-v1.0.0'],
        dedupeTags: {},
        pubDev: FakePubDevClient({
          pkgA: PubDevPackageFetchError('timeout'),
        }),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('404 package warns and still plans dispatch', () async {
    final plan = await planCatchUpPubDevPublish(
      packages: packages.sublist(0, 1),
      allGitTags: ['${pkgA}-v1.0.0'],
      dedupeTags: {},
      pubDev: FakePubDevClient({pkgA: PubDevPackageNotFound()}),
    );
    expect(plan.dispatchTags, ['${pkgA}-v1.0.0']);
    expect(plan.neverPublishedPackageWarnings, isNotEmpty);
  });

  test('highestStableReleaseTag ignores prereleases', () {
    expect(
      highestStableReleaseTag(
        packageName: pkgA,
        allTags: ['${pkgA}-v1.1.0-beta.1', '${pkgA}-v1.0.1'],
      ),
      '${pkgA}-v1.0.1',
    );
  });

  test('pubDevPackageApiListsVersion object-shaped versions', () {
    expect(
      pubDevPackageApiListsVersion(
        {
          'versions': [
            {'version': '0.3.1'},
          ],
        },
        '0.3.1',
      ),
      isTrue,
    );
  });
}