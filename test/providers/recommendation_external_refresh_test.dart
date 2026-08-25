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

/// The external lane (ADR-060) is filtered by the precision membrane, which
/// compares each candidate against the library identity index. A catalogue
/// mutation invalidates that index, but nothing used to rebuild the cards
/// from it: a reader who scanned the very volume the card was offering kept
/// being offered it for the rest of the session.
class _FakeRepository implements RecommendationRepository {
  _FakeRepository(this.inputs);

  /// Swapped by the test to stand for the reader acquiring the missing
  /// volume: the identity index is what the membrane filters against.
  DiscoveryLookupInputs inputs;

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

DiscoveryLookupInputs _inputs({Set<String> libraryTitleAuthorKeys = const {}}) {
  return DiscoveryLookupInputs(
    series: const [
      DiscoverySeriesLookup(
        collectionId: 'col-1',
        name: 'My Series',
        anchorIsbns: ['9782070541270'],
        memberIsbns: {},
        memberTitleAuthorKeys: {},
      ),
    ],
    authors: const [],
    libraryIsbns: const {},
    libraryTitleAuthorKeys: libraryTitleAuthorKeys,
  );
}

Map<String, dynamic> _seriesCache() => {
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      DiscoveryService.cacheKey: jsonEncode(_seriesCache()),
    });
  });

  test('an acquired volume stops being offered after the mutation', () async {
    final repo = _FakeRepository(_inputs());
    final notifier = BookRefreshNotifier();
    final provider = RecommendationProvider(
      repo,
      notifier,
      discoveryService: DiscoveryService(baseUrl: 'https://hub.test'),
    );
    await pumpEventQueue();
    await provider.loadPersonal();
    await provider.loadExternal(langs: const ['fr']);

    expect(provider.visibleExternal.map((c) => c.book.title), [
      'Missing Volume',
    ]);

    // The reader scans it. The identity index now holds it, and no
    // suggestion surface remounts.
    repo.inputs = _inputs(
      libraryTitleAuthorKeys: {'missing volume|j k rowling'},
    );
    // Drains the queue rather than counting microtask turns: the eager
    // revalidation chains the local lane into the external one, and a fixed
    // number of turns stops proving anything the day it grows one await.
    notifier.refresh();
    await pumpEventQueue();

    expect(provider.visibleExternal, isEmpty);
  });

  test('the lane stays quiet until a surface has named the languages',
      () async {
    final repo = _FakeRepository(_inputs());
    final notifier = BookRefreshNotifier();
    final provider = RecommendationProvider(
      repo,
      notifier,
      discoveryService: DiscoveryService(baseUrl: 'https://hub.test'),
    );
    await pumpEventQueue();
    await provider.loadPersonal();

    // No loadExternal yet: the provider must not invent reading languages
    // to rebuild a lane no surface has ever asked for.
    notifier.refresh();
    await pumpEventQueue();

    expect(provider.visibleExternal, isEmpty);
  });
}
