import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/services/web_cover_service.dart';
import 'package:bibliogenius/widgets/web_cover_dialog.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'web_cover_dialog_title': 'Cover from a web page',
        'web_cover_dialog_help': 'Paste the address',
        'web_cover_dialog_field': 'Page or image address',
        'web_cover_dialog_fetch': 'Get cover',
        'web_cover_dialog_loading': 'Fetching the cover',
        'web_cover_error_no_image_found': 'No cover image found',
        'web_cover_use': 'Use this cover',
        'web_cover_try_another': 'Try another address',
        'web_cover_preview_label': 'Cover found on the page',
        'web_cover_next_image': 'Next image',
        'web_cover_previous_image': 'Previous image',
        'web_cover_no_more_images': 'No other image',
        'cancel': 'Cancel',
        'publisher_cover_searching': "Looking on the publisher's site",
        'publisher_cover_found_on': 'Found on {site}',
        'publisher_cover_error_no_site': "This publisher's site is not known",
        'publisher_cover_step_product_page':
            '{site}: page, try {attempt} of {of}',
        'publisher_cover_step_waiting': '{site} asks to wait: {seconds} s',
        'publisher_cover_show_found': 'Show the cover found on {site}',
        'publisher_cover_step_cover': '{site}: fetching the cover',
      },
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  const page = [
    'https://cdn.example.org/a.jpg',
    'https://cdn.example.org/b.jpg',
    'https://cdn.example.org/c.jpg',
  ];

  Future<FetchedWebCover> found(String url, {String? isbn}) async =>
      (bytes: Uint8List(4), imageUrl: page.first, candidates: page);

  /// Opens the dialog from a button. Returns what it resolved to and the
  /// temp files it asked to delete.
  Future<({List<WebCoverPick?> results, List<String> discarded})> openDialog(
    WidgetTester tester,
    WebCoverFetcher fetch, {
    WebCoverImageFetcher? fetchImage,
    String? isbn,
    PublisherBook? book,
    PublisherCoverFinder? findOnPublisherSite,
    PublisherImageFetcher? fetchPublisherImage,
    bool settle = true,
  }) async {
    final results = <WebCoverPick?>[];
    final discarded = <String>[];
    var saves = 0;
    final service = WebCoverService(
      fetch: fetch,
      fetchImage:
          fetchImage ??
          (url) async =>
              (bytes: Uint8List(4), imageUrl: url, candidates: <String>[]),
      save: (bytes) async => '/covers/temp_${++saves}.jpg',
      discard: (path) async => discarded.add(path),
      findOnPublisherSite:
          findOnPublisherSite ??
          (_, {onStep}) async =>
              throw StateError('no publisher search expected'),
      fetchPublisherImage:
          fetchPublisherImage ??
          (_, {onStep}) async =>
              throw StateError('no publisher image expected'),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(
                await showWebCoverDialog(
                  context,
                  isbn: isbn,
                  book: book,
                  service: service,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // A search still running animates its progress bar forever.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
    return (results: results, discarded: discarded);
  }

  Future<void> fetchAddress(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'https://example.org/livre');
    await tester.tap(find.text('Get cover'));
    await tester.pumpAndSettle();
  }

  testWidgets('previews the cover before anything is replaced', (tester) async {
    final opened = await openDialog(tester, found);
    await fetchAddress(tester);

    expect(find.bySemanticsLabel('Cover found on the page'), findsOneWidget);
    expect(opened.results, isEmpty, reason: 'still waiting for the user');

    await tester.tap(find.text('Use this cover'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(opened.results.single!.path, '/covers/temp_1.jpg');
    expect(opened.results.single!.imageUrl, page.first);
    expect(opened.discarded, isEmpty, reason: 'a kept preview stays');
  });

  testWidgets('drops a refused preview and asks again', (tester) async {
    final opened = await openDialog(tester, found);
    await fetchAddress(tester);

    await tester.tap(find.text('Try another address'));
    await tester.pumpAndSettle();

    expect(opened.discarded, ['/covers/temp_1.jpg']);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);

    await fetchAddress(tester);
    await tester.tap(find.text('Use this cover'));
    await tester.pumpAndSettle();
    expect(opened.results.single!.path, '/covers/temp_2.jpg');
  });

  testWidgets('deletes the preview when the dialog is left', (tester) async {
    final opened = await openDialog(tester, found);
    await fetchAddress(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(opened.results.single, isNull);
    expect(opened.discarded, ['/covers/temp_1.jpg']);
  });

  testWidgets('shows the translated error and stays open', (tester) async {
    final opened = await openDialog(
      tester,
      (url, {isbn}) async => throw 'no_image_found',
    );
    await fetchAddress(tester);

    expect(find.text('No cover image found'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(opened.results, isEmpty);
  });

  testWidgets('can be left while a fetch runs; a late result is deleted', (
    tester,
  ) async {
    final pending = Completer<FetchedWebCover>();
    final opened = await openDialog(tester, (url, {isbn}) => pending.future);

    await tester.enterText(find.byType(TextField), 'https://example.org/livre');
    await tester.tap(find.text('Get cover'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Read-only, not disabled: a disabled field drops the focus, and the user
    // would have to tap it again to correct the address after an error.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.readOnly, isTrue);
    expect(field.enabled, isNot(isFalse));

    // A slow site must not hold the user: Cancel works during the fetch.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(opened.results.single, isNull);

    // The cover saved after the user left is not left on disk.
    pending.complete(await found(''));
    await tester.pumpAndSettle();
    expect(opened.discarded, ['/covers/temp_1.jpg']);
  });

  testWidgets('announces the preview to screen readers', (tester) async {
    await openDialog(tester, found);
    tester.takeAnnouncements();
    await tester.enterText(find.byType(TextField), 'https://example.org/livre');
    await tester.tap(find.text('Get cover'));
    await tester.pumpAndSettle();
    expect(
      tester.takeAnnouncements().map((a) => a.message),
      contains('Cover found on the page'),
    );
  });

  testWidgets('does nothing on an empty address', (tester) async {
    var calls = 0;
    await openDialog(tester, (url, {isbn}) {
      calls++;
      return found(url);
    });

    await tester.tap(find.text('Get cover'));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('steps to the next image, and drops the others on keeping', (
    tester,
  ) async {
    final opened = await openDialog(tester, found);
    await fetchAddress(tester);
    expect(find.text('Previous image'), findsNothing, reason: 'first image');

    await tester.tap(find.text('Next image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next image'));
    await tester.pumpAndSettle();
    expect(find.text('Next image'), findsNothing, reason: 'last candidate');
    expect(opened.discarded, isEmpty, reason: 'kept for going back');

    await tester.tap(find.text('Use this cover'));
    await tester.pumpAndSettle();
    expect(opened.results.single!.imageUrl, page.last);
    expect(opened.results.single!.path, '/covers/temp_3.jpg');
    expect(opened.discarded, ['/covers/temp_1.jpg', '/covers/temp_2.jpg']);
  });

  testWidgets('goes back to an image already seen, without fetching it', (
    tester,
  ) async {
    final fetched = <String>[];
    final opened = await openDialog(
      tester,
      found,
      fetchImage: (url) async {
        fetched.add(url);
        return (bytes: Uint8List(4), imageUrl: url, candidates: <String>[]);
      },
    );
    await fetchAddress(tester);
    await tester.tap(find.text('Next image'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Previous image'));
    await tester.pumpAndSettle();
    expect(find.text('Previous image'), findsNothing);

    // Forward again: the second image comes from the history.
    await tester.tap(find.text('Next image'));
    await tester.pumpAndSettle();
    expect(fetched, [page[1]], reason: 'each candidate fetched once');

    await tester.tap(find.text('Previous image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this cover'));
    await tester.pumpAndSettle();
    expect(opened.results.single!.imageUrl, page.first);
    expect(opened.discarded, ['/covers/temp_2.jpg']);
  });

  testWidgets('drops every preview shown when the dialog is left', (
    tester,
  ) async {
    final opened = await openDialog(tester, found);
    await fetchAddress(tester);
    await tester.tap(find.text('Next image'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(opened.results.single, isNull);
    expect(opened.discarded, ['/covers/temp_1.jpg', '/covers/temp_2.jpg']);
  });

  testWidgets('skips a candidate that fails and says when none is left', (
    tester,
  ) async {
    final opened = await openDialog(
      tester,
      found,
      fetchImage: (url) async {
        if (url == page[1]) throw 'unsupported_image';
        if (url == page[2]) throw 'http_status';
        return (bytes: Uint8List(4), imageUrl: url, candidates: <String>[]);
      },
    );
    await fetchAddress(tester);

    await tester.tap(find.text('Next image'));
    await tester.pumpAndSettle();

    expect(find.text('No other image'), findsOneWidget);
    expect(find.text('Next image'), findsNothing);
    expect(opened.discarded, isEmpty, reason: 'the shown cover stays');
    await tester.tap(find.text('Use this cover'));
    await tester.pumpAndSettle();
    expect(opened.results.single!.imageUrl, page.first);
  });

  testWidgets('offers no next image for a single candidate', (tester) async {
    await openDialog(
      tester,
      (url, {isbn}) async =>
          (bytes: Uint8List(4), imageUrl: url, candidates: [url]),
    );
    await fetchAddress(tester);
    expect(find.text('Use this cover'), findsOneWidget);
    expect(find.text('Next image'), findsNothing);
  });

  testWidgets('hands the book ISBN to the search', (tester) async {
    String? seen;
    await openDialog(tester, (url, {isbn}) {
      seen = isbn;
      return found(url);
    }, isbn: '9782290003299');
    await fetchAddress(tester);
    expect(seen, '9782290003299');
  });

  testWidgets('one tap skips every failing candidate to the next image', (
    tester,
  ) async {
    // The dialog can be left at any time, so a tap need not give up early:
    // the cover may be the sixth image of the page.
    final many = List.generate(6, (i) => 'https://cdn.example.org/$i.jpg');
    final tried = <String>[];
    final opened = await openDialog(
      tester,
      (url, {isbn}) async =>
          (bytes: Uint8List(4), imageUrl: many.first, candidates: many),
      fetchImage: (url) async {
        tried.add(url);
        if (url != many.last) throw 'http_status';
        return (bytes: Uint8List(4), imageUrl: url, candidates: <String>[]);
      },
    );
    await fetchAddress(tester);

    await tester.tap(find.text('Next image'));
    await tester.pumpAndSettle();
    expect(tried, many.sublist(1));
    expect(find.text('Next image'), findsNothing, reason: 'last candidate');
    await tester.tap(find.text('Use this cover'));
    await tester.pumpAndSettle();
    expect(opened.results.single!.imageUrl, many.last);
  });

  group('publisher site', () {
    const book = (
      isbn: '9782070360024',
      title: "L'Étranger",
      authors: 'Albert Camus',
      publisher: 'Gallimard',
    );
    const gallimard = [
      'https://www.gallimard.fr/couv/9782070360024.jpg',
      'https://www.gallimard.fr/couv/autre.jpg',
    ];

    Future<FoundPublisherCover> foundOnSite(PublisherBook b) async => (
      bytes: Uint8List(4),
      imageUrl: gallimard.first,
      candidates: gallimard,
      site: 'gallimard.fr',
    );

    testWidgets('looks on the site as the dialog opens and previews it', (
      tester,
    ) async {
      PublisherBook? asked;
      final stepped = <String>[];
      final opened = await openDialog(
        tester,
        found,
        book: book,
        findOnPublisherSite: (b, {onStep}) {
          asked = b;
          return foundOnSite(b);
        },
        // The page's other images come through the lookup's rules
        // (robots.txt, pause, Crawl-delay), not the Web button's fetch.
        fetchImage: (_) async => throw StateError('not the Web fetch'),
        fetchPublisherImage: (url, {onStep}) async {
          stepped.add(url);
          return (bytes: Uint8List(4), imageUrl: url, candidates: <String>[]);
        },
      );

      expect(asked?.isbn, book.isbn);
      expect(find.bySemanticsLabel('Cover found on the page'), findsOneWidget);
      expect(find.text('Found on gallimard.fr'), findsOneWidget);

      // The page's other images can be stepped through, as for an address.
      await tester.tap(find.text('Next image'));
      await tester.pumpAndSettle();
      expect(find.text('Found on gallimard.fr'), findsOneWidget);
      expect(stepped, [gallimard.last]);

      await tester.tap(find.text('Use this cover'));
      await tester.pumpAndSettle();
      expect(opened.results.single!.imageUrl, gallimard.last);
      expect(opened.discarded, ['/covers/temp_1.jpg']);
    });

    testWidgets('no search for a book without an ISBN', (tester) async {
      var searches = 0;
      await openDialog(
        tester,
        found,
        book: (isbn: '  ', title: 'Sans ISBN', authors: '', publisher: null),
        findOnPublisherSite: (b, {onStep}) {
          searches++;
          return foundOnSite(b);
        },
      );
      expect(searches, 0);
      expect(find.text("Looking on the publisher's site"), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a failed search says why and leaves the address field', (
      tester,
    ) async {
      final opened = await openDialog(
        tester,
        found,
        book: book,
        findOnPublisherSite: (_, {onStep}) async => throw 'no_site',
      );
      expect(find.text("This publisher's site is not known"), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue, reason: 'the way on');

      await fetchAddress(tester);
      expect(find.bySemanticsLabel('Cover found on the page'), findsOneWidget);
      expect(find.textContaining('Found on'), findsNothing);

      // The search's failure no longer applies once an address gave a cover.
      await tester.tap(find.text('Try another address'));
      await tester.pumpAndSettle();
      expect(find.text("This publisher's site is not known"), findsNothing);
      await fetchAddress(tester);
      await tester.tap(find.text('Use this cover'));
      await tester.pumpAndSettle();
      expect(opened.results.single!.imageUrl, page.first);
    });

    testWidgets('an ISBN still being typed starts no search', (tester) async {
      var searches = 0;
      await openDialog(
        tester,
        found,
        book: (isbn: '978207036', title: 'T', authors: '', publisher: null),
        findOnPublisherSite: (b, {onStep}) {
          searches++;
          return foundOnSite(b);
        },
      );
      expect(searches, 0);
      expect(find.textContaining('ISBN'), findsNothing);
    });

    testWidgets('a cover found while an address is typed waits aside', (
      tester,
    ) async {
      final pending = Completer<FoundPublisherCover>();
      final opened = await openDialog(
        tester,
        found,
        book: book,
        findOnPublisherSite: (_, {onStep}) => pending.future,
        settle: false,
      );
      await tester.enterText(find.byType(TextField), 'https://example.org/l');
      pending.complete(await foundOnSite(book));
      await tester.pumpAndSettle();

      // What the user types stays on screen.
      expect(find.text('https://example.org/l'), findsOneWidget);
      expect(find.bySemanticsLabel('Cover found on the page'), findsNothing);

      await tester.tap(find.text('Show the cover found on gallimard.fr'));
      await tester.pumpAndSettle();
      expect(find.text('Found on gallimard.fr'), findsOneWidget);
      await tester.tap(find.text('Use this cover'));
      await tester.pumpAndSettle();
      expect(opened.results.single!.imageUrl, gallimard.first);
      expect(opened.discarded, isEmpty);
    });

    testWidgets('a cover set aside and not shown is deleted on leaving', (
      tester,
    ) async {
      final pending = Completer<FoundPublisherCover>();
      final opened = await openDialog(
        tester,
        found,
        book: book,
        findOnPublisherSite: (_, {onStep}) => pending.future,
        settle: false,
      );
      await tester.enterText(find.byType(TextField), 'https://example.org/l');
      pending.complete(await foundOnSite(book));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(opened.discarded, ['/covers/temp_1.jpg']);
    });

    testWidgets('an address can be fetched during the search, and wins', (
      tester,
    ) async {
      final pending = Completer<FoundPublisherCover>();
      final opened = await openDialog(
        tester,
        found,
        book: book,
        findOnPublisherSite: (_, {onStep}) => pending.future,
        settle: false,
      );
      expect(find.text("Looking on the publisher's site"), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.readOnly, isFalse, reason: 'the search does not hold it');
      expect(field.autofocus, isFalse, reason: 'no keyboard over the search');

      await fetchAddress(tester);
      expect(find.bySemanticsLabel('Cover found on the page'), findsOneWidget);

      // The site answers late: what the user fetched stays on screen.
      pending.complete(await foundOnSite(book));
      await tester.pumpAndSettle();
      expect(find.textContaining('Found on'), findsNothing);
      expect(opened.discarded, ['/covers/temp_2.jpg']);

      await tester.tap(find.text('Use this cover'));
      await tester.pumpAndSettle();
      expect(opened.results.single!.path, '/covers/temp_1.jpg');
    });

    testWidgets('left during the search, its late result is deleted', (
      tester,
    ) async {
      final pending = Completer<FoundPublisherCover>();
      final opened = await openDialog(
        tester,
        found,
        book: book,
        findOnPublisherSite: (_, {onStep}) => pending.future,
        settle: false,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(opened.results.single, isNull);

      pending.complete(await foundOnSite(book));
      await tester.pumpAndSettle();
      expect(opened.discarded, ['/covers/temp_1.jpg']);
    });

    testWidgets('says what the search is doing, and counts a wait down', (
      tester,
    ) async {
      final pending = Completer<FoundPublisherCover>();
      late void Function(PublisherLookupStep) step;
      final opened = await openDialog(
        tester,
        found,
        book: book,
        findOnPublisherSite: (_, {onStep}) {
          step = onStep!;
          return pending.future;
        },
        settle: false,
      );

      step(
        const PublisherLookupStep(
          kind: 'product_page',
          site: 'gallimard.fr',
          attempt: 2,
          of: 3,
        ),
      );
      await tester.pump();
      expect(find.text('gallimard.fr: page, try 2 of 3'), findsOneWidget);

      step(
        const PublisherLookupStep(
          kind: 'waiting',
          site: 'gallimard.fr',
          seconds: 10,
        ),
      );
      await tester.pump();
      expect(find.text('gallimard.fr asks to wait: 10 s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('gallimard.fr asks to wait: 7 s'), findsOneWidget);

      // Left during the wait: the countdown stops with the dialog.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(opened.results.single, isNull);
      pending.complete(await foundOnSite(book));
      await tester.pumpAndSettle();
    });

    testWidgets('says what the next image of a publisher cover waits for', (
      tester,
    ) async {
      final pending = Completer<FetchedWebCover>();
      late void Function(PublisherLookupStep) step;
      await openDialog(
        tester,
        found,
        book: book,
        findOnPublisherSite: (b, {onStep}) => foundOnSite(b),
        fetchPublisherImage: (url, {onStep}) {
          step = onStep!;
          return pending.future;
        },
      );
      await tester.tap(find.text('Next image'));
      await tester.pump();
      step(
        const PublisherLookupStep(
          kind: 'waiting',
          site: 'gallimard.fr',
          seconds: 10,
        ),
      );
      await tester.pump();
      expect(find.text('gallimard.fr asks to wait: 10 s'), findsOneWidget);
      step(const PublisherLookupStep(kind: 'cover', site: 'gallimard.fr'));
      await tester.pump();
      expect(find.text('gallimard.fr: fetching the cover'), findsOneWidget);

      pending.complete((
        bytes: Uint8List(4),
        imageUrl: gallimard.last,
        candidates: <String>[],
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('fetching the cover'), findsNothing);
    });
  });
}
