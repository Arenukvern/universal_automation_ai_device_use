import 'package:test/test.dart';

import 'wait_publish_train_lib.dart';

void main() {
  test('releasePleasePublishTags reads paths_released', () {
    final tags = releasePleasePublishTags(
      outputs: {
        'paths_released': '["pkgs/universal_foo"]',
        'pkgs/universal_foo--release_created': 'true',
        'pkgs/universal_foo--tag_name': 'universal_foo-v1.2.3',
      },
    );
    expect(tags, ['universal_foo-v1.2.3']);
  });

  test('isRetryablePublishFailure', () {
    expect(isRetryablePublishFailure('failure', 'completed'), isTrue);
    expect(isRetryablePublishFailure('success', 'completed'), isFalse);
    expect(isRetryablePublishFailure('failure', 'in_progress'), isFalse);
  });
}
