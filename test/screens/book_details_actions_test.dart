import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/audio/providers/audio_provider.dart';
import 'package:bibliogenius/data/repositories/book_repository.dart';
import 'package:bibliogenius/data/repositories/collection_repository.dart';
import 'package:bibliogenius/data/repositories/contact_repository.dart';
import 'package:bibliogenius/data/repositories/copy_repository.dart';
import 'package:bibliogenius/data/repositories/loan_repository.dart';
import 'package:bibliogenius/data/repositories/recommendation_repository.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/copy.dart';
import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/providers/book_note_provider.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/favorites_provider.dart';
import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/ownership_preference_provider.dart';
import 'package:bibliogenius/providers/recommendation_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/book_details_screen.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/utils/book_filters.dart';

import '../helpers/mock_classes.dart';
import '../helpers/mock_repositories.dart';

/// Action-area cover for the book detail page.
///
/// What it pins, all of it lost or wrong before: the reading cycle has a
/// button at all (its handlers were dead code and the only way in was the
/// status picker), that button is ALONE and follows the book's state, lending
/// stays reachable beside it without depending on the reading status, and the
/// destructive and fine-print controls left the page body for the app bar
/// menu. It also pins the tap-target floor on what remains in the body.
class _FakeRecommendationRepository implements RecommendationRepository {
  @override
  Future<List<Recommendation>> getBookRecommendations(
    String bookId, {
    int? limit,
  }) async => const [];

  @override
  Future<PersonalRecommendations?> getPersonalRecommendations({
    int? limit,
  }) async => null;

  @override
  Future<DiscoveryLookupInputs?> getDiscoveryLookupInputs() async => null;
}

/// An ISBN lookup that comes back empty, as it does for an edition no source
/// has indexed yet.
class _NoMetadataApiService extends MockApiService {
  @override
  Future<Map<String, String?>?> lookupBookMetadata(
    String isbn, {
    String? lang,
  }) async => null;
}

const _catalogue = {
  'en': {
    'start_reading': 'Start Reading',
    'mark_as_finished': 'Mark as Finished',
    'give_back_book_btn': 'Give this book back',
    'borrow_from_contact_btn': 'Borrow from a contact',
    'lend_book_btn': 'Lend',
    'borrow': 'Borrow',
    'return_book_btn': 'Return',
    'menu_edit': 'Edit',
    'menu_copies_short': 'Copies',
    'menu_manage_copies': 'Manage copies',
    'read_more': 'Read more',
    'read_less': 'Show less',
    'book_summary': 'Summary',
    'book_not_found': 'Book not found',
    'retry': 'Retry',
    'started_on': 'Started',
    'finished_on': 'Finished',
    'menu_delete': 'Delete',
    'refresh_metadata_title': 'Update',
    'refresh_metadata_not_found': 'No data found for this ISBN',
    'cover_search_by_title_short': 'By title',
    'book_visibility': 'Visibility',
    'book_visibility_public': 'Public',
    'book_visibility_public_desc': 'Visible to your contacts',
    'book_visibility_not_lendable': 'Public, not for loan',
    'book_visibility_not_lendable_desc': 'Never offered for loan',
    'book_private': 'Private book',
    'own_this_book': 'I own this book',
    'book_ownership': 'Ownership',
    'book_ownership_not_owned': 'I do not own this book',
    'book_ownership_delete_copies': 'Its {count} copies will be deleted.',
    'book_ownership_leaves_wishlist': 'The book will leave your wishlist.',
    'book_ownership_release_blocked': 'A copy is out.',
    'book_private_desc': 'Hidden from the network',
    'coming_soon': 'Coming soon',
    'more_actions': 'More',
    'back': 'Back',
    'currently_reading': 'Reading',
    'to_read_status': 'To read',
    'read_status': 'Read',
    'wishlist_status': 'Wanted',
    'no_reading_status': 'No status',
    'reading_status_abandoned': 'Abandoned',
    'date_select_option_today': 'Today',
    'date_select_option_pick': 'Pick a date',
    'date_select_option_none': 'No date',
    'status_updated': 'Status updated',
    'status_change_ownership_title': 'Is this book on your shelves?',
    'status_change_ownership_yes_desc': 'It joins "All my books".',
    'status_change_ownership_no_desc': 'It stays under its reading status.',
    'status_change_ownership_show_all': 'Show everything in my library',
    'status_change_ownership_show_all_desc': 'Owned or not, together.',
  },
};

Copy _copy(String id, String status) => Copy(
  id: id,
  bookId: 'b1',
  libraryId: 1,
  status: status,
  isTemporary: false,
);

/// WCAG 2.1 contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final la = luminance(a);
  final lb = luminance(b);
  final light = la > lb ? la : lb;
  final dark = la > lb ? lb : la;
  return (light + 0.05) / (dark + 0.05);
}

void main() {
  late ThemeProvider theme;
  late MockBookRepository books;
  late MockCopyRepository copies;
  late MockCollectionRepository collections;
  late MockContactRepository contacts;
  late MockLoanRepository loans;
  late OwnershipPreferenceProvider ownershipPrefs;

  Widget _wrap(Widget child) {
    final favorites = FavoritesProvider(collections, BookRefreshNotifier());
    final recommendations = RecommendationProvider(
      _FakeRecommendationRepository(),
      BookRefreshNotifier(),
    );

    // The providers sit ABOVE MaterialApp on purpose, as they do in
    // main.dart: a modal bottom sheet is pushed on the root navigator, so a
    // provider scoped under `home` is not visible from inside the sheet.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<OwnershipPreferenceProvider>.value(
          value: ownershipPrefs,
        ),
        ChangeNotifierProvider<FavoritesProvider>.value(value: favorites),
        ChangeNotifierProvider<RecommendationProvider>.value(
          value: recommendations,
        ),
        Provider<ApiService>.value(value: _NoMetadataApiService()),
        Provider<BookRepository>.value(value: books),
        Provider<CopyRepository>.value(value: copies),
        Provider<CollectionRepository>.value(value: collections),
        Provider<ContactRepository>.value(value: contacts),
        Provider<LoanRepository>.value(value: loans),
        Provider<RecommendationRepository>.value(
          value: _FakeRecommendationRepository(),
        ),
        // Two sections of the page own their state: the audio module and
        // the reading notes. Neither is under test here, both must be able
        // to build.
        ChangeNotifierProvider<AudioProvider>(create: (_) => AudioProvider()),
        ChangeNotifierProvider<BookNoteProvider>(
          create: (_) => BookNoteProvider(),
        ),
        // A wished book renders the acquisition cards, which reach for the
        // hub directory. The FFI is not up under test, so they render
        // nothing, which is all this suite needs from them.
        ChangeNotifierProvider<HubDirectoryProvider>(
          create: (_) => HubDirectoryProvider(ffi: FfiService()),
        ),
      ],
      child: MaterialApp(home: child),
    );
  }

  /// The page reached by id alone, as a deep link or a loan row does it.
  Widget harnessById(String bookId) => _wrap(BookDetailsScreen(bookId: bookId));

  Widget harness(Book book) {
    // The screen re-fetches on open; without this the mock throws and the
    // page never leaves its spinner.
    books.mockBook = book;
    return _wrap(BookDetailsScreen(book: book, bookId: book.id!));
  }



  /// Settles without `pumpAndSettle`: the page carries lazy discovery sections
  /// whose futures never complete under test, and the header animates.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({'languageCode': 'en'});
    theme = ThemeProvider()..setLocaleSync(const Locale('en'));
    books = MockBookRepository();
    copies = MockCopyRepository();
    collections = MockCollectionRepository();
    contacts = MockContactRepository();
    loans = MockLoanRepository();
    ownershipPrefs = OwnershipPreferenceProvider();
    TranslationService.setPoTranslationsForTest(_catalogue);
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  Book book({
    String? readingStatus,
    bool owned = true,
    bool private = false,
    String? summary,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? isbn,
  }) => Book(
    id: 'b1',
    title: 'The Anomaly',
    author: 'Herve Le Tellier',
    isbn: isbn,
    readingStatus: readingStatus,
    owned: owned,
    private: private,
    summary: summary,
    startedReadingAt: startedAt,
    finishedReadingAt: finishedAt,
  );

  testWidgets('an unread book offers to start reading, and only that', (
    tester,
  ) async {
    copies.mockCopies = [_copy('c1', 'available')];
    await tester.pumpWidget(harness(book(readingStatus: 'to_read')));
    await settle(tester);

    expect(find.byKey(const Key('bookPrimaryActionButton')), findsOneWidget);
    expect(find.text('Start Reading'), findsOneWidget);
    expect(find.text('Mark as Finished'), findsNothing);
  });

  testWidgets('a book being read offers to finish it', (tester) async {
    copies.mockCopies = [_copy('c1', 'available')];
    await tester.pumpWidget(harness(book(readingStatus: 'reading')));
    await settle(tester);

    expect(find.text('Mark as Finished'), findsOneWidget);
    expect(find.text('Start Reading'), findsNothing);
  });

  testWidgets('a finished book has no primary button at all', (tester) async {
    copies.mockCopies = [_copy('c1', 'available')];
    await tester.pumpWidget(harness(book(readingStatus: 'read')));
    await settle(tester);

    expect(find.byKey(const Key('bookPrimaryActionButton')), findsNothing);
  });

  testWidgets('lending is offered whatever the reading status, and unrated', (
    tester,
  ) async {
    // The rating never enters the ranking: an unrated finished book must still
    // offer the loan, beside a page that has no primary button left.
    for (final status in ['to_read', 'reading', 'read']) {
      copies.mockCopies = [_copy('c1', 'available')];
      await tester.pumpWidget(harness(book(readingStatus: status)));
      await settle(tester);

      expect(
        find.text('Lend'),
        findsOneWidget,
        reason: 'lending disappeared on status $status',
      );
    }
  });

  testWidgets('a borrowed copy outranks the reading step', (tester) async {
    copies.mockCopies = [_copy('c1', 'borrowed')];
    await tester.pumpWidget(harness(book(readingStatus: 'reading')));
    await settle(tester);

    expect(find.text('Give this book back'), findsOneWidget);
    expect(find.text('Mark as Finished'), findsNothing);
  });

  testWidgets('delete and update left the page body for the bar menu', (
    tester,
  ) async {
    copies.mockCopies = [_copy('c1', 'available')];
    await tester.pumpWidget(harness(book(readingStatus: 'to_read')));
    await settle(tester);

    // Nothing in the body: they used to be two ~28px text buttons pressed
    // against each other, one of them destructive.
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Update'), findsNothing);

    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
  });

  testWidgets('the menu icons are legible on the menu, not on the app bar', (
    tester,
  ) async {
    // PopupMenuButton captures the inherited themes of the button's context,
    // and this button lives in the app bar, whose IconTheme is white. Icons
    // left to inherit came out white on the menu's light surface.
    copies.mockCopies = [_copy('c1', 'available')];
    await tester.pumpWidget(harness(book(readingStatus: 'to_read')));
    await settle(tester);

    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final surface = theme.themeData.colorScheme.surface;
    for (final glyph in [
      Icons.library_books_outlined,
      Icons.refresh_outlined,
      Icons.visibility,
      Icons.delete_outline,
    ]) {
      final icon = tester.widget<Icon>(find.byIcon(glyph).first);
      expect(icon.color, isNotNull, reason: '$glyph inherits its colour');
      expect(
        _contrast(icon.color!, surface),
        greaterThanOrEqualTo(3.0),
        reason: '$glyph is not legible on the menu surface',
      );
    }
  });

  testWidgets('visibility is a ladder whose third rung is not ready yet', (
    tester,
  ) async {
    // allowPrivateBooks already defaults to true; calling its setter here
    // would drag ApiService and dotenv into a widget test.
    copies.mockCopies = [_copy('c1', 'available')];
    await tester.pumpWidget(harness(book(readingStatus: 'to_read')));
    await settle(tester);

    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Visibility'));
    // The menu dismisses before the sheet opens: two animations back to back.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Public'), findsOneWidget);
    expect(find.text('Private book'), findsOneWidget);

    // Present and disabled: drawing this as a two-state switch today would
    // mean rebuilding the control when the hub learns to carry availability.
    final rung = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Public, not for loan'),
        matching: find.byType(ListTile),
      ),
    );
    expect(rung.enabled, isFalse);
  });

  testWidgets('copies are navigation, not one of the actions', (tester) async {
    // A single copy needs no management surface on the page at all; the entry
    // stays in the bar menu, with the other places to go.
    copies.mockCopies = [_copy('c1', 'available')];
    await tester.pumpWidget(harness(book(readingStatus: 'to_read')));
    await settle(tester);

    expect(find.byKey(const Key('manageCopiesButton')), findsNothing);

    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Manage copies'), findsOneWidget);
  });

  testWidgets('a second copy earns its own quiet line', (tester) async {
    copies.mockCopies = [_copy('c1', 'available'), _copy('c2', 'available')];
    await tester.pumpWidget(harness(book(readingStatus: 'to_read')));
    await settle(tester);

    final line = find.byKey(const Key('manageCopiesButton'));
    expect(line, findsOneWidget);
    expect(find.text('2 copies'), findsOneWidget);
    expect(tester.getSize(line).height, greaterThanOrEqualTo(44));
  });

  testWidgets('the actions sit two per row, never one ragged per line', (
    tester,
  ) async {
    copies.mockCopies = [_copy('c1', 'available')];
    await tester.pumpWidget(harness(book(readingStatus: 'to_read')));
    await settle(tester);

    final edit = tester.getRect(
      find.ancestor(
        of: find.text('Edit'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    final lend = tester.getRect(
      find.ancestor(
        of: find.text('Lend'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(
      edit.top,
      closeTo(lend.top, 0.5),
      reason: 'Edit and Lend are both actions and belong on the same row',
    );
  });

  Future<void> openOwnership(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('I own this book'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('releasing ownership says what it will delete', (tester) async {
    copies.mockCopies = [_copy('c1', 'available'), _copy('c2', 'available')];
    await tester.pumpWidget(harness(book(readingStatus: 'to_read')));
    await settle(tester);

    await openOwnership(tester);

    // The consequence is on the option, not discovered afterwards.
    expect(find.text('Its 2 copies will be deleted.'), findsOneWidget);
  });

  testWidgets('a lent copy blocks the release, with its reason', (
    tester,
  ) async {
    copies.mockCopies = [_copy('c1', 'loaned')];
    await tester.pumpWidget(harness(book(readingStatus: 'to_read')));
    await settle(tester);

    await openOwnership(tester);

    final rung = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('I do not own this book'),
        matching: find.byType(ListTile),
      ),
    );
    expect(
      rung.enabled,
      isFalse,
      reason: 'deleting a lent copy leaves the loan pointing at nothing',
    );
    expect(find.text('A copy is out.'), findsOneWidget);
  });

  testWidgets('a borrowed copy blocks claiming ownership', (tester) async {
    copies.mockCopies = [_copy('c1', 'borrowed')];
    await tester.pumpWidget(harness(book(readingStatus: 'reading', owned: false)));
    await settle(tester);

    await openOwnership(tester);

    final rung = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('I own this book').last,
        matching: find.byType(ListTile),
      ),
    );
    expect(rung.enabled, isFalse);
  });

  testWidgets('a wished book is told it will leave the wishlist', (
    tester,
  ) async {
    copies.mockCopies = [];
    await tester.pumpWidget(
      harness(book(readingStatus: 'wanting', owned: false)),
    );
    await settle(tester);

    await openOwnership(tester);

    expect(find.text('The book will leave your wishlist.'), findsOneWidget);
  });

  /// Starts reading through the primary button and picks today's date, which
  /// is where the possession question fires, or must not.
  Future<void> startReadingToday(WidgetTester tester) async {
    await tester.tap(find.text('Start Reading'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Today'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a book the reader does not have is asked about possession', (
    tester,
  ) async {
    // A wish marked read used to leave "All my books" silently: the status
    // never touched `owned`, and the default view is possession (ADR-063).
    copies.mockCopies = [];
    await tester.pumpWidget(
      harness(book(readingStatus: 'to_read', owned: false)),
    );
    await settle(tester);

    await startReadingToday(tester);

    expect(find.text('Is this book on your shelves?'), findsOneWidget);
    expect(
      books.lastUpdate,
      isNull,
      reason: 'the question comes before the write, so the two land together',
    );

    await tester.tap(find.byKey(const Key('ownershipAfterStatusYes')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(books.lastUpdate!['reading_status'], 'reading');
    expect(books.lastUpdate!['owned'], isTrue);
    expect(copies.createdCopies, hasLength(1));
  });

  testWidgets('declining possession still applies the status', (tester) async {
    copies.mockCopies = [];
    await tester.pumpWidget(
      harness(book(readingStatus: 'to_read', owned: false)),
    );
    await settle(tester);

    await startReadingToday(tester);
    await tester.tap(find.byKey(const Key('ownershipAfterStatusNo')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(books.lastUpdate!['reading_status'], 'reading');
    expect(books.lastUpdate!.containsKey('owned'), isFalse);
    expect(copies.createdCopies, isEmpty);
  });

  testWidgets('the first question is about the book alone', (tester) async {
    copies.mockCopies = [];
    await tester.pumpWidget(
      harness(book(readingStatus: 'to_read', owned: false)),
    );
    await settle(tester);

    await startReadingToday(tester);

    // One book read without owning it is an anecdote, not a habit: the
    // row that widens the whole library is not offered yet.
    expect(find.byKey(const Key('ownershipAfterStatusShowAll')), findsNothing);

    await tester.tap(find.byKey(const Key('ownershipAfterStatusNo')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(ownershipPrefs.hasDeclinedOwnership, isTrue);
  });

  testWidgets('from the second declined book on, widening the view is offered', (
    tester,
  ) async {
    copies.mockCopies = [];
    await ownershipPrefs.markOwnershipDeclined();
    await tester.pumpWidget(
      harness(book(readingStatus: 'to_read', owned: false)),
    );
    await settle(tester);

    await startReadingToday(tester);
    await tester.tap(find.byKey(const Key('ownershipAfterStatusShowAll')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(ownershipPrefs.scope, OwnershipScope.all);
    // The book itself is untouched: the status lands, possession does not.
    expect(books.lastUpdate!['reading_status'], 'reading');
    expect(books.lastUpdate!.containsKey('owned'), isFalse);
    expect(copies.createdCopies, isEmpty);
  });

  testWidgets('a view that shows everything is never asked', (tester) async {
    copies.mockCopies = [];
    await ownershipPrefs.setScope(OwnershipScope.all);
    await tester.pumpWidget(
      harness(book(readingStatus: 'to_read', owned: false)),
    );
    await settle(tester);

    await startReadingToday(tester);

    expect(find.text('Is this book on your shelves?'), findsNothing);
    expect(books.lastUpdate!['reading_status'], 'reading');
  });

  testWidgets('an owned book is not asked about possession', (tester) async {
    copies.mockCopies = [_copy('c1', 'available')];
    await tester.pumpWidget(harness(book(readingStatus: 'to_read')));
    await settle(tester);

    await startReadingToday(tester);

    expect(find.text('Is this book on your shelves?'), findsNothing);
    expect(books.lastUpdate!['reading_status'], 'reading');
    expect(books.lastUpdate!.containsKey('owned'), isFalse);
  });

  testWidgets('a long summary is clamped until the reader asks for more', (
    tester,
  ) async {
    // A fifteen-line blurb used to render in full and push the notes and the
    // suggestions far below the fold on every book that had one.
    copies.mockCopies = [_copy('c1', 'available')];
    final long = List.filled(60, 'Une phrase de resume assez longue.').join(' ');
    await tester.pumpWidget(
      harness(book(readingStatus: 'to_read', summary: long)),
    );
    await settle(tester);

    final toggle = find.byKey(const Key('summaryToggleButton'));
    expect(toggle, findsOneWidget);
    expect(find.text('Read more'), findsOneWidget);

    final clamped = tester.widget<Text>(find.text(long));
    expect(clamped.maxLines, 4);

    await tester.ensureVisible(toggle);
    await tester.pump();
    await tester.tap(toggle, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.widget<Text>(find.text(long)).maxLines, isNull);
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('a short summary carries no toggle at all', (tester) async {
    copies.mockCopies = [_copy('c1', 'available')];
    await tester.pumpWidget(
      harness(book(readingStatus: 'to_read', summary: 'Two words.')),
    );
    await settle(tester);

    expect(find.byKey(const Key('summaryToggleButton')), findsNothing);
  });

  testWidgets('the two reading dates share one row', (tester) async {
    copies.mockCopies = [_copy('c1', 'available')];
    await tester.pumpWidget(
      harness(
        book(
          readingStatus: 'read',
          startedAt: DateTime(2026, 8, 14),
          finishedAt: DateTime(2026, 8, 22),
        ),
      ),
    );
    await settle(tester);

    expect(
      tester.getRect(find.text('STARTED')).top,
      closeTo(tester.getRect(find.text('FINISHED')).top, 0.5),
      reason: 'a pair of dates costs one row, not two',
    );
  });

  testWidgets('a book that never loads says so, and offers a way out', (
    tester,
  ) async {
    // Reached from a deep link, a loan row or the statistics: the id is
    // known, the book is not. A failed fetch used to spin for ever in a
    // Scaffold with no app bar, so there was not even a way back.
    books.mockBook = null;
    await tester.pumpWidget(harnessById('missing'));
    await settle(tester);

    expect(find.text('Book not found'), findsOneWidget);
    expect(find.byKey(const Key('bookRetryButton')), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('the collapsed bar is opaque and its title is not white', (
    tester,
  ) async {
    // FlexibleSpaceBar fades its background out as the bar collapses. With a
    // transparent bar behind it the page scrolled under the toolbar and the
    // white title sat on top of the buttons going past.
    copies.mockCopies = [_copy('c1', 'available')];
    await tester.pumpWidget(harness(book(readingStatus: 'to_read')));
    await settle(tester);

    final bar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
    expect(bar.backgroundColor, isNotNull);
    expect(
      bar.backgroundColor!.a,
      1.0,
      reason: 'a see-through bar lets the page scroll under the title',
    );

    final title = tester.widget<Text>(find.text('The Anomaly').last);
    expect(
      title.style?.color,
      isNot(Colors.white),
      reason: 'the title only ever shows on the bar surface, never on a cover',
    );
  });

  testWidgets('every control left in the action area clears 44px', (
    tester,
  ) async {
    copies.mockCopies = [_copy('c1', 'available')];
    await tester.pumpWidget(harness(book(readingStatus: 'reading')));
    await settle(tester);

    for (final label in ['Mark as Finished', 'Edit', 'Lend']) {
      final button = find.ancestor(
        of: find.text(label),
        // byType matches the exact runtime type; these are subclasses.
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(button, findsOneWidget, reason: '"$label" is missing');
      expect(
        tester.getSize(button).height,
        greaterThanOrEqualTo(44),
        reason: '"$label" is under the tap target floor',
      );
    }
  });

  testWidgets('the ISBN dead end expires instead of following the reader', (
    tester,
  ) async {
    // The bar offers "By title", and Flutter pins any bar that carries an
    // action: its duration goes inert and, the messenger sitting above the
    // navigator, it stays on screen through the search it sends the reader
    // to. It has to say `persist: false` to expire like the others.
    copies.mockCopies = [_copy('c1', 'available')];
    await tester.pumpWidget(
      harness(book(readingStatus: 'to_read', isbn: '9782072895098')),
    );
    await settle(tester);

    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Update'));
    await settle(tester);

    expect(find.text('No data found for this ISBN'), findsOneWidget);
    expect(find.text('By title'), findsOneWidget);

    // The dismissal timer is armed once the entrance animation has finished,
    // then the bar's own eight seconds have to run out.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 9));
    await settle(tester);
    expect(find.text('No data found for this ISBN'), findsNothing);
  });
}
