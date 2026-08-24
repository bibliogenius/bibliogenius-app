import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/curated_lists_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/curated_book_preview.dart';

/// The books a curated list holds, shown before the reader commits to
/// importing them.
///
/// The asymmetry this closes: the import catalogue has always listed three
/// titles per list with a "see all" toggle, while the suggestion card of
/// ADR-066 went straight to a dialog that named a COUNT and no title at all.
/// The pushed surface showed less than the browsed one, which is backwards.

CuratedBook _book(String note) => CuratedBook(isbn: '978000000000', note: note);

List<CuratedBook> _books(int count) => [
  for (var i = 0; i < count; i++) _book('Title $i - Author $i'),
];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'curated_see_all_books': 'See the {count} books',
        'curated_see_less': 'See less',
        'catalog_already_in_library': 'Already in your library',
      },
    });
  });

  Future<void> pump(
    WidgetTester tester,
    List<CuratedBook> books, {
    double? maxExpandedHeight,
    Set<int> ownedIndexes = const {},
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: Scaffold(
            body: SingleChildScrollView(
              child: CuratedBookPreview(
                books: books,
                maxExpandedHeight: maxExpandedHeight,
                ownedIndexes: ownedIndexes,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('three titles show, the rest waits to be asked for', (
    tester,
  ) async {
    await pump(tester, _books(10));

    expect(find.text('Title 0'), findsOneWidget);
    expect(find.text('Title 1'), findsOneWidget);
    expect(find.text('Title 2'), findsOneWidget);
    expect(find.text('Title 3'), findsNothing);
  });

  testWidgets('the toggle names how many books it will reveal', (tester) async {
    await pump(tester, _books(10));

    expect(find.text('See the 10 books'), findsOneWidget);
  });

  testWidgets('asking reveals every book, and the toggle turns around', (
    tester,
  ) async {
    await pump(tester, _books(10));

    await tester.tap(find.text('See the 10 books'));
    await tester.pump();

    expect(find.text('Title 9'), findsOneWidget);
    expect(find.text('See less'), findsOneWidget);
    expect(find.text('See the 10 books'), findsNothing);
  });

  testWidgets('a list that fits carries no toggle at all', (tester) async {
    await pump(tester, _books(3));

    expect(find.text('Title 2'), findsOneWidget);
    expect(find.textContaining('See the'), findsNothing);
  });

  testWidgets('an entry with no note falls back to its ISBN', (tester) async {
    // Same rule the catalogue has always applied: never render an empty row.
    await pump(tester, const [CuratedBook(isbn: '9782070360024')]);

    expect(find.text('9782070360024'), findsOneWidget);
  });

  testWidgets('the title half of the note is what shows, not the author', (
    tester,
  ) async {
    await pump(tester, [_book('Le Procès - Franz Kafka')]);

    expect(find.text('Le Procès'), findsOneWidget);
  });

  testWidgets('an expanded list can be bounded so it cannot push the rest of '
      'a dialog off screen', (tester) async {
    await pump(tester, _books(60), maxExpandedHeight: 120);

    await tester.tap(find.text('See the 60 books'));
    await tester.pump();

    final box = tester.getSize(
      find.descendant(
        of: find.byType(CuratedBookPreview),
        matching: find.byType(Scrollable),
      ),
    );
    expect(box.height, lessThanOrEqualTo(120));
  });

  testWidgets('a book the reader already owns says so, in words', (
    tester,
  ) async {
    // Never icon-only. A tick the reader cannot hear, and cannot name when
    // they see it, states nothing (Rules A1 and A2).
    await pump(tester, _books(10), ownedIndexes: const {1});

    final owned = tester.getSemantics(
      find.ancestor(
        of: find.text('Title 1'),
        matching: find.byType(Semantics),
      ).first,
    );
    expect(owned.label, contains('Already in your library'));
    expect(owned.label, contains('Title 1'));

    expect(find.byTooltip('Already in your library'), findsOneWidget);
  });

  testWidgets('a book the reader does not own carries no mark', (
    tester,
  ) async {
    await pump(tester, _books(10), ownedIndexes: const {1});

    final plain = tester.getSemantics(
      find.ancestor(
        of: find.text('Title 0'),
        matching: find.byType(Semantics),
      ).first,
    );
    expect(plain.label, isNot(contains('Already in your library')));
  });

  testWidgets('the marking follows the book, not the visible row', (
    tester,
  ) async {
    // Indexes address the list, so unfolding must not shift a tick onto a
    // book the reader does not own.
    await pump(tester, _books(10), ownedIndexes: const {7});

    expect(find.byTooltip('Already in your library'), findsNothing);

    await tester.tap(find.text('See the 10 books'));
    await tester.pump();

    expect(find.byTooltip('Already in your library'), findsOneWidget);
    final owned = tester.getSemantics(
      find.ancestor(
        of: find.text('Title 7'),
        matching: find.byType(Semantics),
      ).first,
    );
    expect(owned.label, contains('Already in your library'));
  });

  testWidgets('an entry that carries a clean title uses it, not the note', (
    tester,
  ) async {
    // The 72 volumes of the Naruto list all note "Naruto - Tome N", and a
    // split on the FIRST dash renders every one of them as "Naruto". The
    // `title` field exists precisely because notes are unreliable (ADR-066
    // amendment A3); it was read for identity matching and ignored for
    // display.
    await pump(tester, const [
      CuratedBook(
        isbn: '9782505114741',
        note: 'Naruto - Tome 52',
        title: 'Naruto - Tome 52',
        authors: ['Masashi Kishimoto'],
      ),
    ]);

    expect(find.text('Naruto - Tome 52'), findsOneWidget);
    expect(find.text('Naruto'), findsNothing);
  });
}
