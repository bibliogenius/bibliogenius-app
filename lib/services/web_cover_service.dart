import 'dart:async';
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

  /// The publisher's site the cover was found on, as the engine's table names
  /// it (`gallimard.fr`), when it came from [WebCoverService.findOnPublisherSiteAndSave].
  final String? site;

  const WebCoverPick({
    required this.path,
    required this.imageUrl,
    this.candidates = const [],
    this.site,
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
    'blocked_by_site',
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

/// Why no cover came from the book's publisher's site.
class PublisherCoverException implements Exception {
  /// Error codes the Rust side returns. An unknown code is reported as
  /// `network`, which only invites the user to try again later.
  static const knownCodes = {
    'invalid_isbn',
    'no_site',
    'not_found',
    'blocked_by_site',
    'network',
    'image_forbidden',
    'no_image_found',
  };

  final String code;

  PublisherCoverException(String code)
    : code = knownCodes.contains(code) ? code : 'network';

  /// The i18n key of the message shown to the user.
  String get translationKey => 'publisher_cover_error_$code';

  @override
  String toString() => 'PublisherCoverException($code)';
}

/// What the engine needs to find a book's page on its publisher's site.
typedef PublisherBook = ({
  String isbn,
  String title,
  String authors,
  String? publisher,
});

typedef FoundPublisherCover = ({
  Uint8List bytes,
  String imageUrl,
  List<String> candidates,
  String site,
  String pageUrl,
});
typedef PublisherCoverFinder =
    Future<FoundPublisherCover> Function(PublisherBook book);

/// Runs one search per key at a time: an ask for a key whose search is still
/// running gets that search's result instead of starting another.
class SingleFlight<T> {
  final _running = <String, Future<T>>{};

  Future<T> run(String key, Future<T> Function() start) {
    final running = _running[key];
    if (running != null) return running;
    final future = start();
    _running[key] = future;
    // Forgotten once done, failed included: a later ask searches again.
    // ignore() keeps this bookkeeping branch from reporting the error, which
    // reaches every caller through the returned future.
    future.whenComplete(() => _running.remove(key)).ignore();
    return future;
  }
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
  final PublisherCoverFinder _findOnPublisherSite;
  final WebCoverImageFetcher _fetchPublisherImage;

  WebCoverService({
    WebCoverFetcher? fetch,
    WebCoverImageFetcher? fetchImage,
    WebCoverSaver? save,
    WebCoverDiscarder? discard,
    WebCoverRenamer? rename,
    WebCoverOriginRecorder? recordOrigin,
    PublisherCoverFinder? findOnPublisherSite,
    WebCoverImageFetcher? fetchPublisherImage,
  }) : _fetch = fetch ?? _fetchViaFfi,
       _fetchImage = fetchImage ?? _fetchImageViaFfi,
       _save = save ?? _saveCapped,
       _discard = discard ?? CoverCameraHelper.cleanupTempCover,
       _rename = rename ?? CoverCameraHelper.renameTempCover,
       _recordOrigin = recordOrigin ?? _recordOriginViaFfi,
       _findOnPublisherSite = findOnPublisherSite ?? _findViaFfi,
       _fetchPublisherImage = fetchPublisherImage ?? _fetchPublisherImageViaFfi;

  static Future<FetchedWebCover> _fetchPublisherImageViaFfi(String url) async {
    final cover = await FfiService().fetchPublisherCoverImage(url);
    return (
      bytes: cover.bytes,
      imageUrl: cover.imageUrl,
      candidates: cover.candidates,
    );
  }

  /// One engine search per book at a time: the dialog closed and opened again
  /// on the same book joins the search still running instead of sending the
  /// same requests to the publisher's site a second time.
  static final _publisherSearches = SingleFlight<FoundPublisherCover>();

  static Future<FoundPublisherCover> _findViaFfi(PublisherBook book) =>
      _publisherSearches.run(
        book.isbn.replaceAll(RegExp('[^0-9Xx]'), '').toUpperCase(),
        () async {
          final cover = await FfiService().findCoverOnPublisherSite(
            isbn: book.isbn,
            title: book.title,
            authors: book.authors,
            publisher: book.publisher,
          );
          return (
            bytes: cover.bytes,
            imageUrl: cover.imageUrl,
            candidates: cover.candidates,
            site: cover.site,
            pageUrl: cover.pageUrl,
          );
        },
      );

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

  /// Look for [book]'s cover on its publisher's site (the engine finds the
  /// book's page from its ISBN, and takes it only if the page states it), and
  /// save it under a temp name. Throws [PublisherCoverException], whatever
  /// went wrong: an image the app cannot use counts as no usable cover.
  Future<WebCoverPick> findOnPublisherSiteAndSave(PublisherBook book) async {
    final publisher = book.publisher?.trim();
    final FoundPublisherCover found;
    try {
      found = await _findOnPublisherSite((
        isbn: book.isbn.trim(),
        title: book.title.trim(),
        authors: book.authors.trim(),
        publisher: publisher == null || publisher.isEmpty ? null : publisher,
      ));
    } on String catch (code) {
      throw PublisherCoverException(code);
    } catch (e) {
      debugPrint('[WEB-COVER] publisher site search failed: $e');
      throw PublisherCoverException('network');
    }
    try {
      final pick = await _saveFetched((
        bytes: found.bytes,
        imageUrl: found.imageUrl,
        candidates: found.candidates,
      ));
      return WebCoverPick(
        path: pick.path,
        imageUrl: pick.imageUrl,
        candidates: pick.candidates,
        site: found.site,
      );
    } on WebCoverException {
      throw PublisherCoverException('no_image_found');
    }
  }

  /// Fetch one of a page's [WebCoverPick.candidates], when the user steps to
  /// the next image, and save it under a temp name. Candidates of a cover
  /// found on a publisher's site ([fromPublisherSite]) go through the
  /// engine's lookup rules: robots.txt, the pause between two requests to a
  /// host, the site's Crawl-delay. Throws [WebCoverException].
  Future<WebCoverPick> fetchCandidateAndSave(
    String imageUrl, {
    bool fromPublisherSite = false,
  }) async => _saveFetched(
    await _guard(
      () => fromPublisherSite
          ? _fetchPublisherImage(imageUrl)
          : _fetchImage(imageUrl),
    ),
  );

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
  /// the file sits under its final `<bookId>.jpg` name. Best effort: the
  /// cover is in place whatever happens here, so a failure is logged, never
  /// thrown. Losing the origin only means Open Library will later not be
  /// offered that address.
  Future<void> recordOrigin(String bookId, String imageUrl) async {
    try {
      await _recordOrigin(bookId, imageUrl);
    } catch (e) {
      debugPrint('[WEB-COVER] could not record the origin of $bookId: $e');
    }
  }

  /// Makes a kept preview the cover of the existing book [bookId] and returns
  /// the cover's final path.
  ///
  /// The book's cover file is replaced only once [updateCoverUrl] has stored
  /// the final path, so a failed database write leaves the previous cover
  /// intact. If the file cannot be renamed afterwards, [previousCoverUrl] is
  /// stored back. On any failure the preview is deleted and the error
  /// rethrown; on success the cover's web origin is recorded, best effort.
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
    await recordOrigin(bookId, pick.imageUrl);
    return finalPath;
  }
}
