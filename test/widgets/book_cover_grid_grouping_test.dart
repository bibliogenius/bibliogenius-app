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

  group('shouldGroupByReadingStatus', () {
    bool group({
      bool enabled = true,
      bool inventoryStatuses = false,
      bool selecting = false,
      bool statusFiltered = false,
      bool searching = false,
      bool shelfFiltered = false,
    }) => shouldGroupByReadingStatus(
      enabled: enabled,
      inventoryStatuses: inventoryStatuses,
      selecting: selecting,
      statusFiltered: statusFiltered,
      searching: searching,
      shelfFiltered: shelfFiltered,
    );

    test('groups while browsing the whole library', () {
      expect(group(), isTrue);
    });

    test('never when the setting is off', () {
      expect(group(enabled: false), isFalse);
    });

    test('never with inventory statuses, which replace the reading ones', () {
      expect(group(inventoryStatuses: true), isFalse);
    });

    test('never in selection mode, where "select all" takes every book', () {
      expect(group(selecting: true), isFalse);
    });

    test('never under a status filter, a search or a shelf', () {
      expect(group(statusFiltered: true), isFalse);
      expect(group(searching: true), isFalse);
      expect(group(shelfFiltered: true), isFalse);
    });
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

  testWidgets('the two-row cap follows the grid columns on a narrow phone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // A 360 dp phone: the grid is 328 px wide inside its padding, which fits
    // 2 columns of 150 px covers, so two rows hold 4 books, not 6.
    tester.view.physicalSize = const Size(360, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: ThemeProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: BookCoverGrid(
              books: [for (var i = 0; i < 12; i++) book('r$i', 'reading')],
              onBookTap: (_) {},
              groupByReadingStatus: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BookCoverCard), findsNWidgets(4));
  });

  testWidgets('"See all" names its count when it opens more books', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: ThemeProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: BookCoverGrid(
              books: [
                for (var i = 0; i < 3; i++) book('d$i', 'read'),
                for (var i = 0; i < 2; i++) book('r$i', 'reading'),
              ],
              onBookTap: (_) {},
              groupByReadingStatus: true,
              onSeeAllStatus: (_) {},
              // The status filter adds 2 books read but not owned; the
              // reading one opens exactly the section.
              seeAllCount: (status) => status == 'read' ? 5 : 2,
            ),
          ),
        ),
      ),
    );

    expect(find.text('books_group_see_all (5)'), findsOneWidget);
    expect(find.text('books_group_see_all'), findsOneWidget);
  });
}
