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
        'web_cover_no_more_images': 'No other image',
        'cancel': 'Cancel',
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
    await tester.pumpAndSettle();
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

  testWidgets('steps to the next image and drops the one it replaces', (
    tester,
  ) async {
    final opened = await openDialog(tester, found);
    await fetchAddress(tester);

    await tester.tap(find.text('Next image'));
    await tester.pumpAndSettle();
    expect(opened.discarded, ['/covers/temp_1.jpg']);

    await tester.tap(find.text('Next image'));
    await tester.pumpAndSettle();
    expect(find.text('Next image'), findsNothing, reason: 'last candidate');

    await tester.tap(find.text('Use this cover'));
    await tester.pumpAndSettle();
    expect(opened.results.single!.imageUrl, page.last);
    expect(opened.results.single!.path, '/covers/temp_3.jpg');
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

  testWidgets('tries a bounded number of candidates per tap', (tester) async {
    // Each try may take up to the engine's deadline while the dialog cannot
    // be dismissed: one tap must not walk the whole list.
    final many = List.generate(6, (i) => 'https://cdn.example.org/$i.jpg');
    final tried = <String>[];
    await openDialog(
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
    expect(tried, many.sublist(1, 4));
    expect(find.text('No other image'), findsNothing, reason: 'some are left');
    expect(find.text('Next image'), findsOneWidget);

    await tester.tap(find.text('Next image'));
    await tester.pumpAndSettle();
    expect(tried, many.sublist(1));
    await tester.tap(find.text('Use this cover'));
    await tester.pumpAndSettle();
  });
}
