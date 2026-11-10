import 'package:flutter/foundation.dart';

import '../utils/cover_camera_helper.dart';
import 'ffi_service.dart';

/// A cover fetched from a web page and saved into covers/.
@immutable
class WebCoverPick {
  /// Local file, `<bookId>.jpg` or a temp name while the book has no id.
  final String path;

  /// The image's web address, to record as the cover's origin.
  final String imageUrl;

  const WebCoverPick({required this.path, required this.imageUrl});
}

/// Why no cover could be taken from the page.
class WebCoverException implements Exception {
  /// Error codes the Rust side returns, plus `unreadable_image` when the
  /// bytes passed its format check but the cover pipeline could not decode
  /// them. Anything else is reported as `network`.
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
typedef WebCoverSaver =
    Future<String> Function(Uint8List bytes, {String? bookId});

/// Takes a book cover from a web page the user points at: the Rust side finds
/// and downloads the image (public https only), then the bytes go through the
/// same pipeline as a cover photo, so the result is an ordinary local cover.
class WebCoverService {
  final WebCoverFetcher _fetch;
  final WebCoverSaver _save;

  WebCoverService({WebCoverFetcher? fetch, WebCoverSaver? save})
    : _fetch = fetch ?? _fetchViaFfi,
      _save = save ?? CoverCameraHelper.saveBytesToCovers;

  static Future<({Uint8List bytes, String imageUrl})> _fetchViaFfi(
    String url,
  ) async {
    final cover = await FfiService().fetchCoverFromWebPage(url);
    return (bytes: cover.bytes, imageUrl: cover.imageUrl);
  }

  /// Fetch the cover shown at [url] and save it, as `<bookId>.jpg` when
  /// [bookId] is known. Throws [WebCoverException].
  Future<WebCoverPick> fetchAndSave(String url, {String? bookId}) async {
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
      final path = await _save(fetched.bytes, bookId: bookId);
      return WebCoverPick(path: path, imageUrl: fetched.imageUrl);
    } on CoverImageTooLargeException {
      throw WebCoverException('too_large');
    } on FormatException {
      throw WebCoverException('unreadable_image');
    }
  }

  /// Record where the cover now saved for [bookId] came from. Call it once
  /// the file sits under its final `<bookId>.jpg` name.
  Future<void> recordOrigin(String bookId, String imageUrl) =>
      FfiService().recordWebCoverOrigin(bookId, imageUrl);
}
