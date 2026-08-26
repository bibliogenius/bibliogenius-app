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
import 'package:bibliogenius/screens/recommendations_screen.dart';
import 'package:bibliogenius/services/curated_lists_service.dart';
import 'package:bibliogenius/services/recommendation_dismissal_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/curated_list_suggestion_card.dart';
import 'package:bibliogenius/widgets/suggestion_tile.dart';

import '../helpers/mock_repositories.dart';

/// Serves a canned payload; the screen only ever reads the provider cache.
class _FakeRepository implements RecommendationRepository {
  _FakeRepository(this.payload, {this.inputs});

  final PersonalRecommendations? payload;

  /// The identity index the editorial tier measures against (ADR-066). Null
  /// is the profile floor, where the tier returns nothing at all.
  final DiscoveryLookupInputs? inputs;

  @override
  Future<List<Recommendation>> getBookRecommendations(
    String bookId, {
    int? limit,
  }) async => const [];

  @override
  Future<PersonalRecommendations?> getPersonalRecommendations({
    int? limit,
  }) async => payload;

  @override
  Future<DiscoveryLookupInputs?> getDiscoveryLookupInputs() async => inputs;
}

Recommendation _suggestion(String title) {
  return Recommendation(
    book: Book(id: 'book-$title', title: title, author: 'Albert Camus'),
    score: 1,
    reasons: const [
      RecommendationReason(type: 'same_author', value: 'Albert Camus'),
    ],
  );
}

const _ownedIsbns = {'9782070541270', '9780306406157', '9780441007318'};

/// Three books in common of ten, which is what the ADR-066 gate asks for.
CuratedList _eligibleList() => CuratedList(
  id: 'goncourt',
  version: 1,
  title: const {'en': 'Goncourt winners'},
  description: const {'en': ''},
  tags: const [],
  contentLanguages: const ['en'],
  curationStatus: CuratedList.curationReviewed,
  books: [
    for (final isbn in _ownedIsbns) CuratedBook(isbn: isbn, note: 'Owned'),
    for (var i = 0; i < 7; i++)
      CuratedBook(isbn: '978999900000$i', note: 'Rest $i'),
  ],
);

Widget _harness({
  required ThemeProvider theme,
  required List<Recommendation> suggestions,
  List<CuratedList> corpus = const [],
}) {
  final provider = RecommendationProvider(
    _FakeRepository(
      PersonalRecommendations(
        recommendations: suggestions,
        topSubjects: const [],
        favoriteAuthors: const [],
        scoredBooksCount: 12,
      ),
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

  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<RecommendationProvider>.value(value: provider),
      ],
      child: const RecommendationsScreen(),
    ),
  );
}

void main() {
  late ThemeProvider theme;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'recommendations_personal': 'Suggestions for you',
        'recommendations_empty': 'No suggestions right now',
        'reason_same_author': 'Same author: {value}',
        'reason_same_author_short': 'Same author',
        'recommendation_not_interested': 'Not interested',
        'recommendation_dismissed': 'Suggestion hidden',
        'action_undo': 'Undo',
        'suggestion_badge_editorial': 'Selection',
        'curated_affinity_reason': '{owned} books in common',
      },
    });
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  testWidgets('renders the complete list, beyond the dashboard digest cap', (
    tester,
  ) async {
    final titles = ['A', 'B', 'C', 'D', 'E', 'F', 'G'];
    await tester.pumpWidget(
      _harness(
        theme: theme,
        suggestions: [for (final t in titles) _suggestion(t)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Suggestions for you'), findsOneWidget);
    for (final t in titles) {
      expect(
        find.text(t),
        findsOneWidget,
        reason: 'the full ranked list shows every suggestion, not a digest',
      );
    }
  });

  group('curated list rows (ADR-066)', () {
    testWidgets('a list joins the column, after the books', (tester) async {
      await tester.pumpWidget(
        _harness(
          theme: theme,
          suggestions: [_suggestion('A'), _suggestion('B')],
          corpus: [_eligibleList()],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CuratedListSuggestionCard), findsOneWidget);
      expect(find.text('Goncourt winners'), findsOneWidget);
      expect(find.text('3 books in common'), findsOneWidget);

      // Last row of the ONE column, never a section of its own: the page's
      // blended-list position (ADR-060) holds for lists too.
      final lastBook = tester.getRect(find.text('B'));
      final list = tester.getRect(find.text('Goncourt winners'));
      expect(list.top, greaterThan(lastBook.top));

      // And on the column's grid, so the separators cut at one place.
      final row = tester.getRect(find.byType(CuratedListSuggestionCard));
      expect(list.left - row.left, SuggestionTile.textOffset);
    });

    testWidgets('a list can never make the page non-empty on its own', (
      tester,
    ) async {
      // Same rule as the library strip: "Suggestions for you" is a page
      // about books, and a column made only of selections is a different
      // feature from the one the page names.
      await tester.pumpWidget(
        _harness(
          theme: theme,
          suggestions: const [],
          corpus: [_eligibleList()],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No suggestions right now'), findsOneWidget);
      expect(find.byType(CuratedListSuggestionCard), findsNothing);
    });

    testWidgets('the close button hides the row, and Undo restores it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          theme: theme,
          suggestions: [_suggestion('A')],
          corpus: [_eligibleList()],
        ),
      );
      await tester.pumpAndSettle();

      // The book tile carries the same tooltip, so target the list's own.
      await tester.tap(
        find.descendant(
          of: find.byType(CuratedListSuggestionCard),
          matching: find.byTooltip('Not interested'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CuratedListSuggestionCard), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.byType(CuratedListSuggestionCard), findsOneWidget);
    });
  });

  testWidgets('"Not interested" hides the tile and Undo restores it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        theme: theme,
        suggestions: [
          _suggestion('La Peste'),
          _suggestion('Le Mythe de Sisyphe'),
          _suggestion('Caligula'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Not interested').last);
    await tester.pumpAndSettle();

    expect(find.text('Caligula'), findsNothing);
    expect(find.text('Suggestion hidden'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Caligula'), findsOneWidget);
  });

  testWidgets('a dismissal persisted on a previous launch stays filtered', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      RecommendationDismissalService.dismissedBookIdsKey: ['book-Caligula'],
    });

    await tester.pumpWidget(
      _harness(
        theme: theme,
        suggestions: [_suggestion('La Peste'), _suggestion('Caligula')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Caligula'), findsNothing);
    expect(find.text('La Peste'), findsOneWidget);
  });

  testWidgets('says so instead of a blank page when everything is dismissed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        theme: theme,
        suggestions: [_suggestion('La Peste'), _suggestion('Caligula')],
      ),
    );
    await tester.pumpAndSettle();

    // Unlike the dashboard digest, the screen has no two-suggestion floor:
    // dismissing everything leaves an explicit empty state, not a blank.
    await tester.tap(find.byTooltip('Not interested').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Not interested').first);
    await tester.pumpAndSettle();

    expect(find.text('No suggestions right now'), findsOneWidget);
  });
}
