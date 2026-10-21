import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/widgets/book_cover_card.dart';
import 'package:bibliogenius/widgets/book_cover_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Home page covers grouped by reading status (Settings > Theme): fixed
// section order, empty sections dropped, every other status in "other".
void main() {
  Book book(String id, String? status) => Book(
    id: id,
    title: 'Book $id',
    author: 'Author',
    owned: true,
    readingStatus: status,
  );

  final books = [
    book('a', 'to_read'),
    book('b', 'reading'),
    book('c', 'abandoned'),
    book('d', 'read'),
    book('e', null),
    book('f', 'reading'),
  ];

  test('sections come in order and keep the books order', () {
    final groups = groupBooksByReadingStatus(books);

    expect(groups.map((g) => g.key), ['reading', 'to_read', 'read', null]);
    expect(groups.first.value.map((b) => b.id), ['b', 'f']);
    expect(groups.last.value.map((b) => b.id), ['c', 'e']);
  });

  test('empty sections are dropped', () {
    final groups = groupBooksByReadingStatus([book('a', 'read')]);

    expect(groups.map((g) => g.key), ['read']);
  });

  testWidgets('grouped grid shows one header per non-empty section', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: ThemeProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: BookCoverGrid(
              books: [book('a', 'reading'), book('b', 'read')],
              onBookTap: (_) {},
              groupByReadingStatus: true,
            ),
          ),
        ),
      ),
    );

    // No translations loaded in tests: the header shows the key.
    expect(find.textContaining('reading_status_reading'), findsOneWidget);
    expect(find.textContaining('reading_status_read '), findsOneWidget);
    expect(find.textContaining('reading_status_to_read'), findsNothing);
    expect(find.text('Book a'), findsOneWidget);
    expect(find.text('Book b'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('status sections stop at two rows, "other" is shown in full', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // Tall enough for every tile to be built; 800 px wide at the default
    // 150 px extent fits 5 columns.
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final seeAll = <String>[];
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: ThemeProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: BookCoverGrid(
              books: [
                for (var i = 0; i < 12; i++) book('r$i', 'reading'),
                for (var i = 0; i < 12; i++) book('o$i', null),
              ],
              onBookTap: (_) {},
              groupByReadingStatus: true,
              onSeeAllStatus: seeAll.add,
            ),
          ),
        ),
      ),
    );

    // 2 rows x 5 columns of the 12 reading books, all 12 others.
    expect(find.byType(BookCoverCard), findsNWidgets(10 + 12));
    expect(find.text('Book r9'), findsOneWidget);
    expect(find.text('Book r10'), findsNothing);
    // One link, for the status section only.
    expect(find.text('books_group_see_all'), findsOneWidget);

    await tester.tap(find.text('books_group_see_all'));
    expect(seeAll, ['reading']);
  });
}
