import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/widgets/cached_book_cover.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Lets the wiring test construct the real [BookCoverCacheManager.instance]:
/// the underlying CacheManager eagerly resolves its cache directory and
/// metadata store through path_provider, whose platform channel does not
/// exist in a pure test environment.
class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.rootPath);

  final String rootPath;

  @override
  Future<String?> getApplicationSupportPath() async => rootPath;

  @override
  Future<String?> getTemporaryPath() async => rootPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => rootPath;
}

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

    test('caps cache at 2000 covers (~57 MB at the measured 29 KB average)', () {
      // 407 remote covers already exist against the old cap of 500, on a
      // library that keeps growing. Past the cap, LRU eviction on `touched`
      // thrashes: scrolling the list evicts its top, scrolling back
      // re-downloads it.
      expect(BookCoverCacheManager.maxNrOfCacheObjects, 2000);
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

  group('BookCoverCacheManager immutable cover hosts', () {
    test('recognises an Open Library cover URL', () {
      expect(
        BookCoverCacheManager.hasImmutableCoverUrl(
          'https://covers.openlibrary.org/b/isbn/9782070376018-L.jpg',
        ),
        isTrue,
      );
    });

    test('recognises a content-addressed inventaire URL', () {
      expect(
        BookCoverCacheManager.hasImmutableCoverUrl(
          'https://inventaire.io/img/entities/55ca8c0ca790ec29d23838a7ff4d49db',
        ),
        isTrue,
      );
    });

    test('does NOT claim a hub cover URL (its bytes can change)', () {
      expect(
        BookCoverCacheManager.hasImmutableCoverUrl(
          'https://hub.bibliogenius.org/api/directory/node-7/covers/42',
        ),
        isFalse,
      );
    });

    test('does NOT claim this device own cover endpoint', () {
      expect(
        BookCoverCacheManager.hasImmutableCoverUrl(
          'http://192.168.1.20:8000/api/books/42/cover',
        ),
        isFalse,
      );
    });

    test('does not match on a lookalike suffix host', () {
      expect(
        BookCoverCacheManager.hasImmutableCoverUrl(
          'https://evil-inventaire.io/img/entities/abc',
        ),
        isFalse,
      );
    });

    test('tolerates an unparseable URL', () {
      expect(BookCoverCacheManager.hasImmutableCoverUrl('not a url'), isFalse);
    });
  });

  group('BookCoverCacheManager.effectiveValidTill', () {
    final now = DateTime.utc(2026, 8, 17, 17, 0);

    test('extends Open Library max-age=3h to the one-year floor '
        '(no ETag there, so every expiry is a full re-download)', () {
      const url = 'https://covers.openlibrary.org/b/isbn/9782070376018-L.jpg';

      final result = BookCoverCacheManager.effectiveValidTill(
        url,
        now.add(const Duration(hours: 3)),
        now: now,
      );

      expect(result, now.add(BookCoverCacheManager.immutableCoverValidity));
    });

    test('never shortens a host that already promises longer', () {
      const url = 'https://inventaire.io/img/entities/abc';
      final serverValidTill = now.add(const Duration(days: 400));

      final result = BookCoverCacheManager.effectiveValidTill(
        url,
        serverValidTill,
        now: now,
      );

      expect(result, serverValidTill);
    });

    test('leaves a mutable hub cover on the server deadline', () {
      const url = 'https://hub.bibliogenius.org/api/directory/n1/covers/42';
      final serverValidTill = now.add(const Duration(hours: 1));

      final result = BookCoverCacheManager.effectiveValidTill(
        url,
        serverValidTill,
        now: now,
      );

      expect(result, serverValidTill);
    });
  });

  group('CoverFileService', () {
    /// A client whose every response carries [status] and [headers], the way
    /// covers.openlibrary.org answers (short max-age, no ETag).
    http.Client clientAnswering(int status, Map<String, String> headers) {
      return MockClient(
        (_) async => http.Response.bytes(const [1, 2, 3], status,
            headers: headers),
      );
    }

    const openLibraryUrl =
        'https://covers.openlibrary.org/b/isbn/9782070376018-L.jpg';
    const shortMaxAge = {
      'cache-control': 'max-age=10800',
      'content-type': 'image/jpeg',
    };

    test(
      'floors a whitelisted host answering max-age=10800 to one year',
      () async {
        final service = CoverFileService(
          httpClient: clientAnswering(200, shortMaxAge),
        );

        final before = DateTime.now();
        final response = await service.get(openLibraryUrl);
        final after = DateTime.now();

        expect(
          response.validTill.isAfter(before.add(const Duration(days: 364))),
          isTrue,
          reason: 'The 3h max-age must be extended to the one-year floor',
        );
        expect(
          response.validTill.isBefore(after.add(const Duration(days: 366))),
          isTrue,
          reason: 'The floor only extends to one year, never beyond',
        );
      },
    );

    test('floors a 304 revalidation too (validTill is reused as-is by '
        'the cache manager on Not Modified)', () async {
      final service = CoverFileService(
        httpClient: clientAnswering(304, shortMaxAge),
      );

      final before = DateTime.now();
      final response = await service.get(openLibraryUrl);

      expect(response.statusCode, 304);
      expect(
        response.validTill.isAfter(before.add(const Duration(days: 364))),
        isTrue,
        reason: 'A Not Modified response confirms the bytes are unchanged; '
            'dropping the floor there would reinstate the 3h expiry',
      );
    });

    test('leaves a host outside the whitelist on its own max-age', () async {
      final service = CoverFileService(
        httpClient: clientAnswering(200, shortMaxAge),
      );

      final response = await service.get(
        'https://hub.bibliogenius.org/api/directory/n1/covers/42',
      );

      expect(
        response.validTill
            .isBefore(DateTime.now().add(const Duration(hours: 4))),
        isTrue,
        reason: 'A mutable host must keep honouring its own header so a '
            're-uploaded cover still propagates',
      );
    });

    test('instance is wired with CoverFileService (floor active in '
        'production, not only in isolation)', () async {
      final tempRoot = Directory.systemTemp.createTempSync('cover_wiring');
      addTearDown(() {
        if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
      });
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempRoot.path);

      expect(
        BookCoverCacheManager.instance.config.fileService,
        isA<CoverFileService>(),
        reason: 'Dropping fileService from the Config silently reverts to '
            'HttpFileService and the 3h re-download cycle, with every '
            'effectiveValidTill test still green',
      );
    });
  });

  group('BookCoverCacheManager.sweepOrphanFiles', () {
    late Directory dir;

    /// Ages a file past [BookCoverCacheManager.orphanGracePeriod] so the
    /// in-flight-download guard does not spare it.
    void ageFile(File file) {
      file.setLastModifiedSync(
        DateTime.now().subtract(
          BookCoverCacheManager.orphanGracePeriod + const Duration(hours: 1),
        ),
      );
    }

    File writeCover(String name, {int bytes = 1024, bool aged = true}) {
      final file = File(p.join(dir.path, name))
        ..writeAsBytesSync(List.filled(bytes, 0));
      if (aged) ageFile(file);
      return file;
    }

    setUp(() {
      dir = Directory.systemTemp.createTempSync('cover_sweep_test');
      BookCoverCacheManager.cacheDirectoryImpl = () async => dir;
    });

    tearDown(() {
      BookCoverCacheManager.resetSweepHooksForTest();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test(
      'deletes a file the index no longer references, reports bytes',
      () async {
        final tracked = writeCover('kept.webp');
        final orphan = writeCover('leaked.webp', bytes: 2048);
        BookCoverCacheManager.trackedFileNamesImpl = () async => {'kept.webp'};

        final reclaimed = await BookCoverCacheManager.sweepOrphanFiles();

        expect(orphan.existsSync(), isFalse);
        expect(tracked.existsSync(), isTrue);
        expect(reclaimed, 2048);
      },
    );

    test(
      'refuses to sweep on an empty index (may have failed to load)',
      () async {
        final orphan = writeCover('leaked.webp');
        BookCoverCacheManager.trackedFileNamesImpl = () async => <String>{};

        final reclaimed = await BookCoverCacheManager.sweepOrphanFiles();

        expect(orphan.existsSync(), isTrue);
        expect(reclaimed, 0);
      },
    );

    test('spares an untracked file still within the grace period', () async {
      final inFlight = writeCover('downloading.webp', aged: false);
      BookCoverCacheManager.trackedFileNamesImpl = () async => {'other.webp'};

      final reclaimed = await BookCoverCacheManager.sweepOrphanFiles();

      expect(inFlight.existsSync(), isTrue);
      expect(reclaimed, 0);
    });

    test('returns 0 when the cache directory does not exist', () async {
      dir.deleteSync(recursive: true);
      BookCoverCacheManager.trackedFileNamesImpl = () async => {'kept.webp'};

      expect(await BookCoverCacheManager.sweepOrphanFiles(), 0);
    });

    test('never throws when the index lookup fails', () async {
      writeCover('leaked.webp');
      BookCoverCacheManager.trackedFileNamesImpl = () async =>
          throw const FileSystemException('index unreadable');

      expect(await BookCoverCacheManager.sweepOrphanFiles(), 0);
    });
  });
}
