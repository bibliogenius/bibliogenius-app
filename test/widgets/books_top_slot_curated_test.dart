import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/recommendation_repository.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/recommendation_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/curated_lists_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/books_top_slot.dart';
import 'package:bibliogenius/widgets/compact_suggestion_card.dart';
import 'package:bibliogenius/widgets/curated_list_suggestion_card.dart';

import '../helpers/mock_repositories.dart';

/// ADR-066 in the ADR-062 slot: a curated list card JOINS the "To discover"
/// segment and can never create one. The segment's existence rule stays
/// exactly as ADR-062 wrote it, which is the strictest no-regression stance
/// available on a slot that shipped three weeks ago.

class _FakeRepository implements RecommendationRepository {
  _FakeRepository({this.personal, this.inputs});

  final PersonalRecommendations? personal;
  final DiscoveryLookupInputs? inputs;

  @override
  Future<List<Recommendation>> getBookRecommendations(
    String bookId, {
    int? limit,
  }) async => const [];

  @override
  Future<PersonalRecommendations?> getPersonalRecommendations({
    int? limit,
  }) async => personal;

  @override
  Future<DiscoveryLookupInputs?> getDiscoveryLookupInputs() async => inputs;
}

Recommendation _suggestion(String id) => Recommendation(
  book: Book(id: id, title: 'Book $id', author: 'An Author'),
  score: 1,
  reasons: const [RecommendationReason(type: 'same_author', value: 'An Author')],
);

PersonalRecommendations _payload(int count) => PersonalRecommendations(
  recommendations: [for (var i = 0; i < count; i++) _suggestion('s$i')],
  topSubjects: const [],
  favoriteAuthors: const [],
  scoredBooksCount: 12,
);

const _ownedIsbns = {'9782070541270', '9780306406157', '9780441007318'};

CuratedList _eligibleList() => CuratedList(
  id: 'goncourt',
  version: 1,
  title: const {'en': 'Goncourt winners', 'fr': 'Lauréats Goncourt'},
  description: const {'en': '', 'fr': ''},
  tags: const [],
  contentLanguages: const ['en', 'fr'],
  curationStatus: CuratedList.curationReviewed,
  books: [
    for (final isbn in _ownedIsbns)
      CuratedBook(isbn: isbn, note: 'Owned $isbn - An Author'),
    for (var i = 0; i < 7; i++)
      CuratedBook(isbn: '978999900000$i', note: 'Rest $i - Someone'),
  ],
);

/// A library with real activity, so the Activity segment exists too.
List<Book> _activeLibrary() => [
  Book(
    id: 'reading',
    title: 'Currently Reading',
    readingStatus: 'reading',
    startedReadingAt: DateTime.now().subtract(const Duration(days: 2)),
    addedAt: DateTime.now().subtract(const Duration(days: 300)),
  ),
  for (var i = 0; i < 20; i++)
    Book(
      id: 'old$i',
      title: 'Old $i',
      addedAt: DateTime.now().subtract(const Duration(days: 400)),
    ),
];

void main() {
  late ThemeProvider theme;

  Future<RecommendationProvider> pumpSlot(
    WidgetTester tester, {
    required int suggestionCount,
    List<CuratedList> corpus = const [],
  }) async {
    final provider = RecommendationProvider(
      _FakeRepository(
        personal: suggestionCount == 0 ? null : _payload(suggestionCount),
        inputs: const DiscoveryLookupInputs(
          series: [],
          authors: [],
          libraryIsbns: _ownedIsbns,
          libraryTitleAuthorKeys: {},
        ),
      ),
      BookRefreshNotifier(),
      curatedCorpusLoader: () async => corpus,
      bookRepository: MockBookRepository(),
    );
    await provider.loadPersonal();
    await provider.loadCuratedAffinity(readerLanguages: const ['en']);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>.value(value: theme),
            ChangeNotifierProvider<RecommendationProvider>.value(
              value: provider,
            ),
          ],
          child: Scaffold(body: BooksTopSlot(books: _activeLibrary())),
        ),
      ),
    );
    await tester.pump();
    return provider;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'books_slot_segment_activity': 'Activity',
        'books_slot_segment_discover': 'To discover · {count}',
        'books_slot_tab_discover': 'To discover',
        'recently_added_title': 'Recent activity',
        'carousel_collapse_tooltip': 'Collapse',
        'carousel_hide_long_press_tooltip': 'Long press to hide',
        'see_all_recommendations': 'See all',
        'reason_same_author': 'Same author: {value}',
        'recommendation_not_interested': 'Not interested',
        'curated_affinity_reason': '{owned} books in common',
        'curated_affinity_reason_liked':
            '{owned} books in common, {liked} of them liked',
        'suggestion_badge_editorial': 'Selection',
      },
    });
  });

  testWidgets('a list card joins an existing discovery segment', (
    tester,
  ) async {
    await pumpSlot(tester, suggestionCount: 3, corpus: [_eligibleList()]);
    theme.setBooksSlotShowsDiscovery(true);
    await tester.pump();

    expect(find.byType(CuratedListSuggestionCard), findsOneWidget);
    expect(find.byType(CompactSuggestionCard), findsWidgets);
  });

  testWidgets('it sits AFTER the book cards', (tester) async {
    await pumpSlot(tester, suggestionCount: 3, corpus: [_eligibleList()]);
    theme.setBooksSlotShowsDiscovery(true);
    await tester.pump();

    final lastBook = tester
        .getTopLeft(find.byType(CompactSuggestionCard).last)
        .dx;
    final listCard = tester
        .getTopLeft(find.byType(CuratedListSuggestionCard))
        .dx;
    expect(
      listCard,
      greaterThan(lastBook),
      reason:
          'The strip answers "what should I read next"; a whole selection '
          'is the broader offer and comes once the books have had a slot.',
    );
  });

  testWidgets('a list card can never CREATE the segment on its own', (
    tester,
  ) async {
    // One visible suggestion is below the ADR-059 floor, so there is no
    // discovery segment. An eligible list must not conjure one: the slot
    // would then be a list-only strip under a tab that promises books.
    await pumpSlot(tester, suggestionCount: 1, corpus: [_eligibleList()]);

    expect(find.byType(CuratedListSuggestionCard), findsNothing);
    expect(find.textContaining('To discover'), findsNothing);
  });

  testWidgets('no eligible list leaves the segment exactly as it was', (
    tester,
  ) async {
    await pumpSlot(tester, suggestionCount: 3, corpus: const []);
    theme.setBooksSlotShowsDiscovery(true);
    await tester.pump();

    expect(find.byType(CuratedListSuggestionCard), findsNothing);
    expect(find.byType(CompactSuggestionCard), findsWidgets);
    theme.setCarouselCollapsedOwnLib(true);
    await tester.pumpAndSettle();
    expect(find.text('To discover · 3'), findsOneWidget);
  });

  testWidgets('the collapsed count includes the list card the strip draws', (
    tester,
  ) async {
    // ADR-062 defect: the header once counted from a different base than
    // the strip and announced more covers than the reader could find. The
    // count now rides on the collapsed summary alone, which is the only
    // place with room for it, so that is where the rule is pinned.
    await pumpSlot(tester, suggestionCount: 3, corpus: [_eligibleList()]);
    theme.setBooksSlotShowsDiscovery(true);
    await tester.pump();
    expect(find.byType(CuratedListSuggestionCard), findsOneWidget);

    theme.setCarouselCollapsedOwnLib(true);
    await tester.pumpAndSettle();

    expect(find.text('To discover · 4'), findsOneWidget);
  });

  testWidgets('a dismissed list leaves the book suggestions untouched', (
    tester,
  ) async {
    final provider = await pumpSlot(
      tester,
      suggestionCount: 3,
      corpus: [_eligibleList()],
    );
    theme.setBooksSlotShowsDiscovery(true);
    await tester.pump();
    expect(find.byType(CuratedListSuggestionCard), findsOneWidget);

    await provider.dismissExternal('list:goncourt');
    await tester.pump();

    expect(find.byType(CuratedListSuggestionCard), findsNothing);
    expect(find.byType(CompactSuggestionCard), findsWidgets);
  });
}
