import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/widgets/cached_book_cover.dart';

/// Regression + contract tests for BookCoverCacheManager.
///
/// The cache config is a bandwidth/freshness contract: shorten the stale
/// window and you re-fetch too often; lengthen it and peers see stale
/// covers for weeks. The eviction helper must stay bounded per URL so dead
/// URLs in a scrollable list do not trigger request storms.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BookCoverCacheManager config', () {
    test('stalePeriod is 7 days (freshness vs bandwidth balance)', () {
      expect(BookCoverCacheManager.stalePeriod, const Duration(days: 7));
    });

    test('caps cache at 500 covers (~20 MB on disk)', () {
      expect(BookCoverCacheManager.maxNrOfCacheObjects, 500);
    });
  });

  group('BookCoverCacheManager.evictOnce', () {
    setUp(() {
      BookCoverCacheManager.resetEvictedForTest();
      // Stub the disk I/O: the real CacheStore hits SQLite via a platform
      // channel that isn't registered in pure-Dart unit tests.
      BookCoverCacheManager.removeFileImpl = (_) {};
    });

    test('marks URL as evicted after first call', () async {
      const url = 'https://example.test/api/books/1/cover';
      expect(BookCoverCacheManager.hasBeenEvictedThisSession(url), isFalse);

      BookCoverCacheManager.evictOnce(url);

      expect(BookCoverCacheManager.hasBeenEvictedThisSession(url), isTrue);
    });

    test('is idempotent per URL (no storm on repeat errors)', () async {
      const url = 'https://example.test/api/books/2/cover';

      BookCoverCacheManager.evictOnce(url);
      BookCoverCacheManager.evictOnce(url);
      BookCoverCacheManager.evictOnce(url);

      // Still just the one session mark; nothing blew up.
      expect(BookCoverCacheManager.hasBeenEvictedThisSession(url), isTrue);
    });

    test('tracks distinct URLs independently', () async {
      const url1 = 'https://example.test/api/books/1/cover';
      const url2 = 'https://example.test/api/books/2/cover';

      BookCoverCacheManager.evictOnce(url1);

      expect(BookCoverCacheManager.hasBeenEvictedThisSession(url1), isTrue);
      expect(BookCoverCacheManager.hasBeenEvictedThisSession(url2), isFalse);
    });

    test('resetEvictedForTest clears the session set', () async {
      const url = 'https://example.test/api/books/3/cover';
      BookCoverCacheManager.evictOnce(url);
      expect(BookCoverCacheManager.hasBeenEvictedThisSession(url), isTrue);

      BookCoverCacheManager.resetEvictedForTest();

      expect(BookCoverCacheManager.hasBeenEvictedThisSession(url), isFalse);
    });
  });
}
