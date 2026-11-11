import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/cover_camera_helper.dart';
import 'ffi_service.dart';

/// A cover fetched from a web page and saved into covers/ under a temp name,
/// for the user to preview before it replaces anything.
@immutable
class WebCoverPick {
  /// The temp file, `temp_<uuid>.jpg`.
  final String path;

  /// The image's web address, to record as the cover's origin.
  final String imageUrl;

  /// Every usable image of the page, best first, [imageUrl] included, for the
  /// user to step through. Empty for a pick made by stepping.
  final List<String> candidates;

  const WebCoverPick({
    required this.path,
    required this.imageUrl,
    this.candidates = const [],
  });
}

/// Why no cover could be taken from the page.
class WebCoverException implements Exception {
  /// Error codes the Rust side returns, plus `too_large`, `unsupported_image`
  /// and `unreadable_image` from the cover pipeline. An unknown code is
  /// reported as `network`.
  static const knownCodes = {
    'invalid_url',
    'blocked_address',
    'network',
    'too_many_redirects',
    'http_status',
    'too_large',
    'no_image_found',
    'unsupported_image',
    'unreadable_image',
  };

  final String code;

  WebCoverException(String code)
    : code = knownCodes.contains(code) ? code : 'network';

  /// The i18n key of the message shown to the user.
  String get translationKey => 'web_cover_error_$code';

  @override
  String toString() => 'WebCoverException($code)';
}

typedef FetchedWebCover = ({
  Uint8List bytes,
  String imageUrl,
  List<String> candidates,
});
typedef WebCoverFetcher =
    Future<FetchedWebCover> Function(String url, {String? isbn});
typedef WebCoverImageFetcher = Future<FetchedWebCover> Function(String url);
typedef WebCoverSaver = Future<String> Function(Uint8List bytes);
typedef WebCoverDiscarder = Future<void> Function(String path);
typedef WebCoverRenamer =
    Future<String?> Function(String tempPath, String bookId);
typedef WebCoverOriginRecorder =
    Future<void> Function(String bookId, String imageUrl);

/// Writes a book's `cover_url` (null clears it).
typedef CoverUrlUpdater = Future<void> Function(String? coverUrl);

/// Takes a book cover from a web page the user points at: the Rust side finds
/// and downloads the image (public https only), then the bytes go through the
/// same pipeline as a cover photo, so the result is an ordinary local cover.
class WebCoverService {
  final WebCoverFetcher _fetch;
  final WebCoverImageFetcher _fetchImage;
  final WebCoverSaver _save;
  final WebCoverDiscarder _discard;
  final WebCoverRenamer _rename;
  final WebCoverOriginRecorder _recordOrigin;

  WebCoverService({
    WebCoverFetcher? fetch,
    WebCoverImageFetcher? fetchImage,
    WebCoverSaver? save,
    WebCoverDiscarder? discard,
    WebCoverRenamer? rename,
    WebCoverOriginRecorder? recordOrigin,
  }) : _fetch = fetch ?? _fetchViaFfi,
       _fetchImage = fetchImage ?? _fetchImageViaFfi,
       _save = save ?? _saveCapped,
       _discard = discard ?? CoverCameraHelper.cleanupTempCover,
       _rename = rename ?? CoverCameraHelper.renameTempCover,
       _recordOrigin = recordOrigin ?? _recordOriginViaFfi;

  static Future<void> _recordOriginViaFfi(String bookId, String imageUrl) =>
      FfiService().recordWebCoverOrigin(bookId, imageUrl);

  static Future<String> _saveCapped(Uint8List bytes) =>
      CoverCameraHelper.saveBytesToCovers(
        bytes,
        maxPixels: CoverCameraHelper.webMaxSourcePixels,
      );

  static Future<FetchedWebCover> _fetchViaFfi(
    String url, {
    String? isbn,
  }) async {
    final cover = await FfiService().fetchCoverFromWebPage(url, isbn: isbn);
    return (
      bytes: cover.bytes,
      imageUrl: cover.imageUrl,
      candidates: cover.candidates,
    );
  }

  static Future<FetchedWebCover> _fetchImageViaFfi(String url) async {
    final cover = await FfiService().fetchWebCoverImage(url);
    return (
      bytes: cover.bytes,
      imageUrl: cover.imageUrl,
      candidates: cover.candidates,
    );
  }

  /// Fetch the cover shown at [url] and save it under a temp name. [isbn],
  /// when the book has one, ranks the images named after it first. Throws
  /// [WebCoverException], whatever went wrong.
  Future<WebCoverPick> fetchAndSave(String url, {String? isbn}) async {
    final trimmed = isbn?.trim();
    return _saveFetched(
      await _guard(
        () => _fetch(
          url.trim(),
          isbn: trimmed == null || trimmed.isEmpty ? null : trimmed,
        ),
      ),
    );
  }

  /// Fetch one of a page's [WebCoverPick.candidates], when the user steps to
  /// the next image, and save it under a temp name. Throws
  /// [WebCoverException].
  Future<WebCoverPick> fetchCandidateAndSave(String imageUrl) async =>
      _saveFetched(await _guard(() => _fetchImage(imageUrl)));

  static Future<FetchedWebCover> _guard(
    Future<FetchedWebCover> Function() fetch,
  ) async {
    try {
      return await fetch();
    } on String catch (code) {
      throw WebCoverException(code);
    } catch (e) {
      debugPrint('[WEB-COVER] fetch failed: $e');
      throw WebCoverException('network');
    }
  }

  Future<WebCoverPick> _saveFetched(FetchedWebCover fetched) async {
    try {
      final path = await _save(fetched.bytes);
      return WebCoverPick(
        path: path,
        imageUrl: fetched.imageUrl,
        candidates: fetched.candidates,
      );
    } on CoverImageTooLargeException {
      throw WebCoverException('too_large');
    } on UnsupportedCoverImageException {
      throw WebCoverException('unsupported_image');
    } catch (e) {
      // A corrupt image (FormatException, RangeError from the decoder) or a
      // full disk: the caller must always get an answer it can show.
      debugPrint('[WEB-COVER] save failed: $e');
      throw WebCoverException('unreadable_image');
    }
  }

  /// Delete a preview the user did not keep.
  Future<void> discard(WebCoverPick pick) => _discard(pick.path);

  /// Record where the cover now saved for [bookId] came from. Call it once
  /// the file sits under its final `<bookId>.jpg` name.
  Future<void> recordOrigin(String bookId, String imageUrl) =>
      _recordOrigin(bookId, imageUrl);

  /// Makes a kept preview the cover of the existing book [bookId] and returns
  /// the cover's final path.
  ///
  /// The book's cover file is replaced only once [updateCoverUrl] has stored
  /// the final path, so a failed database write leaves the previous cover
  /// intact. If the file cannot be renamed afterwards, [previousCoverUrl] is
  /// stored back. On any failure the preview is deleted and the error
  /// rethrown; on success the cover's web origin is recorded.
  Future<String> adoptForBook(
    WebCoverPick pick, {
    required String bookId,
    required String? previousCoverUrl,
    required CoverUrlUpdater updateCoverUrl,
  }) async {
    final finalPath = CoverCameraHelper.coverPathBeside(pick.path, bookId);
    var databaseUpdated = false;
    try {
      await updateCoverUrl(finalPath);
      databaseUpdated = true;
      if (await _rename(pick.path, bookId) == null) {
        throw FileSystemException('Preview file is gone', pick.path);
      }
    } catch (_) {
      if (databaseUpdated) {
        try {
          await updateCoverUrl(previousCoverUrl);
        } catch (e) {
          debugPrint('[WEB-COVER] could not restore the previous cover: $e');
        }
      }
      await _discard(pick.path);
      rethrow;
    }
    await _recordOrigin(bookId, pick.imageUrl);
    return finalPath;
  }
}
