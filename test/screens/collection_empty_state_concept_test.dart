import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/collection_repository.dart';
import 'package:bibliogenius/data/repositories/recommendation_repository.dart';
import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/recommendation_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/collection/collection_list_screen.dart';
import 'package:bibliogenius/services/translation_service.dart';

import '../helpers/mock_repositories.dart';

/// The empty Collections tab says what a collection is, against a shelf.
///
/// It used to describe collections alone ("gather every book of one author"),
/// which reads like a shelf. The two concepts now sit side by side with the
/// rule that tells them apart, the same sentences as the empty shelves tab.

class _EmptyRecommendations implements RecommendationRepository {
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

const _shelfConcept = 'Shelf: where you put a book.';
const _collectionConcept =
    'Collection: a list of books that belong together, in an order.';
const _rule = 'Does the order matter? A collection. Otherwise, a shelf.';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'no_collections': 'No collections',
        'shelf_concept': _shelfConcept,
        'collection_concept': _collectionConcept,
        'shelf_or_collection_rule': _rule,
        'create_collection': 'Create a collection',
        'discover_collections_title': 'Discover collections',
        'discover_collections_subtitle': 'Curated selections',
        'explore_collections': 'Explore',
      },
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  testWidgets('the empty tab tells a collection from a shelf', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final provider = RecommendationProvider(
      _EmptyRecommendations(),
      BookRefreshNotifier(),
      curatedCorpusLoader: () async => const [],
      bookRepository: MockBookRepository(),
    );
    final repository = MockCollectionRepository()..mockCollections = [];

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

    expect(find.text('No collections'), findsOneWidget);
    expect(find.text(_collectionConcept), findsOneWidget);
    expect(find.text(_shelfConcept), findsOneWidget);
    expect(find.text(_rule), findsOneWidget);
  });
}
