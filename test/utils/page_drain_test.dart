import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/utils/page_drain.dart';

void main() {
  group('loadPagesUntilDone', () {
    test('loads every page while each call makes progress', () async {
      var remaining = 3;
      var calls = 0;

      await loadPagesUntilDone(
        hasMore: () => remaining > 0,
        loadNext: () async {
          calls++;
          remaining--;
          return true;
        },
      );

      expect(calls, 3);
      expect(remaining, 0);
    });

    test('never calls the loader when nothing is left', () async {
      var calls = 0;

      await loadPagesUntilDone(
        hasMore: () => false,
        loadNext: () async {
          calls++;
          return true;
        },
      );

      expect(calls, 0);
    });

    test('stops when the loader is busy and returns without loading', () async {
      // Regression: a second caller looped on a loader whose in-flight guard
      // made it return at once. Awaiting an already completed future resumes
      // in a microtask, so the loop spun without ever serving the event loop
      // and the screen froze. The cap turns that endless spin into a failure.
      var calls = 0;

      await loadPagesUntilDone(
        hasMore: () => true,
        loadNext: () async {
          calls++;
          if (calls > 5) fail('kept looping on a loader that made no progress');
          return false;
        },
      );

      expect(calls, 1);
    });

    test('stops after a failed page instead of retrying it forever', () async {
      var calls = 0;

      await loadPagesUntilDone(
        hasMore: () => true,
        loadNext: () async {
          calls++;
          if (calls > 5) fail('kept retrying a failing page');
          // Two good pages, then the loader reports a failure.
          return calls <= 2;
        },
      );

      expect(calls, 3);
    });
  });
}
