import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/widgets/metadata_refresh_dialog.dart';

/// The lookup answers a page count, but the dialog used to ignore the key: a
/// reader refreshing a book with no page count was told there was nothing new
/// while the source had it.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<Map<String, dynamic>? Function()> openDialog(
    WidgetTester tester,
    Book current,
    Map<String, String?> fetched,
  ) async {
    Map<String, dynamic>? applied;
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                applied = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (_) => MetadataRefreshDialog(
                    currentBook: current,
                    fetchedMetadata: fetched,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => applied;
  }

  testWidgets('a fetched page count is offered and applied as an integer', (
    tester,
  ) async {
    final applied = await openDialog(
      tester,
      Book(id: '1', title: 'Martin Eden'),
      {'page_count': '456'},
    );

    expect(find.textContaining('456', findRichText: true), findsOneWidget);

    // Pre-selected: the book has no page count of its own.
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(applied(), {'page_count': 456});
  });

  testWidgets('an identical page count is shown as unchanged, not applicable', (
    tester,
  ) async {
    await openDialog(
      tester,
      Book(id: '1', title: 'Martin Eden', pageCount: 456),
      {'page_count': '456'},
    );

    expect(find.byType(CheckboxListTile), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('a page count that is not a number is never applied', (
    tester,
  ) async {
    final applied = await openDialog(
      tester,
      Book(id: '1', title: 'Martin Eden'),
      {'page_count': 'n/a', 'publisher': 'Phébus'},
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(applied(), {'publisher': 'Phébus'});
  });
}
