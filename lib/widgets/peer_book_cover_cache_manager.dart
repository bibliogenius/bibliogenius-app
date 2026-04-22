import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

/// Cache manager for peer library book covers.
///
/// Kept strictly separate from [BookCoverCacheManager] so that an eviction
/// triggered by a peer cover never drops a locally-owned cover, and so the
/// user can bound the disk footprint of peer covers without affecting their
/// own library. Uses its own cache key -- which becomes both the on-disk
/// subdirectory and the name of the JSON metadata repository.
class PeerBookCoverCacheManager {
  static const String key = 'peerBookCoversCache';

  /// Default cap used when no user preference has been persisted yet.
  static const int defaultCapMb = 100;

  /// Parity with [BookCoverCacheManager.stalePeriod]: 7 days keeps stale
  /// covers bounded while remaining cheap on disk and bandwidth.
  @visibleForTesting
  static const Duration stalePeriod = Duration(days: 7);

  /// Conservative estimate of a cover's on-disk size, used to translate the
  /// user-facing MB cap into flutter_cache_manager's `maxNrOfCacheObjects`
  /// (which is the only cap lever the library exposes). Chosen under the
  /// post-padding target of 50 KB so the file count cap slightly
  /// under-provisions vs the MB budget, leaving headroom for third-party
  /// hubs or legacy non-padded covers.
  @visibleForTesting
  static const int averageCoverSizeBytes = 40 * 1024;

  /// Safety margin applied by [enforceCapFromDisk]: only sweep when real
  /// disk usage exceeds the cap by more than this ratio. Avoids thrashing
  /// when the count-based cap is close to the MB cap.
  @visibleForTesting
  static const double diskOvershootTolerance = 1.1;

  static CacheManager? _instance;
  static int _capMb = defaultCapMb;
  static final Set<String> _evictedThisSession = {};

  /// Test hook mirroring [BookCoverCacheManager.removeFileImpl]. Production
  /// code routes to the real cache manager; tests swap this to avoid
  /// touching platform channels.
  @visibleForTesting
  static FutureOr<void> Function(String url) removeFileImpl =
      _defaultRemoveFile;

  static int _fileCountCap(int capMb) =>
      (capMb * 1024 * 1024 / averageCoverSizeBytes).round();

  /// Accessor used by [CachedBookCover] when rendering peer covers.
  /// Returns the current manager -- rebuilt whenever the cap changes.
  static CacheManager get instance {
    _instance ??= _build(_capMb);
    return _instance!;
  }

  /// Current user-facing cap in MB.
  static int get capMb => _capMb;

  /// Apply the user preference read from storage. Must be called at app
  /// startup (and whenever the user changes the cap in Settings). Triggers
  /// [enforceCapFromDisk] to recover from cases where real covers averaged
  /// above [averageCoverSizeBytes].
  ///
  /// The disk sweep is best-effort: if path_provider is unavailable (tests,
  /// or a platform quirk on first launch), we fall back to the file-count
  /// cap applied by [_build]. The sweep will re-run on the next configure
  /// call, which happens on every app startup.
  static Future<void> configure({required int capMb}) async {
    _capMb = capMb;
    _instance = _build(capMb);
    try {
      await enforceCapFromDisk();
    } catch (_) {
      // Platform channel unavailable or FS transient error -- ignore.
    }
  }

  static CacheManager _build(int capMb) => CacheManager(
        Config(
          key,
          stalePeriod: stalePeriod,
          maxNrOfCacheObjects: _fileCountCap(capMb),
          repo: JsonCacheInfoRepository(databaseName: key),
        ),
      );

  /// Absolute path of the on-disk cache directory. Mirrors the layout
  /// flutter_cache_manager's default [IOFileSystem] resolves from the cache
  /// key under the platform temporary directory.
  static Future<Directory> get cacheDirectory async {
    final temp = await getTemporaryDirectory();
    return Directory('${temp.path}/$key');
  }

  /// Sum of all file sizes in [cacheDirectory], in bytes. Used by the
  /// Settings screen to display "X MB used of Y MB" without relying on the
  /// JSON metadata (which can drift from the real disk state after a crash
  /// or a startup sweep).
  static Future<int> diskSizeBytes() async {
    final dir = await cacheDirectory;
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {
          // File disappeared between list and length -- ignore.
        }
      }
    }
    return total;
  }

  /// Safety net against the file-count cap under-estimating real disk usage
  /// (e.g. a peer serving 80 KB covers while [averageCoverSizeBytes] assumes
  /// 40 KB). Called from [configure]; also callable standalone at app
  /// resume if needed later.
  ///
  /// Deletes the oldest files (by mtime) until the directory is back under
  /// the cap. The JSON metadata is not touched -- the next fetch for an
  /// orphaned URL simply refetches, which is the correct behavior.
  static Future<void> enforceCapFromDisk() async {
    final dir = await cacheDirectory;
    if (!await dir.exists()) return;
    final capBytes = _capMb * 1024 * 1024;
    var size = await diskSizeBytes();
    if (size <= capBytes * diskOvershootTolerance) return;

    final files = <File>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) files.add(e);
    }
    files.sort(
      (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
    );

    for (final f in files) {
      if (size <= capBytes) break;
      try {
        final length = await f.length();
        await f.delete();
        size -= length;
      } catch (_) {
        // Ignore transient FS errors; the next sweep will pick them up.
      }
    }
  }

  /// Wipe the peer cover cache: every file on disk plus the metadata
  /// repository. Does NOT touch [BookCoverCacheManager]'s directory or DB.
  ///
  /// Two-step delete: [instance.emptyCache] only removes files that are
  /// tracked in the JSON index, so orphans left behind by partial
  /// downloads or an older cache format would otherwise keep accruing
  /// disk usage that the user cannot reclaim via Settings. Wiping the
  /// directory afterwards catches those, then [_build] re-creates a fresh
  /// manager so subsequent fetches land in a clean state.
  static Future<void> clearAll() async {
    try {
      await instance.emptyCache();
    } catch (_) {
      // Swallow: an empty or half-open store throws here on some platforms.
    }
    try {
      final dir = await cacheDirectory;
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Directory may already be gone, or locked -- next sweep will pick
      // up remaining files.
    }
    // Rebuild so the manager re-opens its store and recreates the
    // directory lazily on the next fetch.
    _instance = _build(_capMb);
    _evictedThisSession.clear();
  }

  static Future<void> _defaultRemoveFile(String url) async {
    try {
      await instance.removeFile(url);
    } catch (_) {
      // removeFile throws if the URL was never cached: safe to ignore.
    }
  }

  /// Mirrors [BookCoverCacheManager.evictOnce]: bounded one-shot eviction
  /// so scrolling through a peer list with many broken covers doesn't
  /// trigger a removeFile storm.
  static void evictOnce(String url) {
    if (!_evictedThisSession.add(url)) return;
    final result = removeFileImpl(url);
    if (result is Future) {
      unawaited(result);
    }
  }

  @visibleForTesting
  static bool hasBeenEvictedThisSession(String url) =>
      _evictedThisSession.contains(url);

  @visibleForTesting
  static void resetForTest() {
    _instance = null;
    _capMb = defaultCapMb;
    _evictedThisSession.clear();
  }

  @visibleForTesting
  static int fileCountCapForTest(int capMb) => _fileCountCap(capMb);
}
