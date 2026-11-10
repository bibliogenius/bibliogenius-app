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

  const WebCoverPick({required this.path, required this.imageUrl});
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

typedef WebCoverFetcher =
    Future<({Uint8List bytes, String imageUrl})> Function(String url);
typedef WebCoverSaver = Future<String> Function(Uint8List bytes);
typedef WebCoverDiscarder = Future<void> Function(String path);

/// Takes a book cover from a web page the user points at: the Rust side finds
/// and downloads the image (public https only), then the bytes go through the
/// same pipeline as a cover photo, so the result is an ordinary local cover.
class WebCoverService {
  final WebCoverFetcher _fetch;
  final WebCoverSaver _save;
  final WebCoverDiscarder _discard;

  WebCoverService({
    WebCoverFetcher? fetch,
    WebCoverSaver? save,
    WebCoverDiscarder? discard,
  }) : _fetch = fetch ?? _fetchViaFfi,
       _save = save ?? _saveCapped,
       _discard = discard ?? CoverCameraHelper.cleanupTempCover;

  static Future<String> _saveCapped(Uint8List bytes) =>
      CoverCameraHelper.saveBytesToCovers(
        bytes,
        maxPixels: CoverCameraHelper.webMaxSourcePixels,
      );

  static Future<({Uint8List bytes, String imageUrl})> _fetchViaFfi(
    String url,
  ) async {
    final cover = await FfiService().fetchCoverFromWebPage(url);
    return (bytes: cover.bytes, imageUrl: cover.imageUrl);
  }

  /// Fetch the cover shown at [url] and save it under a temp name. Throws
  /// [WebCoverException], whatever went wrong.
  Future<WebCoverPick> fetchAndSave(String url) async {
    final ({Uint8List bytes, String imageUrl}) fetched;
    try {
      fetched = await _fetch(url.trim());
    } on String catch (code) {
      throw WebCoverException(code);
    } catch (e) {
      debugPrint('[WEB-COVER] fetch failed: $e');
      throw WebCoverException('network');
    }
    try {
      final path = await _save(fetched.bytes);
      return WebCoverPick(path: path, imageUrl: fetched.imageUrl);
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
      FfiService().recordWebCoverOrigin(bookId, imageUrl);
}
