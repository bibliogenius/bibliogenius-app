import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/widgets/metadata_refresh_dialog.dart';

/// A metadata source may answer a full date rather than a year: OpenLibrary's
/// `publish_date` is free text ("Jan 01, 2004"). The dialog used to propose its
/// first four characters, so the reader was offered "Jan " as a publication
/// year, and applying it wrote nothing.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Opens the dialog on a book with no year of its own and returns a getter on
  /// what the dialog eventually pops.
  Future<Map<String, dynamic>? Function()> openDialog(
    WidgetTester tester,
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
                    currentBook: Book(id: '1', title: 'Le mythe de Sisyphe'),
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

  testWidgets('a month-first date is offered as its year, not its prefix', (
    tester,
  ) async {
    await openDialog(tester, {'publication_year': 'Jan 01, 2004'});

    expect(find.textContaining('2004', findRichText: true), findsOneWidget);
    expect(find.textContaining('Jan', findRichText: true), findsNothing);
  });

  testWidgets('applying a month-first date writes the year', (tester) async {
    final applied = await openDialog(tester, {
      'publication_year': 'Jan 01, 2004',
    });

    // The dialog pre-selects a field the book has no value of its own for.
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(applied(), {'publication_year': 2004});
  });
}
