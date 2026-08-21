import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/recommendation_repository.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/recommendation_provider.dart';
import 'package:bibliogenius/services/discovery_service.dart';
import 'package:bibliogenius/services/external_suggestion_dismissal_service.dart';

/// ADR-060 section 4.4 blend inside the external tier: series completion
/// outranks author completion, at most two works per author, and a
/// dismissal promotes the next candidate of the same lookup instead of
/// leaving a hole.
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
  }) async => PersonalRecommendations(
    recommendations: [
      for (final title in ['Local A', 'Local B'])
        Recommendation(
          book: Book(id: 'book-$title', title: title, author: 'Someone'),
          score: 1,
          reasons: const [
            RecommendationReason(type: 'highly_rated', value: '5'),
          ],
        ),
    ],
    topSubjects: const [],
    favoriteAuthors: const [],
    scoredBooksCount: 12,
  );

  @override
  Future<DiscoveryLookupInputs?> getDiscoveryLookupInputs() async => inputs;
}

void main() {
  final inputs = DiscoveryLookupInputs(
    series: const [
      DiscoverySeriesLookup(
        collectionId: 'col-1',
        name: 'My Series',
        anchorIsbns: ['9782070541270'],
        memberIsbns: {},
        memberTitleAuthorKeys: {},
      ),
    ],
    authors: const [
      DiscoveryAuthorLookup(
        name: 'Albert Camus',
        anchorIsbns: ['9782070360024'],
      ),
    ],
    libraryIsbns: const {},
    libraryTitleAuthorKeys: const {},
  );

  Map<String, dynamic> seriesCache() => {
    'col-1': {
      // Fresh: the sweep stays inside the 24h throttle, so no network.
      'at': DateTime.now().millisecondsSinceEpoch,
      'status': 'resolved',
      'series': {
        'source': 'wikidata',
        'source_id': 'Q1',
        'label': 'My Series',
        'volumes': [
          {
            'ordinal': 2,
            'title': 'Missing Volume',
            'authors': ['J. K. Rowling'],
            'year': 2000,
            'editions': const [],
            'other_langs_exist': false,
          },
        ],
      },
    },
  };

  Map<String, dynamic> authorCache() => {
    'Albert Camus': {
      'at': DateTime.now().millisecondsSinceEpoch,
      'status': 'resolved',
      'author': {
        'source': 'wikidata',
        'source_id': 'Q34670',
        'label': 'Albert Camus',
        'works': [
          for (final (i, title) in [
            'The Plague',
            'The Fall',
            'A Happy Death',
          ].indexed)
            {
              'title': title,
              'titles': [title],
              'authors': ['Albert Camus'],
              'year': 1947,
              'editions_count': 40 - i,
              'editions': const [],
              'other_langs_exist': false,
            },
        ],
      },
    },
  };

  Future<RecommendationProvider> loadedProvider() async {
    final provider = RecommendationProvider(
      _FakeRepository(inputs),
      BookRefreshNotifier(),
      discoveryService: DiscoveryService(baseUrl: 'https://hub.test'),
    );
    await provider.loadPersonal();
    await provider.loadExternal(langs: const ['fr']);
    return provider;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({
      DiscoveryService.cacheKey: jsonEncode(seriesCache()),
      DiscoveryService.authorCacheKey: jsonEncode(authorCache()),
    });
  });

  test('series cards come first, then at most two works per author', () async {
    final provider = await loadedProvider();

    expect(
      provider.visibleExternal.map((c) => c.book.title),
      ['Missing Volume', 'The Plague', 'The Fall'],
      reason: 'series completion outranks author completion, 2 works max',
    );
    expect(
      provider.visibleExternal.first.reasons.first.type,
      'series_missing_volume',
    );
    expect(
      provider.visibleExternal[1].reasons.first.type,
      'author_completion',
    );
  });

  test('dismissing a work promotes the next one of the same author', () async {
    final provider = await loadedProvider();

    await provider.dismissExternal('author:Q34670:the plague');
    expect(
      provider.visibleExternal.map((c) => c.book.title),
      ['Missing Volume', 'The Fall', 'A Happy Death'],
    );

    await provider.restoreDismissedExternal('author:Q34670:the plague');
    expect(
      provider.visibleExternal.map((c) => c.book.title),
      ['Missing Volume', 'The Plague', 'The Fall'],
    );
  });

  test('an imported work leaves the list without waiting for a new lookup',
      () async {
    final provider = await loadedProvider();

    provider.hideExternalAfterImport('author:Q34670:the plague');
    expect(
      provider.visibleExternal.map((c) => c.book.title),
      ['Missing Volume', 'The Fall', 'A Happy Death'],
    );
  });

  test('a dismissal persists in the shared external store', () async {
    final provider = await loadedProvider();

    await provider.dismissExternal('author:Q34670:the plague');

    // Same store as the series lane: an ISBN-keyed dismissal on one lane
    // suppresses the same book on the other (ADR-060 section 4.5).
    expect(
      await ExternalSuggestionDismissalService.loadDismissed(),
      contains('author:Q34670:the plague'),
    );
  });
}
