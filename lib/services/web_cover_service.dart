import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/cover_camera_helper.dart';
import '../utils/isbn_validator.dart';
import '../src/rust/api/frb.dart' as frb;
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

/// When the Web cover dialog looks for the cover on the book's publisher's
/// site. The search sends the publisher the book looked up: by default it
/// starts only when the user taps its button, and that tap is the consent.
enum PublisherCoverSearch {
  /// A button names the site; nothing is sent until it is tapped.
  onDemand('on_demand'),

  /// As the dialog opens, for a book without a cover; on demand otherwise.
  automatic('automatic'),

  /// No button, no search.
  never('never');

  const PublisherCoverSearch(this.prefValue);

  /// How the choice is stored, and the suffix of its i18n keys.
  final String prefValue;

  /// The stored choice; [onDemand] for none or an unknown one.
  static PublisherCoverSearch fromPref(String? value) => values.firstWhere(
    (mode) => mode.prefValue == value,
    orElse: () => onDemand,
  );
}

/// What the engine needs to find a book's page on its publisher's site.
typedef PublisherBook = ({
  String isbn,
  String title,
  String authors,
  String? publisher,
});

/// The book as a form shows it, for the publisher site search: the [authors]
/// added, and the name still in the author field ([pendingAuthor]).
PublisherBook publisherBookFromForm({
  required String isbn,
  required String title,
  required List<String> authors,
  required String pendingAuthor,
  required String publisher,
}) {
  final pending = pendingAuthor.trim();
  return (
    isbn: isbn,
    title: title,
    authors: [
      ...authors,
      if (pending.isNotEmpty && !authors.contains(pending)) pending,
    ].join(', '),
    publisher: publisher,
  );
}

typedef FoundPublisherCover = ({
  Uint8List bytes,
  String imageUrl,
  List<String> candidates,
  String site,
});

/// What a publisher site search is doing, for the dialog to say while the
/// user waits: a site asking 10 s between two pages makes a search last half
/// a minute, most of it waiting.
@immutable
class PublisherLookupStep {
  /// `rules`, `product_page`, `search`, `search_result`, `site_map`,
  /// `waiting` or `cover` (see the engine's `FrbPublisherLookupStep`).
  final String kind;

  /// The site, without `www.` (`gallimard.fr`).
  final String site;

  /// For `product_page` and `search_result`: try [attempt] of at most [of].
  final int attempt;
  final int of;

  /// For `waiting`: the seconds left before the next request, when the step
  /// was said ([saidAt]).
  final int seconds;
  final DateTime? saidAt;

  const PublisherLookupStep({
    required this.kind,
    required this.site,
    this.attempt = 0,
    this.of = 0,
    this.seconds = 0,
    this.saidAt,
  });

  /// The seconds of a wait left at [now]: a dialog that joins a search late
  /// hears its last step, said some time ago.
  int secondsLeft(DateTime now) {
    final said = saidAt;
    if (said == null) return seconds;
    final left = seconds - now.difference(said).inSeconds;
    return left < 0 ? 0 : left;
  }

  /// The i18n key that says this step.
  String get translationKey => 'publisher_cover_step_$kind';

  @override
  String toString() => 'PublisherLookupStep($kind, $site)';
}

/// The site a search for the book would look on first, from the engine's
/// table alone (no request), or null when it knows none.
typedef PublisherSiteNamer = Future<String?> Function(PublisherBook book);

typedef PublisherCoverFinder =
    Future<FoundPublisherCover> Function(
      PublisherBook book, {
      void Function(PublisherLookupStep step)? onStep,
    });

/// Runs one search per key at a time: an ask for a key whose search is still
/// running gets that search's result instead of starting another, and hears
/// its progress ([S]) from the step it has reached.
class SingleFlight<T, S> {
  final _running = <String, _Flight<T, S>>{};

  /// [start] runs the search, telling its progress to the function it gets.
  /// The future it gets completes once everyone who listened has stopped
  /// ([stopHearing]): the search may stop then, nobody waits for it.
  Future<T> run(
    String key,
    Future<T> Function(void Function(S progress) report, Future<void> abandoned)
    start, {
    void Function(S progress)? onProgress,
  }) {
    final running = _running[key];
    if (running != null) {
      running.listen(onProgress);
      return running.future;
    }
    final flight = _Flight<T, S>()..listen(onProgress);
    _running[key] = flight;
    flight.future = start(flight.report, flight._abandoned.future);
    // Forgotten once done, failed included: a later ask searches again.
    // ignore() keeps this bookkeeping branch from reporting the error, which
    // reaches every caller through the returned future.
    flight.future.whenComplete(() => _running.remove(key)).ignore();
    return flight.future;
  }

  /// [listener] hears no more progress: its dialog is gone, the search may
  /// go on for another.
  void stopHearing(void Function(S progress) listener) {
    for (final flight in _running.values) {
      if (flight._listeners.remove(listener) &&
          flight._listeners.isEmpty &&
          !flight._abandoned.isCompleted) {
        flight._abandoned.complete();
      }
    }
  }
}

class _Flight<T, S> {
  late final Future<T> future;
  final _listeners = <void Function(S)>[];
  final _abandoned = Completer<void>();
  S? _last;

  void listen(void Function(S)? listener) {
    if (listener == null) return;
    _listeners.add(listener);
    final last = _last;
    if (last != null) listener(last);
  }

  void report(S progress) {
    _last = progress;
    for (final listener in List.of(_listeners)) {
      listener(progress);
    }
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

/// Fetches one of a publisher cover's other images, telling the steps. Once
/// [abandoned] completes, the fetch stops and throws `network`.
typedef PublisherImageFetcher =
    Future<FetchedWebCover> Function(
      String url, {
      void Function(PublisherLookupStep step)? onStep,
      Future<void>? abandoned,
    });
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
  final PublisherImageFetcher _fetchPublisherImage;
  final PublisherSiteNamer _siteFor;

  WebCoverService({
    WebCoverFetcher? fetch,
    WebCoverImageFetcher? fetchImage,
    WebCoverSaver? save,
    WebCoverDiscarder? discard,
    WebCoverRenamer? rename,
    WebCoverOriginRecorder? recordOrigin,
    PublisherCoverFinder? findOnPublisherSite,
    PublisherImageFetcher? fetchPublisherImage,
    PublisherSiteNamer? siteFor,
  }) : _fetch = fetch ?? _fetchViaFfi,
       _fetchImage = fetchImage ?? _fetchImageViaFfi,
       _save = save ?? _saveCapped,
       _discard = discard ?? CoverCameraHelper.cleanupTempCover,
       _rename = rename ?? CoverCameraHelper.renameTempCover,
       _recordOrigin = recordOrigin ?? _recordOriginViaFfi,
       _findOnPublisherSite = findOnPublisherSite ?? _findViaFfi,
       _fetchPublisherImage = fetchPublisherImage ?? _fetchPublisherImageViaFfi,
       _siteFor = siteFor ?? _siteForViaFfi;

  static Future<String?> _siteForViaFfi(PublisherBook book) =>
      FfiService().publisherSiteFor(isbn: book.isbn, publisher: book.publisher);

  static Future<FetchedWebCover> _fetchPublisherImageViaFfi(
    String url, {
    void Function(PublisherLookupStep step)? onStep,
    Future<void>? abandoned,
  }) async {
    final cover = await _outcomeOf(
      FfiService().fetchPublisherCoverImage(url),
      onStep ?? (_) {},
      abandoned: abandoned,
    );
    return (
      bytes: cover.bytes,
      imageUrl: cover.imageUrl,
      candidates: cover.candidates,
    );
  }

  /// The cover an engine stream ends with, its steps told to [report] on the
  /// way. Throws the error code it ends with instead, or `network` when it
  /// ends with neither. Once [abandoned] completes, the stream is cancelled,
  /// which the engine sees at its next step and stops the lookup there.
  static Future<frb.FrbPublisherCover> _outcomeOf(
    Stream<frb.FrbPublisherLookupEvent> events,
    void Function(PublisherLookupStep step) report, {
    Future<void>? abandoned,
  }) {
    final outcome = Completer<frb.FrbPublisherCover>();
    void fail(String code) {
      if (!outcome.isCompleted) outcome.completeError(code);
    }

    late final StreamSubscription<frb.FrbPublisherLookupEvent> subscription;
    subscription = events.listen(
      (event) {
        final step = event.step;
        if (step != null) {
          report(
            PublisherLookupStep(
              kind: step.kind,
              site: step.site,
              attempt: step.attempt,
              of: step.of,
              seconds: step.seconds,
              saidAt: DateTime.now(),
            ),
          );
          return;
        }
        final cover = event.cover;
        if (cover != null && !outcome.isCompleted) {
          outcome.complete(cover);
        } else {
          fail(event.error ?? 'network');
        }
        subscription.cancel();
      },
      onError: (Object e) {
        debugPrint('[WEB-COVER] publisher stream failed: $e');
        fail('network');
      },
      // The stream ended without its outcome.
      onDone: () => fail('network'),
    );
    abandoned?.then((_) {
      subscription.cancel();
      fail('network');
    });
    return outcome.future;
  }

  /// One engine search per book at a time: the dialog closed and opened again
  /// on the same book joins the search still running instead of sending the
  /// same requests to the publisher's site a second time.
  static final _publisherSearches =
      SingleFlight<FoundPublisherCover, PublisherLookupStep>();

  /// One search per book as asked: the ISBN in its canonical form (its
  /// ISBN-10 and ISBN-13 are one book), and the fields the search uses, so a
  /// publisher filled in since starts a new one.
  @visibleForTesting
  static String publisherSearchKey(PublisherBook book) => [
    IsbnValidator.canonicalKey(book.isbn.trim()),
    book.publisher?.trim().toLowerCase() ?? '',
    book.title.trim().toLowerCase(),
    book.authors.trim().toLowerCase(),
  ].join('\u0000');

  /// [listener], given to [findOnPublisherSiteAndSave], hears no more steps.
  void stopHearingSteps(void Function(PublisherLookupStep step) listener) =>
      _publisherSearches.stopHearing(listener);

  /// The engine sends the search's steps, then the cover or an error code,
  /// as the last event of its stream.
  static Future<FoundPublisherCover> _findViaFfi(
    PublisherBook book, {
    void Function(PublisherLookupStep step)? onStep,
  }) => _publisherSearches.run(publisherSearchKey(book), (
    report,
    abandoned,
  ) async {
    final cover = await _outcomeOf(
      FfiService().findCoverOnPublisherSite(
        isbn: book.isbn,
        title: book.title,
        authors: book.authors,
        publisher: book.publisher,
      ),
      report,
      abandoned: abandoned,
    );
    return (
      bytes: cover.bytes,
      imageUrl: cover.imageUrl,
      candidates: cover.candidates,
      site: cover.site,
    );
  }, onProgress: onStep);

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

  /// The site a search for [book] would look on first (`gallimard.fr`), read
  /// from the engine's table with no request, for the button that starts the
  /// search to name it. Null when the table knows none, the ISBN is not
  /// valid, or the engine cannot say.
  Future<String?> publisherSite(PublisherBook book) async {
    if (!IsbnValidator.isValid(book.isbn)) return null;
    try {
      final site = await _siteFor(_trimmed(book));
      return site == null || site.isEmpty ? null : site;
    } catch (e) {
      debugPrint('[WEB-COVER] publisher site unknown: $e');
      return null;
    }
  }

  /// [book] as the engine is given it: fields trimmed, no empty publisher.
  static PublisherBook _trimmed(PublisherBook book) {
    final publisher = book.publisher?.trim();
    return (
      isbn: book.isbn.trim(),
      title: book.title.trim(),
      authors: book.authors.trim(),
      publisher: publisher == null || publisher.isEmpty ? null : publisher,
    );
  }

  /// Look for [book]'s cover on its publisher's site (the engine finds the
  /// book's page from its ISBN, and takes it only if the page states it), and
  /// save it under a temp name. When the image found is one the app cannot
  /// keep (too large, animated), the page's next images are tried, under the
  /// lookup's rules. Throws [PublisherCoverException], whatever went wrong:
  /// no image the app can keep counts as no usable cover.
  ///
  /// [onStep] hears what the search is doing. Once [abandoned] completes
  /// (the dialog closed, an address won), the next images are no longer
  /// tried: the search itself stops when no dialog hears its steps any more
  /// ([stopHearingSteps]).
  Future<WebCoverPick> findOnPublisherSiteAndSave(
    PublisherBook book, {
    void Function(PublisherLookupStep step)? onStep,
    Future<void>? abandoned,
  }) async {
    var gone = false;
    abandoned?.then((_) => gone = true);
    final FoundPublisherCover found;
    try {
      found = await _findOnPublisherSite(_trimmed(book), onStep: onStep);
    } on String catch (code) {
      throw PublisherCoverException(code);
    } catch (e) {
      debugPrint('[WEB-COVER] publisher site search failed: $e');
      throw PublisherCoverException('network');
    }
    WebCoverPick picked(WebCoverPick pick) => WebCoverPick(
      path: pick.path,
      imageUrl: pick.imageUrl,
      candidates: found.candidates,
      site: found.site,
    );
    try {
      return picked(
        await _saveFetched((
          bytes: found.bytes,
          imageUrl: found.imageUrl,
          candidates: found.candidates,
        )),
      );
    } on WebCoverException catch (e) {
      debugPrint('[WEB-COVER] publisher cover not kept: $e');
    }
    final next = found.candidates.indexOf(found.imageUrl) + 1;
    for (final url in found.candidates.skip(next)) {
      if (gone) break;
      try {
        return picked(
          await fetchCandidateAndSave(
            url,
            fromPublisherSite: true,
            onStep: onStep,
            abandoned: abandoned,
          ),
        );
      } on WebCoverException catch (e) {
        debugPrint('[WEB-COVER] publisher candidate skipped: $e');
      }
    }
    throw PublisherCoverException('no_image_found');
  }

  /// Fetch one of a page's [WebCoverPick.candidates], when the user steps to
  /// the next image, and save it under a temp name. Candidates of a cover
  /// found on a publisher's site ([fromPublisherSite]) go through the
  /// engine's lookup rules: robots.txt, the pause between two requests to a
  /// host, the site's Crawl-delay, which can take as long as the search:
  /// [onStep] hears its steps, and [abandoned] completing stops it. Throws
  /// [WebCoverException].
  Future<WebCoverPick> fetchCandidateAndSave(
    String imageUrl, {
    bool fromPublisherSite = false,
    void Function(PublisherLookupStep step)? onStep,
    Future<void>? abandoned,
  }) async => _saveFetched(
    await _guard(
      () => fromPublisherSite
          ? _fetchPublisherImage(imageUrl, onStep: onStep, abandoned: abandoned)
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
