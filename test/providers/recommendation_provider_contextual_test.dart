import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/recommendation_repository.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/recommendation_provider.dart';
import 'package:bibliogenius/services/discovery_service.dart';
import 'package:bibliogenius/utils/author_identity.dart';

/// ADR-061 section 3: the contextual surfaces read the SHARED lookup
/// inputs. What this file pins is the cost rule the ADR is built on, the
/// library must not be re-scanned per page open, plus the two guards the
/// dashboard blend does not have: a book page never fires a lookup, and the
/// author page refuses to run without an identity index.
class _CountingRepository implements RecommendationRepository {
  _CountingRepository(this.inputs, {this.localCount = 0});

  final DiscoveryLookupInputs? inputs;

  /// How many local suggestions the engine returns. Null inputs plus a zero
  /// count models "backend unavailable"; two or more clears the ADR-059
  /// visible-suggestions floor.
  final int localCount;
  int inputCalls = 0;

  @override
  Future<List<Recommendation>> getBookRecommendations(
    String bookId, {
    int? limit,
  }) async => const [];

  @override
  Future<PersonalRecommendations?> getPersonalRecommendations({
    int? limit,
  }) async {
    if (localCount == 0) return null;
    return PersonalRecommendations(
      recommendations: [
        for (var i = 0; i < localCount; i++)
          Recommendation(
            book: Book(id: 'local-$i', title: 'Local $i', author: 'Someone'),
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
  }

  @override
  Future<DiscoveryLookupInputs?> getDiscoveryLookupInputs() async {
    inputCalls++;
    return inputs;
  }
}

DiscoverySeriesLookup _lookup(String id, String name) => DiscoverySeriesLookup(
  collectionId: id,
  name: name,
  anchorIsbns: const ['9782070541270'],
  memberIsbns: const {},
  memberTitleAuthorKeys: const {},
);

Map<String, dynamic> _cachedSeries(String sourceId, List<(int, String)> vols) {
  return {
    'at': DateTime.now().millisecondsSinceEpoch,
    'status': 'resolved',
    'series': {
      'source_id': sourceId,
      'label': 'Series $sourceId',
      'volumes': [
        for (final (ordinal, title) in vols)
          {
            'ordinal': ordinal,
            'title': title,
            'authors': const ['J. K. Rowling'],
            'editions': const [],
          },
      ],
    },
  };
}

void main() {
  late List<Uri> hubCalls;

  DiscoveryService service() => DiscoveryService(
    baseUrl: 'https://hub.test',
    client: MockClient((request) async {
      hubCalls.add(request.url);
      return http.Response(jsonEncode({'status': 'unknown'}), 200);
    }),
  );

  ({RecommendationProvider provider, _CountingRepository repository}) build({
    DiscoveryLookupInputs? inputs,
  }) {
    final repository = _CountingRepository(
      inputs ??
          DiscoveryLookupInputs(
            series: [_lookup('col-1', 'Harry Potter')],
            authors: const [],
            libraryIsbns: const {'9780000000001'},
            libraryTitleAuthorKeys: const {'dune|frank herbert'},
          ),
    );
    return (
      provider: RecommendationProvider(
        repository,
        BookRefreshNotifier(),
        discoveryService: service(),
      ),
      repository: repository,
    );
  }

  setUp(() {
    hubCalls = [];
    SharedPreferences.setMockInitialValues({});
  });

  group('ensureLookupInputs', () {
    test('one library pass serves every surface', () async {
      final built = build();

      await built.provider.ensureLookupInputs();
      await built.provider.ensureLookupInputs();
      await built.provider.seriesCardsForCollections(
        const ['col-1'],
        langs: const ['fr'],
      );

      expect(
        built.repository.inputCalls,
        1,
        reason: 'opening a page must not cost a library scan',
      );
    });

    test('concurrent callers share the same in-flight pass', () async {
      final built = build();

      await Future.wait([
        built.provider.ensureLookupInputs(),
        built.provider.ensureLookupInputs(),
        built.provider.ensureLookupInputs(),
      ]);

      expect(built.repository.inputCalls, 1);
    });

    test('a catalogue mutation invalidates them', () async {
      final notifier = BookRefreshNotifier();
      final repository = _CountingRepository(
        DiscoveryLookupInputs(
          series: [_lookup('col-1', 'Harry Potter')],
          authors: const [],
          libraryIsbns: const {},
          libraryTitleAuthorKeys: const {},
        ),
      );
      final provider = RecommendationProvider(
        repository,
        notifier,
        discoveryService: service(),
      );

      await provider.ensureLookupInputs();
      expect(repository.inputCalls, 1);

      // The identity index and the lookups both change when books do, so
      // the contextual surfaces must not keep filtering against a library
      // that no longer exists.
      notifier.refresh();
      await provider.ensureLookupInputs();
      expect(repository.inputCalls, 2);
    });
  });

  /// ADR-061 section 4: what a page opening must NOT pay twice.
  group('memoisation (a second page open re-derives nothing)', () {
    test('the author vocabulary is derived once, not per page open', () async {
      final built = build();

      final first = await built.provider.authorVocabulary();
      final second = await built.provider.authorVocabulary();

      expect(first, {AuthorIdentity.matchKey('Frank Herbert')});
      expect(
        identical(first, second),
        isTrue,
        reason: 'the same Set instance, so nothing was re-derived',
      );
      expect(built.repository.inputCalls, 1);
    });

    test('a catalogue mutation re-derives it', () async {
      final notifier = BookRefreshNotifier();
      final repository = _CountingRepository(
        const DiscoveryLookupInputs(
          series: [],
          authors: [],
          libraryIsbns: {},
          libraryTitleAuthorKeys: {'dune|frank herbert'},
        ),
      );
      final provider = RecommendationProvider(
        repository,
        notifier,
        discoveryService: service(),
      );

      final before = await provider.authorVocabulary();
      notifier.refresh();
      final after = await provider.authorVocabulary();

      expect(identical(before, after), isFalse);
      expect(repository.inputCalls, 2);
    });

    test('the persistent caches are parsed once, not per page open', () async {
      SharedPreferences.setMockInitialValues({
        DiscoveryService.cacheKey: jsonEncode({
          'col-1': _cachedSeries('Q1', [(2, 'Chamber of Secrets')]),
        }),
      });
      final discovery = service();
      final provider = RecommendationProvider(
        _CountingRepository(
          DiscoveryLookupInputs(
            series: [_lookup('col-1', 'Harry Potter')],
            authors: const [],
            libraryIsbns: const {},
            libraryTitleAuthorKeys: const {},
          ),
        ),
        BookRefreshNotifier(),
        discoveryService: discovery,
      );

      for (var open = 0; open < 5; open++) {
        await provider.seriesCardsForCollections(
          const ['col-1'],
          langs: const ['fr'],
        );
      }

      expect(
        discovery.cacheDecodeCount,
        1,
        reason: 'five book pages, one jsonDecode of the series cache',
      );
    });

    test('a reader mutating the cache still sees fresh candidates', () async {
      // The memo must not outlive a write, or a dismissal-driven rewrite
      // would keep serving the old payload for the session.
      SharedPreferences.setMockInitialValues({});
      final discovery = DiscoveryService(
        baseUrl: 'https://hub.test',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'status': 'resolved',
              'series': {
                'source_id': 'Q1',
                'label': 'S',
                'volumes': [
                  {
                    'ordinal': 2,
                    'title': 'Freshly Resolved',
                    'authors': const ['A'],
                    'editions': const [],
                  },
                ],
              },
            }),
            200,
          ),
        ),
      );
      final inputs = DiscoveryLookupInputs(
        series: [_lookup('col-1', 'S')],
        authors: const [],
        libraryIsbns: const {},
        libraryTitleAuthorKeys: const {},
      );
      final provider = RecommendationProvider(
        _CountingRepository(inputs),
        BookRefreshNotifier(),
        discoveryService: discovery,
      );

      // Cold read populates the memo with an empty cache.
      expect(
        await provider.seriesCardsForCollections(
          const ['col-1'],
          langs: const ['fr'],
        ),
        isEmpty,
      );

      await discovery.sweep(inputs, const ['fr']);

      final cards = await provider.seriesCardsForCollections(
        const ['col-1'],
        langs: const ['fr'],
      );
      expect(cards.map((c) => c.book.title), ['Freshly Resolved']);
    });
  });

  group('seriesCardsForCollections (book page, cache-only)', () {
    test('serves the cache without the dashboard ever loading', () async {
      SharedPreferences.setMockInitialValues({
        DiscoveryService.cacheKey: jsonEncode({
          'col-1': _cachedSeries('Q1', [(2, 'Chamber of Secrets')]),
        }),
      });
      final built = build();

      // Note: no loadPersonal, no loadExternal. The app opens on the book
      // list, not the dashboard, so this is the normal path.
      final cards = await built.provider.seriesCardsForCollections(
        const ['col-1'],
        langs: const ['fr'],
      );

      expect(cards.map((c) => c.book.title), ['Chamber of Secrets']);
      expect(hubCalls, isEmpty);
    });

    test('a cold cache yields nothing and fires nothing', () async {
      final built = build();

      final cards = await built.provider.seriesCardsForCollections(
        const ['col-1'],
        langs: const ['fr'],
      );

      expect(cards, isEmpty);
      expect(
        hubCalls,
        isEmpty,
        reason: 'the book page is cache-only, it never resolves',
      );
    });

    test('no series collection means no work at all', () async {
      final built = build();

      final cards = await built.provider.seriesCardsForCollections(
        const [],
        langs: const ['fr'],
      );

      expect(cards, isEmpty);
      expect(
        built.repository.inputCalls,
        0,
        reason: 'a book outside any series must not even fetch the inputs',
      );
    });

    test('two series collections yield the first one that has candidates',
        () async {
      SharedPreferences.setMockInitialValues({
        DiscoveryService.cacheKey: jsonEncode({
          // col-1 resolved but complete: nothing missing.
          'col-1': _cachedSeries('Q1', const []),
          'col-2': _cachedSeries('Q2', [(5, 'Omnibus Volume')]),
        }),
      });
      final repository = _CountingRepository(
        DiscoveryLookupInputs(
          series: [_lookup('col-1', 'Cycle'), _lookup('col-2', 'Omnibus')],
          authors: const [],
          libraryIsbns: const {},
          libraryTitleAuthorKeys: const {},
        ),
      );
      final provider = RecommendationProvider(
        repository,
        BookRefreshNotifier(),
        discoveryService: service(),
      );

      final cards = await provider.seriesCardsForCollections(
        const ['col-1', 'col-2'],
        langs: const ['fr'],
      );

      expect(cards.map((c) => c.book.title), ['Omnibus Volume']);
    });
  });

  /// ADR-061 section 7, decision A5: the dashboard section is no longer the
  /// only igniter of the background sweep. Note that not a single widget is
  /// built anywhere in this group, which IS the point being pinned.
  group('warmUpAtStartup (session kick, no dashboard involved)', () {
    RecommendationProvider startupProvider({int localCount = 2}) {
      return RecommendationProvider(
        _CountingRepository(
          DiscoveryLookupInputs(
            series: [_lookup('col-1', 'Harry Potter')],
            authors: const [],
            libraryIsbns: const {},
            libraryTitleAuthorKeys: const {'dune|frank herbert'},
          ),
          localCount: localCount,
        ),
        BookRefreshNotifier(),
        discoveryService: service(),
      );
    }

    test('sweeps without any dashboard widget ever building', () async {
      final provider = startupProvider();

      await provider.warmUpAtStartup(langs: const ['fr']);

      expect(
        hubCalls.map((u) => u.path),
        ['/api/discovery/series'],
        reason: 'the sweep ran off the startup kick alone',
      );
    });

    test('runs once per session', () async {
      final provider = startupProvider();

      await provider.warmUpAtStartup(langs: const ['fr']);
      await provider.warmUpAtStartup(langs: const ['fr']);

      expect(hubCalls, hasLength(1));
    });

    test('still honours the two-visible-local floor', () async {
      // One local suggestion is below the ADR-059 floor: the kick loads the
      // profile and stops there. Decoupling the trigger must not smuggle in
      // a relaxation of the gates.
      final provider = startupProvider(localCount: 1);

      await provider.warmUpAtStartup(langs: const ['fr']);

      expect(hubCalls, isEmpty);
      expect(provider.visibleExternal, isEmpty);
    });

    test('an unavailable backend does not burn the session kick', () async {
      // FFI down (or web): the profile comes back null. The flag must stay
      // down so a later trigger still gets its chance.
      final provider = startupProvider(localCount: 0);

      await provider.warmUpAtStartup(langs: const ['fr']);
      expect(hubCalls, isEmpty);

      // Same provider, backend now answering: a second kick must work.
      final recovered = startupProvider();
      await recovered.warmUpAtStartup(langs: const ['fr']);
      expect(hubCalls, hasLength(1));
    });
  });

  group('authorPageDiscovery (author page, resolves on open)', () {
    test('an empty identity index disables the lane', () async {
      // Below the ADR-059 profile floor the FFI returns empty inputs. The
      // ADR-061 "explicit visits bypass the floors" rule stops here: with
      // no membrane the lane would offer books already on the shelf, which
      // precision-before-coverage forbids outright.
      final provider = RecommendationProvider(
        _CountingRepository(
          const DiscoveryLookupInputs(
            series: [],
            authors: [],
            libraryIsbns: {},
            libraryTitleAuthorKeys: {},
          ),
        ),
        BookRefreshNotifier(),
        discoveryService: service(),
      );

      final cards = await provider.authorPageDiscovery(
        name: 'Albert Camus',
        anchorIsbns: const ['9782070360024'],
        langs: const ['fr'],
      );

      expect(cards, isEmpty);
      expect(hubCalls, isEmpty);
    });

    test('an index present lets the visit resolve', () async {
      final built = build();

      await built.provider.authorPageDiscovery(
        name: 'Albert Camus',
        anchorIsbns: const ['9782070360024'],
        langs: const ['fr'],
      );

      expect(hubCalls.single.path, '/api/discovery/author');
    });
  });
}
