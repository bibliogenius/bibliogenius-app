import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/recently_added_carousel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ThemeProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'recently_added_title': 'Recently added',
        'carousel_expand_tooltip': 'Expand carousel',
        'carousel_collapse_tooltip': 'Collapse carousel',
        'carousel_hide_long_press_tooltip': 'Long-press to hide',
        'carousel_collapsed_label': 'Recently added · {count}',
        'carousel_hide_tooltip': 'Hide carousel',
        'carousel_hidden_snackbar': 'Carousel hidden',
        'action_undo': 'Undo',
        'badge_new': 'NEW',
        'badge_days_since_start': 'D+%s',
        'reading_status_reading': 'Currently reading',
      },
    });
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  Book newBook({required int id, required String title}) => Book(
    id: id,
    title: title,
    addedAt: DateTime.now().subtract(const Duration(hours: 1)),
  );

  Book oldBook({required int id, required String title}) => Book(
    id: id,
    title: title,
    addedAt: DateTime.now().subtract(const Duration(days: 365)),
  );

  Book readingBook({
    required int id,
    required String title,
    DateTime? startedAt,
    DateTime? addedAt,
  }) => Book(
    id: id,
    title: title,
    readingStatus: 'reading',
    startedReadingAt: startedAt,
    addedAt: addedAt ?? DateTime.now().subtract(const Duration(days: 365)),
  );

  /// Pads the library with enough old books to clear the auto-hide thresholds
  /// (`_minLibrarySize = 10`, `_maxRecentRatio = 0.6`).
  List<Book> withPad(List<Book> books, {int pad = 9}) => [
    ...books,
    for (var i = 0; i < pad; i++)
      oldBook(id: 1000 + i, title: 'Old $i'),
  ];

  Widget buildHarness(List<Book> books) {
    return MaterialApp(
      home: ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: Scaffold(
          body: RecentlyAddedCarousel(
            books: books,
            scope: RecentlyAddedCarouselScope.ownLib,
            onBookTap: (_) {}, // avoid router dependency
          ),
        ),
      ),
    );
  }

  testWidgets('renders nothing when no recent books', (tester) async {
    await tester.pumpWidget(buildHarness([
      oldBook(id: 1, title: 'Old'),
    ]));

    expect(find.text('Recently added'), findsNothing);
  });

  testWidgets('renders nothing when hidden', (tester) async {
    await provider.setCarouselHiddenOwnLib(true);
    await tester.pumpWidget(buildHarness(withPad([
      newBook(id: 1, title: 'New Book'),
    ])));

    expect(find.text('Recently added'), findsNothing);
  });

  testWidgets('renders nothing when library is too small', (tester) async {
    // 2 new books, 5 old books: total = 7, below _minLibrarySize = 10.
    await tester.pumpWidget(buildHarness([
      newBook(id: 1, title: 'A'),
      newBook(id: 2, title: 'B'),
      for (var i = 0; i < 5; i++) oldBook(id: 100 + i, title: 'Old $i'),
    ]));

    expect(find.text('Recently added'), findsNothing);
  });

  testWidgets('renders nothing when recent-to-total ratio exceeds threshold',
      (tester) async {
    // 7 new, 3 old: total = 10 (>= min), ratio = 0.7 > 0.6.
    await tester.pumpWidget(buildHarness([
      for (var i = 0; i < 7; i++) newBook(id: i, title: 'New $i'),
      for (var i = 0; i < 3; i++) oldBook(id: 100 + i, title: 'Old $i'),
    ]));

    expect(find.text('Recently added'), findsNothing);
  });

  testWidgets('expanded state shows title and covers', (tester) async {
    await tester.pumpWidget(buildHarness(withPad([
      newBook(id: 1, title: 'New Book A'),
      newBook(id: 2, title: 'New Book B'),
    ])));

    expect(find.text('Recently added'), findsOneWidget);
    expect(find.byIcon(Icons.expand_less_rounded), findsOneWidget);
  });

  testWidgets('books without coverUrl render the title as a fallback',
      (tester) async {
    await tester.pumpWidget(buildHarness(withPad([
      newBook(id: 1, title: 'New Book A'),
      newBook(id: 2, title: 'New Book B'),
    ])));

    // BookCoverCard renders the title inside the colored fallback when
    // coverUrl is null, so users can identify the book in the carousel.
    expect(find.text('New Book A'), findsOneWidget);
    expect(find.text('New Book B'), findsOneWidget);
  });

  testWidgets('tapping collapse chevron switches to collapsed bar',
      (tester) async {
    await tester.pumpWidget(buildHarness(withPad([
      newBook(id: 1, title: 'A'),
      newBook(id: 2, title: 'B'),
    ])));

    await tester.tap(find.byIcon(Icons.expand_less_rounded));
    await tester.pumpAndSettle();

    expect(provider.carouselCollapsedOwnLib, isTrue);
    expect(find.text('Recently added · 2'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
    expect(find.byIcon(Icons.expand_less_rounded), findsNothing);
  });

  testWidgets('tapping collapsed bar re-expands the carousel',
      (tester) async {
    provider.setCarouselCollapsedOwnLib(true);
    await tester.pumpWidget(buildHarness(withPad([
      newBook(id: 1, title: 'A'),
    ])));

    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    await tester.pumpAndSettle();

    expect(provider.carouselCollapsedOwnLib, isFalse);
    expect(find.text('Recently added'), findsOneWidget);
  });

  testWidgets('long-press on collapsed bar hides the carousel',
      (tester) async {
    provider.setCarouselCollapsedOwnLib(true);
    await tester.pumpWidget(buildHarness(withPad([
      newBook(id: 1, title: 'A'),
    ])));

    await tester.longPress(find.byIcon(Icons.expand_more_rounded));
    await tester.pump();

    expect(provider.carouselHiddenOwnLib, isTrue);
  });

  testWidgets('long-press on expanded chevron hides the carousel',
      (tester) async {
    await tester.pumpWidget(buildHarness(withPad([
      newBook(id: 1, title: 'A'),
    ])));

    await tester.longPress(find.byIcon(Icons.expand_less_rounded));
    await tester.pump();

    expect(provider.carouselHiddenOwnLib, isTrue);
  });

  testWidgets('currently-reading books appear before recently-added books',
      (tester) async {
    final reading = readingBook(
      id: 50,
      title: 'Reading Book',
      startedAt: DateTime.now().subtract(const Duration(days: 2)),
    );
    final recent = newBook(id: 51, title: 'New Book');

    await tester.pumpWidget(buildHarness(withPad([recent, reading])));

    final readingRect = tester.getRect(find.text('Reading Book'));
    final newRect = tester.getRect(find.text('New Book'));
    expect(readingRect.left, lessThan(newRect.left),
        reason: 'reading book should render to the left of the new book');
  });

  testWidgets(
      'carousel shows when reading books exist even in a small library',
      (tester) async {
    // Library of 3 books, well below _minLibrarySize = 10. Without a reading
    // book this would auto-hide.
    await tester.pumpWidget(buildHarness([
      readingBook(id: 1, title: 'Reading'),
      oldBook(id: 2, title: 'Old 1'),
      oldBook(id: 3, title: 'Old 2'),
    ]));

    expect(find.text('Recently added'), findsOneWidget);
    expect(find.text('Reading'), findsOneWidget);
  });

  testWidgets('NEW badge appears on recently-added books', (tester) async {
    await tester.pumpWidget(buildHarness(withPad([
      newBook(id: 1, title: 'Fresh Book'),
    ])));

    expect(find.text('NEW'), findsOneWidget);
  });

  testWidgets('NEW badge does not appear on currently-reading books',
      (tester) async {
    // Reading AND recent-addedAt: we should see the reading status badge,
    // not the NEW badge.
    await tester.pumpWidget(buildHarness(withPad([
      Book(
        id: 1,
        title: 'Active',
        readingStatus: 'reading',
        addedAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    ])));

    expect(find.text('NEW'), findsNothing);
  });

  testWidgets('D+N badge appears on reading books with startedReadingAt',
      (tester) async {
    await tester.pumpWidget(buildHarness([
      readingBook(
        id: 1,
        title: 'Ongoing',
        startedAt: DateTime.now().subtract(const Duration(days: 5)),
      ),
      oldBook(id: 2, title: 'Old'),
      oldBook(id: 3, title: 'Old2'),
    ]));

    expect(find.text('D+5'), findsOneWidget);
  });

  testWidgets('D+N badge caps at 99+ for long reads', (tester) async {
    await tester.pumpWidget(buildHarness([
      readingBook(
        id: 1,
        title: 'Slow',
        startedAt: DateTime.now().subtract(const Duration(days: 365)),
      ),
      oldBook(id: 2, title: 'Old'),
      oldBook(id: 3, title: 'Old2'),
    ]));

    expect(find.text('D+99+'), findsOneWidget);
  });

  testWidgets('D+N badge absent when startedReadingAt is today',
      (tester) async {
    await tester.pumpWidget(buildHarness([
      readingBook(
        id: 1,
        title: 'Fresh read',
        startedAt: DateTime.now(),
      ),
      oldBook(id: 2, title: 'Old'),
      oldBook(id: 3, title: 'Old2'),
    ]));

    expect(find.textContaining('D+'), findsNothing);
  });

  testWidgets('D+N badge absent when startedReadingAt is null',
      (tester) async {
    await tester.pumpWidget(buildHarness([
      readingBook(id: 1, title: 'Unknown start'),
      oldBook(id: 2, title: 'Old'),
      oldBook(id: 3, title: 'Old2'),
    ]));

    expect(find.textContaining('D+'), findsNothing);
  });
}
