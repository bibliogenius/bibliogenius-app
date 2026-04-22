import 'dart:io';

import 'package:bibliogenius/widgets/cached_book_cover.dart';
import 'package:bibliogenius/widgets/peer_book_cover_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PeerBookCoverCacheManager.resetForTest();
    BookCoverCacheManager.resetEvictedForTest();
  });

  group('PeerBookCoverCacheManager isolation from local cache', () {
    test('uses a distinct cache key from BookCoverCacheManager', () {
      expect(
        PeerBookCoverCacheManager.key,
        isNot(equals(BookCoverCacheManager.key)),
        reason:
            'Peer and local cache keys must differ so they end up in '
            'distinct on-disk directories and JSON metadata repositories. '
            'A shared key would re-enable cross-eviction.',
      );
    });

    test('shares stale period with local cache for consistent UX', () {
      expect(
        PeerBookCoverCacheManager.stalePeriod,
        equals(BookCoverCacheManager.stalePeriod),
        reason:
            'Stale window parity keeps the "how long before re-fetch" '
            'behavior identical across both caches. Divergence would '
            'surprise users switching between peer and local views.',
      );
    });

    test('evictOnce tracks peer URLs independently from the local session set',
        () {
      const url = 'https://peer.example/cover/1.jpg';

      var peerEvictions = 0;
      PeerBookCoverCacheManager.removeFileImpl = (_) {
        peerEvictions += 1;
      };

      PeerBookCoverCacheManager.evictOnce(url);
      PeerBookCoverCacheManager.evictOnce(url);

      expect(peerEvictions, 1,
          reason: 'evictOnce must be idempotent per session');
      expect(
        PeerBookCoverCacheManager.hasBeenEvictedThisSession(url),
        isTrue,
      );
      expect(
        BookCoverCacheManager.hasBeenEvictedThisSession(url),
        isFalse,
        reason:
            'Evicting a peer URL must not mark the same URL as evicted in '
            'the local manager -- the two managers own different files.',
      );
    });
  });

  group('file count cap derivation from MB cap', () {
    test('100 MB cap yields ~2560 files at 40KB/cover estimate', () {
      // 100 * 1024 * 1024 / (40 * 1024) = 2560
      expect(
        PeerBookCoverCacheManager.fileCountCapForTest(100),
        equals(2560),
      );
    });

    test('50 MB cap scales proportionally', () {
      expect(
        PeerBookCoverCacheManager.fileCountCapForTest(50),
        equals(1280),
      );
    });

    test('500 MB cap scales proportionally', () {
      expect(
        PeerBookCoverCacheManager.fileCountCapForTest(500),
        equals(12800),
      );
    });

    test('all Settings-exposed cap values produce positive file counts', () {
      // Guards against a future change to averageCoverSizeBytes that would
      // round down to zero for the smallest supported cap.
      for (final capMb in const [50, 100, 200, 500]) {
        expect(
          PeerBookCoverCacheManager.fileCountCapForTest(capMb),
          greaterThan(0),
          reason: 'cap $capMb MB must produce a non-zero file count',
        );
      }
    });
  });

  group('cap bookkeeping', () {
    test('capMb defaults to defaultCapMb before configure() is called', () {
      expect(
        PeerBookCoverCacheManager.capMb,
        equals(PeerBookCoverCacheManager.defaultCapMb),
      );
    });
  });

  group('clearAll wipes orphans that the JSON index does not know about',
      () {
    // flutter_cache_manager's emptyCache() only deletes files tracked in
    // its JSON index. Partial downloads, artifacts from an older cache
    // format, or files left behind by a crash would keep accruing disk
    // usage that the user cannot reclaim from the Settings button.
    //
    // Regression guard for the "0.5 MB stays after Clear" bug: the test
    // writes a file directly into the cache directory (bypassing the
    // manager's index), then clears, then asserts the directory is
    // really empty.

    late Directory tempRoot;

    setUpAll(() {
      tempRoot = Directory.systemTemp
          .createTempSync('peer_cover_cache_clear_test_');
      PathProviderPlatform.instance =
          _FakePathProviderPlatform(tempRoot.path);
    });

    tearDownAll(() {
      try {
        tempRoot.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('orphan files on disk are removed by clearAll', () async {
      // Materialize the cache directory via the manager's public API.
      final cacheDir = await PeerBookCoverCacheManager.cacheDirectory;
      await cacheDir.create(recursive: true);

      // Plant an orphan: a file the JSON index never heard of.
      final orphan = File('${cacheDir.path}/orphan_cover.jpg');
      await orphan.writeAsBytes(List.filled(512 * 1024, 0)); // 0.5 MB
      expect(await orphan.exists(), isTrue);

      final sizeBefore = await PeerBookCoverCacheManager.diskSizeBytes();
      expect(sizeBefore, greaterThanOrEqualTo(512 * 1024));

      await PeerBookCoverCacheManager.clearAll();

      expect(await orphan.exists(), isFalse,
          reason:
              'clearAll must delete orphans too, otherwise the Settings '
              'button leaves the user stuck at a non-zero usage reading.');
      final sizeAfter = await PeerBookCoverCacheManager.diskSizeBytes();
      expect(sizeAfter, equals(0),
          reason:
              'After Clear the directory should be gone (or empty) -- '
              'the manager re-creates it lazily on the next fetch.');
    });
  });
}
