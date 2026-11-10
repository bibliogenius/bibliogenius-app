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
        'cancel': 'Cancel',
      },
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  Future<({Uint8List bytes, String imageUrl})> found(String url) async =>
      (bytes: Uint8List(4), imageUrl: 'https://cdn.example.org/42.jpg');

  /// Opens the dialog from a button. Returns what it resolved to and the
  /// temp files it asked to delete.
  Future<({List<WebCoverPick?> results, List<String> discarded})> openDialog(
    WidgetTester tester,
    WebCoverFetcher fetch,
  ) async {
    final results = <WebCoverPick?>[];
    final discarded = <String>[];
    var saves = 0;
    final service = WebCoverService(
      fetch: fetch,
      save: (bytes) async => '/covers/temp_${++saves}.jpg',
      discard: (path) async => discarded.add(path),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  results.add(await showWebCoverDialog(context, service: service)),
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
    expect(opened.results.single!.imageUrl, 'https://cdn.example.org/42.jpg');
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
      (url) async => throw 'no_image_found',
    );
    await fetchAddress(tester);

    expect(find.text('No cover image found'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(opened.results, isEmpty);
  });

  testWidgets('cannot be dismissed while a fetch runs', (tester) async {
    final pending = Completer<({Uint8List bytes, String imageUrl})>();
    final opened = await openDialog(tester, (url) => pending.future);

    await tester.enterText(find.byType(TextField), 'https://example.org/livre');
    await tester.tap(find.text('Get cover'));
    await tester.pump();

    final cancel = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Cancel'),
    );
    expect(cancel.onPressed, isNull);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Read-only, not disabled: a disabled field drops the focus, and the user
    // would have to tap it again to correct the address after an error.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.readOnly, isTrue);
    expect(field.enabled, isNot(isFalse));

    // Back navigation is refused too.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);

    pending.complete(await found(''));
    await tester.pumpAndSettle();
    expect(find.text('Use this cover'), findsOneWidget);
    expect(opened.results, isEmpty);
  });

  testWidgets('does nothing on an empty address', (tester) async {
    var calls = 0;
    await openDialog(tester, (url) {
      calls++;
      return found(url);
    });

    await tester.tap(find.text('Get cover'));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
