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
        'cancel': 'Cancel',
      },
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  /// Opens the dialog from a button and records what it resolves to.
  Future<List<WebCoverPick?>> openDialog(
    WidgetTester tester,
    WebCoverFetcher fetch,
  ) async {
    final results = <WebCoverPick?>[];
    final service = WebCoverService(
      fetch: fetch,
      save: (bytes, {bookId}) async => '/covers/$bookId.jpg',
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
                  bookId: 'book-1',
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
    return results;
  }

  Future<({Uint8List bytes, String imageUrl})> found(String url) async =>
      (bytes: Uint8List(4), imageUrl: 'https://cdn.example.org/42.jpg');

  testWidgets('resolves to the saved cover', (tester) async {
    final results = await openDialog(tester, found);

    await tester.enterText(find.byType(TextField), 'https://example.org/livre');
    await tester.tap(find.text('Get cover'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(results.single!.path, '/covers/book-1.jpg');
    expect(results.single!.imageUrl, 'https://cdn.example.org/42.jpg');
  });

  testWidgets('shows the translated error and stays open', (tester) async {
    final results = await openDialog(
      tester,
      (url) async => throw 'no_image_found',
    );

    await tester.enterText(find.byType(TextField), 'https://example.org/livre');
    await tester.tap(find.text('Get cover'));
    await tester.pumpAndSettle();

    expect(find.text('No cover image found'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('cannot be dismissed while a fetch runs', (tester) async {
    final pending = Completer<({Uint8List bytes, String imageUrl})>();
    final results = await openDialog(tester, (url) => pending.future);

    await tester.enterText(find.byType(TextField), 'https://example.org/livre');
    await tester.tap(find.text('Get cover'));
    await tester.pump();

    final cancel = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Cancel'),
    );
    expect(cancel.onPressed, isNull);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Back navigation is refused too.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);

    pending.complete(await found(''));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(results.single, isNotNull);
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
