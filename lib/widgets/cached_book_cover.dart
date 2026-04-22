import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
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

  /// Upper bound on the number of cover files on disk. 500 x ~40 KB
  /// ≈ 20 MB; negligible on any device.
  @visibleForTesting
  static const int maxNrOfCacheObjects = 500;

  static final CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: stalePeriod,
      maxNrOfCacheObjects: maxNrOfCacheObjects,
      repo: JsonCacheInfoRepository(databaseName: key),
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
    return GestureDetector(
      onTap: onTapPlaceholder,
      child: fallback,
    );
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
