import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/collection_repository.dart';
import 'package:bibliogenius/data/repositories/recommendation_repository.dart';
import 'package:bibliogenius/models/collection.dart';
import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/recommendation_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/collection/collection_list_screen.dart';
import 'package:bibliogenius/services/curated_lists_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/collection_stack_widget.dart';
import 'package:bibliogenius/widgets/curated_list_suggestion_card.dart';

import '../helpers/mock_repositories.dart';

/// ADR-066 second surface: the Collections screen.
///
/// Verified state this fills: the prominent "discover collections" banner
/// exists in the EMPTY state only, and the populated state offers nothing
/// but the app-bar pill, which the tab-view branch does not even render.
/// The block therefore lands in the populated state, after the reader's own
/// collections, and never when there is nothing to say.

class _FakeRepository implements RecommendationRepository {
  _FakeRepository(this.inputs);

  final DiscoveryLookupInputs inputs;

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
  Future<DiscoveryLookupInputs?> getDiscoveryLookupInputs() async => inputs;
}

const _ownedIsbns = {'9782070541270', '9780306406157', '9780441007318'};

CuratedList _eligibleList({
  String id = 'goncourt',
  String title = 'Goncourt winners',
}) => CuratedList(
  id: id,
  version: 1,
  title: {'en': title, 'fr': title},
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

Collection _collection(String id) => Collection(
  id: id,
  name: 'My collection $id',
  source: 'manual',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'curated_affinity_section_title': 'Selections for your library',
        'curated_affinity_reason': '{owned} books in common',
        'curated_affinity_reason_liked':
            '{owned} books in common, {liked} of them liked',
        'suggestion_badge_editorial': 'Selection',
        'no_collections': 'No collections',
        'collection_empty_state_desc': 'Create one',
        'create_collection': 'Create a collection',
        'discover_collections_title': 'Discover collections',
        'discover_collections_subtitle': 'Curated selections',
        'explore_collections': 'Explore',
        'displayed_collections_count': '%d collection',
        'displayed_collections_count_plural': '%d collections',
        'collection_group_books_count': 'books',
      },
    });
  });

  Future<RecommendationProvider> pumpScreen(
    WidgetTester tester, {
    required List<Collection> collections,
    List<CuratedList> corpus = const [],
  }) async {
    final provider = RecommendationProvider(
      _FakeRepository(
        const DiscoveryLookupInputs(
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
    await provider.loadCuratedAffinity(readerLanguages: const ['en']);

    final repository = MockCollectionRepository()
      ..mockCollections = collections;

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>(
              create: (_) => ThemeProvider(),
            ),
            ChangeNotifierProvider<RecommendationProvider>.value(
              value: provider,
            ),
            ChangeNotifierProvider<BookRefreshNotifier>(
              create: (_) => BookRefreshNotifier(),
            ),
            Provider<CollectionRepository>.value(value: repository),
          ],
          child: const CollectionListScreen(isTabView: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return provider;
  }

  testWidgets('the block sits after the reader own collections', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(
      tester,
      collections: [_collection('a'), _collection('b')],
      corpus: [_eligibleList()],
    );

    expect(find.text('Selections for your library'), findsOneWidget);
    expect(find.byType(CuratedListSuggestionCard), findsOneWidget);

    final lastOwn = tester
        .getBottomLeft(find.byType(CollectionCoverCard).last)
        .dy;
    final header = tester
        .getTopLeft(find.text('Selections for your library'))
        .dy;
    expect(
      header,
      greaterThan(lastOwn),
      reason: "The reader's own collections always render first.",
    );
  });

  testWidgets('the cards ride a horizontal strip, in the Activity shape', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(
      tester,
      collections: [_collection('a')],
      corpus: [
        _eligibleList(),
        _eligibleList(id: 'renaudot', title: 'Renaudot winners'),
      ],
    );

    final cards = find.byType(CuratedListSuggestionCard);
    expect(cards, findsNWidgets(2));

    final first = tester.getRect(cards.at(0));
    final second = tester.getRect(cards.at(1));
    expect(
      second.top,
      first.top,
      reason: 'One scrollable row, like the Activity strip, never a stack.',
    );
    expect(second.left, greaterThan(first.left));

    // The page's own vocabulary: the name sits UNDER the artwork and spans
    // the card, instead of fighting a square mosaic for a text column two
    // words wide. On the library slot the same card keeps its strip shape.
    final title = tester.getRect(find.text('Goncourt winners'));
    expect(title.width, greaterThan(first.width - 8));
    expect(
      title.top,
      greaterThan(first.top + first.height / 2),
      reason: 'The artwork takes the top of the card, the name follows it.',
    );

    // And none of the collection cards' accounting comes with the fan: no
    // count badge, no progress pill. "3/10" would read as a collection the
    // reader is a third through, not a list they own three books of.
    expect(find.text('3/10'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('below the thresholds the body stays clean', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester, collections: [_collection('a')], corpus: const []);

    // Never an empty or lukewarm block: no header over zero cards.
    expect(find.text('Selections for your library'), findsNothing);
    expect(find.byType(CuratedListSuggestionCard), findsNothing);
    expect(find.byType(CollectionCoverCard), findsOneWidget);
  });

  testWidgets('the empty-state banner is untouched and carries no block', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester, collections: const [], corpus: [_eligibleList()]);

    // The banner is onboarding and stays exactly as it was; the teaser
    // block belongs to the populated state only.
    expect(find.text('Discover collections'), findsOneWidget);
    expect(find.text('Selections for your library'), findsNothing);
    expect(find.byType(CuratedListSuggestionCard), findsNothing);
  });

  testWidgets('a dismissed list leaves the screen without a block', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final provider = await pumpScreen(
      tester,
      collections: [_collection('a')],
      corpus: [_eligibleList()],
    );
    expect(find.byType(CuratedListSuggestionCard), findsOneWidget);

    await provider.dismissExternal('list:goncourt');
    await tester.pumpAndSettle();

    expect(find.byType(CuratedListSuggestionCard), findsNothing);
    expect(find.text('Selections for your library'), findsNothing);
  });
}
