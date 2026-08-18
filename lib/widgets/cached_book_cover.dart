import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import 'peer_book_cover_cache_manager.dart';

/// Custom Cache Manager for Book Covers.
///
/// Covers can change (user re-uploads a custom cover, a peer edits a book,
/// the hub regenerates thumbnails). The previous 30-day stale window meant
/// changes only propagated after a month. A 7-day window is still long
/// enough to be effectively free on disk and bandwidth while keeping stale
/// covers bounded to a reasonable delay.
class BookCoverCacheManager {
  static const key = 'bookCoversCache';

  /// How long a successfully-fetched cover stays in cache before the next
  /// fetch goes back to the network.
  @visibleForTesting
  static const Duration stalePeriod = Duration(days: 7);

  /// Upper bound on the number of cover files on disk. 2000 x ~29 KB
  /// measured average ≈ 57 MB, well under the 100 MB the peer cover cache
  /// is granted by default. Kept comfortably above the library size: past
  /// the cap, LRU eviction on `touched` thrashes — scrolling the list
  /// evicts its top, scrolling back re-downloads it.
  @visibleForTesting
  static const int maxNrOfCacheObjects = 2000;

  /// Hosts that serve covers at identifier- or content-addressed URLs: the
  /// URL embeds an ISBN, a volume id or a content hash, so the bytes behind a
  /// given URL do not change. For those, `Cache-Control` is a CDN policy, not
  /// a statement about the image: `covers.openlibrary.org` sends
  /// `max-age=3h` with no ETag, which forces a full re-download (no
  /// conditional revalidation is possible without an ETag) several times a
  /// day, from a backend that answers in 6-11s because it unzips each cover
  /// out of an archive on the fly.
  ///
  /// Hosts whose covers CAN change behind a stable URL are deliberately
  /// absent, so they keep honouring their own header and a re-uploaded cover
  /// still propagates: the hub's `/api/directory/<node>/covers/<book>` and
  /// this device's own `/api/books/<id>/cover`.
  @visibleForTesting
  static const Set<String> immutableCoverHosts = {
    'covers.openlibrary.org',
    'inventaire.io',
    'books.google.com',
    'catalogue.bnf.fr',
  };

  /// Validity floor applied to [immutableCoverHosts] responses. Matches what
  /// inventaire.io already sends of its own accord (`max-age` of one year),
  /// which is the reference point for how long such a URL stays valid.
  @visibleForTesting
  static const Duration immutableCoverValidity = Duration(days: 365);

  /// True when [url] points at a host from [immutableCoverHosts].
  @visibleForTesting
  static bool hasImmutableCoverUrl(String url) {
    final host = Uri.tryParse(url)?.host;
    return host != null && immutableCoverHosts.contains(host);
  }

  /// Freshness deadline to store for [url], given the [serverValidTill] the
  /// response headers imply.
  ///
  /// Only ever extends: a host that already promises more than
  /// [immutableCoverValidity] keeps its own longer deadline, and a host
  /// outside [immutableCoverHosts] is returned untouched.
  @visibleForTesting
  static DateTime effectiveValidTill(
    String url,
    DateTime serverValidTill, {
    DateTime? now,
  }) {
    if (!hasImmutableCoverUrl(url)) return serverValidTill;
    final floor = (now ?? DateTime.now()).add(immutableCoverValidity);
    return serverValidTill.isAfter(floor) ? serverValidTill : floor;
  }

  /// Held so [sweepOrphanFiles] can ask the very store the manager uses
  /// which files are still tracked.
  static final JsonCacheInfoRepository _repo = JsonCacheInfoRepository(
    databaseName: key,
  );

  static final CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: stalePeriod,
      maxNrOfCacheObjects: maxNrOfCacheObjects,
      repo: _repo,
      fileService: CoverFileService(),
    ),
  );

  /// URLs that failed to fetch during this app session. Prevents evicting
  /// and re-fetching the same dead URL on every rebuild (e.g. when the user
  /// scrolls through a list with many missing covers).
  static final Set<String> _evictedThisSession = {};

  /// Strategy used by [evictOnce] to drop a cached file. Production code
  /// hits disk via `instance.removeFile`; tests swap this out to avoid
  /// touching the SQLite-backed cache store which is unavailable in a pure
  /// `test()` environment (no platform channels).
  @visibleForTesting
  static FutureOr<void> Function(String url) removeFileImpl =
      _defaultRemoveFile;

  static Future<void> _defaultRemoveFile(String url) async {
    try {
      await instance.removeFile(url);
    } catch (_) {
      // removeFile throws if the URL was never cached: safe to ignore.
    }
  }

  /// Drops the cached entry for [url] so the next render re-attempts the
  /// fetch. Idempotent per session: a URL that has already been evicted
  /// will not trigger another removeFile call, avoiding request storms on
  /// persistently dead URLs.
  ///
  /// Intended to be called from `errorListener` on a network image failure.
  /// The underlying I/O is fire-and-forget so the errorListener callback
  /// stays non-blocking during rendering.
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
  static void resetEvictedForTest() => _evictedThisSession.clear();

  /// How recent a file must be to be spared by [sweepOrphanFiles] even when
  /// it is absent from the index. A download writes its bytes before the
  /// index row is committed, so a file being fetched right now legitimately
  /// looks orphaned.
  @visibleForTesting
  static const Duration orphanGracePeriod = Duration(hours: 1);

  /// Directory resolution, overridable so tests can sweep a temp directory.
  @visibleForTesting
  static Future<Directory> Function() cacheDirectoryImpl =
      _defaultCacheDirectory;

  /// Index lookup, overridable so tests can state which files are tracked
  /// without opening the real metadata store.
  @visibleForTesting
  static Future<Set<String>> Function() trackedFileNamesImpl =
      _defaultTrackedFileNames;

  /// Mirrors the layout [IOFileSystem] derives from the cache key: the key
  /// is a subdirectory of the platform cache directory.
  static Future<Directory> _defaultCacheDirectory() async {
    final temp = await getTemporaryDirectory();
    return Directory(p.join(temp.path, key));
  }

  static Future<Set<String>> _defaultTrackedFileNames() async {
    await _repo.open();
    final objects = await _repo.getAllObjects();
    return objects.map((o) => p.basename(o.relativePath)).toSet();
  }

  /// Deletes cover files that the metadata index no longer references, and
  /// returns the number of bytes reclaimed.
  ///
  /// Needed because flutter_cache_manager leaks the bytes of every cover it
  /// evicts: reads resolve a file through `fileSystem.createFile(relativePath)`,
  /// which joins the cache directory, but the delete in `CacheStore` builds
  /// `io.File(cacheObject.relativePath)` from the bare filename, which
  /// resolves against the process working directory instead. The file is
  /// never found, so the index row is dropped while the bytes stay on disk
  /// forever. Every stale-period cleanup and every capacity eviction leaks
  /// its whole batch, so the directory grows without bound.
  ///
  /// Best-effort by construction: a directory that cannot be listed, or a
  /// file that vanishes mid-sweep, leaves the rest of the sweep running and
  /// never propagates an error to the caller.
  static Future<int> sweepOrphanFiles() async {
    try {
      final dir = await cacheDirectoryImpl();
      if (!await dir.exists()) return 0;

      final tracked = await trackedFileNamesImpl();
      // An empty index cannot be told apart from an index that failed to
      // load, and sweeping against it would wipe an entirely healthy cache.
      // Refuse: the next launch sweeps with a populated index.
      if (tracked.isEmpty) return 0;

      final cutoff = DateTime.now().subtract(orphanGracePeriod);
      var reclaimed = 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        if (tracked.contains(p.basename(entity.path))) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isAfter(cutoff)) continue;
          final size = stat.size;
          await entity.delete();
          reclaimed += size;
        } catch (_) {
          // Raced with a download or a platform eviction; the next sweep
          // picks it up.
        }
      }
      return reclaimed;
    } catch (_) {
      // Cache maintenance must never break startup.
      return 0;
    }
  }

  @visibleForTesting
  static void resetSweepHooksForTest() {
    cacheDirectoryImpl = _defaultCacheDirectory;
    trackedFileNamesImpl = _defaultTrackedFileNames;
  }
}

/// Applies [BookCoverCacheManager.effectiveValidTill] to every response, so
/// a third-party CDN's short `max-age` cannot force covers whose bytes never
/// change to be re-downloaded over and over.
///
/// The floor must also cover 304 revalidations: the cache manager's
/// `_setDataFromHeaders` takes `response.validTill` for a Not Modified
/// response too, so filtering on status 200 here would silently drop the
/// floor exactly when the server confirmed the bytes are unchanged.
///
/// Public and client-injectable only so tests can drive it with a mock
/// `http.Client`; production constructs it without arguments.
@visibleForTesting
class CoverFileService extends HttpFileService {
  CoverFileService({super.httpClient});

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final response = await super.get(url, headers: headers);
    if (!BookCoverCacheManager.hasImmutableCoverUrl(url)) return response;
    return _FlooredValidityResponse(response, url);
  }
}

/// Decorates a [FileServiceResponse] to widen only its [validTill].
class _FlooredValidityResponse implements FileServiceResponse {
  _FlooredValidityResponse(this._inner, this._url);

  final FileServiceResponse _inner;
  final String _url;

  @override
  DateTime get validTill =>
      BookCoverCacheManager.effectiveValidTill(_url, _inner.validTill);

  @override
  Stream<List<int>> get content => _inner.content;

  @override
  int? get contentLength => _inner.contentLength;

  @override
  int get statusCode => _inner.statusCode;

  @override
  String? get eTag => _inner.eTag;

  @override
  String get fileExtension => _inner.fileExtension;
}

/// A widget that displays a book cover with automatic caching.
///
/// Uses cached_network_image for:
/// - Memory caching (fast re-display)
/// - Disk caching (persistent across sessions)
/// - Placeholder during loading
/// - Error handling with fallback
class CachedBookCover extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;
  final String? semanticLabel;

  /// Called when the user taps the fallback/error placeholder.
  /// Use this to trigger a cover reload (e.g. evict cache + setState).
  final VoidCallback? onTapPlaceholder;

  /// Routes the cover through [PeerBookCoverCacheManager] instead of the
  /// default local [BookCoverCacheManager]. Callers set this explicitly --
  /// URL-based detection is too fragile (peers can live behind any hub).
  /// Keeping the two caches isolated guarantees an eviction triggered by a
  /// peer view never drops a locally-owned cover.
  final bool isPeerCover;

  const CachedBookCover({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
    this.semanticLabel,
    this.onTapPlaceholder,
    this.isPeerCover = false,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _wrapSemantics(_buildTappableFallback());
    }

    // Local file path detection (from cover upload feature)
    // Network URLs start with 'http', relative API paths with '/api'
    // Everything else (including absolute paths like /Users/.../covers/42.jpg) is a local file
    final isNetworkUrl = imageUrl!.startsWith('http');
    final isRelativeApiPath = imageUrl!.startsWith('/api');

    if (!isNetworkUrl && !isRelativeApiPath) {
      // imageUrl is already re-based onto the current covers directory by the
      // model getter (Book.coverUrl / Loan.resolvedCoverUrl via
      // LocalCoverResolver) when it came from a stored book row.
      Widget localImage = Image.file(
        File(imageUrl!),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => errorWidget ?? _buildTappableFallback(),
      );
      if (borderRadius != null) {
        localImage = ClipRRect(borderRadius: borderRadius!, child: localImage);
      }
      return _wrapSemantics(localImage);
    }

    String resolvedUrl = imageUrl!;
    if (isRelativeApiPath) {
      final apiService = Provider.of<ApiService>(context, listen: false);
      String baseUrl = apiService.baseUrl;
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }
      resolvedUrl = '$baseUrl$resolvedUrl';
    }

    // Decode at display resolution to keep RAM bounded. A 800x1200 cover
    // decoded full-res costs ~3.8 MB; at 150 logical px × 3x DPR the same
    // cover costs ~250 KB. When `width` isn't provided (parent-filling case,
    // e.g. cover grid), cap at 300 logical px which covers every call site.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = ((width ?? 300) * dpr).round();

    final cacheManager = isPeerCover
        ? PeerBookCoverCacheManager.instance
        : BookCoverCacheManager.instance;

    Widget image = CachedNetworkImage(
      imageUrl: resolvedUrl,
      cacheManager: cacheManager,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: decodeWidth,
      placeholder: (context, url) => placeholder ?? _buildPlaceholder(),
      errorListener: (error) {
        // Drop the stale cache entry for this URL so a retry (user pulls to
        // refresh, navigates away and back, etc.) actually hits the network.
        // Bounded to once per URL per session to avoid hammering dead URLs.
        // Route to the matching session set so a broken peer URL never
        // shadows a local retry (and vice versa).
        if (isPeerCover) {
          PeerBookCoverCacheManager.evictOnce(resolvedUrl);
        } else {
          BookCoverCacheManager.evictOnce(resolvedUrl);
        }
      },
      errorWidget: (context, url, error) {
        return errorWidget ?? _buildTappableFallback();
      },
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: const Duration(milliseconds: 200),
    );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }

    return _wrapSemantics(image);
  }

  Widget _wrapSemantics(Widget child) {
    if (semanticLabel != null) {
      return Semantics(image: true, label: semanticLabel, child: child);
    }
    return ExcludeSemantics(child: child);
  }

  Widget _buildPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.grey[400],
          ),
        ),
      ),
    );
  }

  Widget _buildTappableFallback() {
    final fallback = _buildFallback();
    if (onTapPlaceholder == null) return fallback;
    return GestureDetector(onTap: onTapPlaceholder, child: fallback);
  }

  Widget _buildFallback() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: borderRadius,
      ),
      child: Icon(
        Icons.book,
        size: (width != null && height != null)
            ? (width! < height! ? width! * 0.4 : height! * 0.4)
            : 32,
        color: Colors.grey[500],
      ),
    );
  }
}

/// Compact version for list items
class CompactBookCover extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final String? semanticLabel;
  final bool isPeerCover;

  const CompactBookCover({
    super.key,
    required this.imageUrl,
    this.size = 50,
    this.semanticLabel,
    this.isPeerCover = false,
  });

  @override
  Widget build(BuildContext context) {
    return CachedBookCover(
      imageUrl: imageUrl,
      width: size,
      height: size * 1.5,
      borderRadius: BorderRadius.circular(4),
      semanticLabel: semanticLabel,
      isPeerCover: isPeerCover,
    );
  }
}
