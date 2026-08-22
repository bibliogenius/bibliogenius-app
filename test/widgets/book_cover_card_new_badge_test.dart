import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/collection.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/book_cover_card.dart';
import 'package:bibliogenius/widgets/book_cover_grid.dart';
import 'package:bibliogenius/widgets/collection_stack_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The covers grid was the only view with no "new" marker (spine view and the
// activity carousel both have one). The badge is OPT-IN per call site: the
// carousel and the peer screens already overlay their own markers, and a
// default-on badge would double-tag them.
void main() {
  late ThemeProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {'badge_new': 'Nouveau', 'reading_status_reading': 'En cours'},
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  Book book({String? status, bool owned = true, DateTime? addedAt}) => Book(
    title: 'Le Livre',
    owned: owned,
    readingStatus: status,
    addedAt: addedAt ?? DateTime.now(),
  );

  Future<void> pump(WidgetTester tester, Book b, {bool showNewBadge = false}) {
    return tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 160,
                height: 240,
                child: BookCoverCard(
                  book: b,
                  onTap: () {},
                  showNewBadge: showNewBadge,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a freshly added book wears the new badge when opted in', (
    tester,
  ) async {
    await pump(tester, book(), showNewBadge: true);
    expect(find.text('NOUVEAU'), findsOneWidget);
  });

  testWidgets('the badge is opt-in: absent by default', (tester) async {
    await pump(tester, book());
    expect(find.text('NOUVEAU'), findsNothing);
  });

  // NEW lives on the free bottom-right corner as the rotated shelf-style
  // band, so it never competes with the status badge (top-right) or the
  // ownership badge (top-left) and needs no silencing.
  testWidgets('the new band coexists with a status badge', (tester) async {
    await pump(tester, book(status: 'reading'), showNewBadge: true);
    expect(find.text('NOUVEAU'), findsOneWidget);
    expect(find.text('EN COURS'), findsOneWidget);
  });

  testWidgets('a not-owned recent book still shows the new band', (
    tester,
  ) async {
    await pump(tester, book(owned: false), showNewBadge: true);
    expect(find.text('NOUVEAU'), findsOneWidget);
  });

  testWidgets('the band carries the shelf-view rotation', (tester) async {
    await pump(tester, book(), showNewBadge: true);
    final rotated = tester.widget<Transform>(
      find.ancestor(of: find.text('NOUVEAU'), matching: find.byType(Transform)),
    );
    expect(rotated.transform, isNot(Matrix4.identity()));
  });

  testWidgets('an old book is never new', (tester) async {
    await pump(
      tester,
      book(addedAt: DateTime.now().subtract(const Duration(days: 365))),
      showNewBadge: true,
    );
    expect(find.text('NOUVEAU'), findsNothing);
  });

  // End to end through the covers grid itself: a freshly added book with a
  // reading status, sitting among old books, must wear the band.
  testWidgets('the covers grid tags a new book among old ones', (tester) async {
    final old = book(
      addedAt: DateTime.now().subtract(const Duration(days: 365)),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: BookCoverGrid(
              books: [
                book(status: 'to_read'),
                old,
                old,
              ],
              onBookTap: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('NOUVEAU'), findsOneWidget);
  });

  // The all-new veto is a FULL-LIBRARY rule: a search or filter isolating
  // one fresh book is an all-new subset, and the band must survive there.
  // The screen passes the full-library verdict; the grid honors it over its
  // own (subset) evaluation.
  testWidgets('a search result of one fresh book keeps its band', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: BookCoverGrid(
              books: [book(status: 'to_read')],
              onBookTap: (_) {},
              showNewBadge: true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('NOUVEAU'), findsOneWidget);
  });

  // The group-by-collection view is a drop-in replacement for the covers
  // grid and must tag its standalone books the same way.
  testWidgets('the grouped-collections grid tags its standalone books', (
    tester,
  ) async {
    final old = book(
      addedAt: DateTime.now().subtract(const Duration(days: 365)),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: CollectionGroupGrid(
              groups: [
                CollectionGroup(collection: null, books: [book()]),
                CollectionGroup(collection: null, books: [old]),
              ],
              onBookTap: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('NOUVEAU'), findsOneWidget);
  });

  // Collection stacks never carry the band: their corner already holds the
  // book-count badge, which masked it. Only standalone cards are tagged in
  // the grouped view.
  testWidgets('a collection stack never wears the band', (tester) async {
    final old = book(
      addedAt: DateTime.now().subtract(const Duration(days: 365)),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: CollectionGroupGrid(
              groups: [
                CollectionGroup(
                  collection: Collection(
                    id: 'c1',
                    name: 'Tobie Lolness',
                    source: 'series',
                    createdAt: '2026-01-01',
                    updatedAt: '2026-01-01',
                  ),
                  books: [book(), old],
                ),
                CollectionGroup(collection: null, books: [old]),
              ],
              onBookTap: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('NOUVEAU'), findsNothing);
  });

  // When EVERY displayed book is new (fresh import, brand new library), the
  // tag differentiates nothing and is pure noise. The grid decides once for
  // the whole list.
  group('newBadgeIsInformative', () {
    final old = book(
      addedAt: DateTime.now().subtract(const Duration(days: 365)),
    );

    test('a mixed list keeps the tag', () {
      expect(newBadgeIsInformative([book(), old]), isTrue);
    });

    test('an all-new list drops the tag', () {
      expect(newBadgeIsInformative([book(), book()]), isFalse);
    });

    test('an empty list shows nothing anyway', () {
      expect(newBadgeIsInformative(const []), isFalse);
    });
  });
}
