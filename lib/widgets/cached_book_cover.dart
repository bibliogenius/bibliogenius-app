import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';

/// Custom Cache Manager for Book Covers
/// Retains images for 30 days and handles up to 500 images.
class BookCoverCacheManager {
  static const key = 'bookCoversCache';
  static final CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 500,
      repo: JsonCacheInfoRepository(databaseName: key),
    ),
  );
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
        errorBuilder: (_, _, _) => _buildFallback(),
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

    Widget image = CachedNetworkImage(
      imageUrl: resolvedUrl,
      cacheManager: BookCoverCacheManager.instance,
      width: width,
      height: height,
      fit: fit,
      placeholder: (context, url) => placeholder ?? _buildPlaceholder(),
      errorWidget: (context, url, error) {
        // Silent fallback - errors are expected for invalid/unavailable cover URLs
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

  const CompactBookCover({
    super.key,
    required this.imageUrl,
    this.size = 50,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return CachedBookCover(
      imageUrl: imageUrl,
      width: size,
      height: size * 1.5,
      borderRadius: BorderRadius.circular(4),
      semanticLabel: semanticLabel,
    );
  }
}
