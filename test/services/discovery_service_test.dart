import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/services/discovery_service.dart';

/// Freezes the ADR-060 client contracts of both lanes: the identity
/// normalization mirror (same fixtures as the Rust
/// `discovery_lookup_service` tests), the precision membrane of section
/// 4.2 (ISBN or title+author, translations and re-editions dropped),
/// candidate ordering, and the 24h throttle with stale-while-error
/// caching of section 4.3.
void main() {
  group('normalizeIdentityText mirrors the Rust normalization', () {
    test('folds case, diacritics and punctuation like the Rust side', () {
      // Same fixtures as discovery_lookup_service.rs; keep both in sync.
      expect(
        DiscoveryService.normalizeIdentityText("L'Étranger"),
        'l etranger',
      );
      expect(
        DiscoveryService.normalizeIdentityText('  Harry Potter, tome 3 '),
        'harry potter tome 3',
      );
      expect(
        DiscoveryService.normalizeIdentityText('J. K. Rowling'),
        'j k rowling',
      );
      expect(DiscoveryService.normalizeIdentityText('çà-et-là'), 'ca et la');
    });
  });

  DiscoverySeriesLookup lookup({
    Set<String>? memberIsbns,
    Set<String>? memberKeys,
  }) {
    return DiscoverySeriesLookup(
      collectionId: 'col-1',
      name: 'Harry Potter',
      anchorIsbns: const ['9782070541270'],
      memberIsbns: memberIsbns ?? const {},
      memberTitleAuthorKeys: memberKeys ?? const {},
    );
  }

  DiscoveryLookupInputs inputs({
    DiscoverySeriesLookup? series,
    Set<String>? libraryIsbns,
    Set<String>? libraryKeys,
  }) {
    return DiscoveryLookupInputs(
      series: [series ?? lookup()],
      authors: const [],
      libraryIsbns: libraryIsbns ?? const {},
      libraryTitleAuthorKeys: libraryKeys ?? const {},
    );
  }

  Map<String, dynamic> cacheWith(List<Map<String, dynamic>> volumes) {
    return {
      'col-1': {
        'at': DateTime.now().millisecondsSinceEpoch,
        'status': 'resolved',
        'series': {
          'source': 'wikidata',
          'source_id': 'Q8337',
          'label': 'Harry Potter',
          'volumes': volumes,
        },
      },
    };
  }

  Map<String, dynamic> volume(
    int ordinal,
    String title, {
    List<Map<String, dynamic>> editions = const [],
    List<String> authors = const ['J. K. Rowling'],
  }) {
    return {
      'ordinal': ordinal,
      'title': title,
      'authors': authors,
      'year': 1997 + ordinal,
      'editions': editions,
      'other_langs_exist': false,
    };
  }

  group('buildSeriesCandidates (the precision membrane)', () {
    test('missing volumes become cards, lowest ordinal first', () {
      final cards = DiscoveryService.buildSeriesCandidates(
        inputs: inputs(),
        cache: cacheWith([
          volume(4, 'Goblet of Fire', editions: [
            {'isbn': '9780747546245', 'lang': 'en', 'cover_url': null},
          ]),
          volume(2, 'Chamber of Secrets', editions: [
            {'isbn': '9780747538486', 'lang': 'en', 'cover_url': null},
          ]),
        ]),
        langs: const ['en'],
      );

      expect(cards, hasLength(1));
      expect(cards.first.map((c) => c.reasons.first.value), ['2', '4']);
      expect(cards.first.first.externalKey, 'isbn:9780747538486');
      expect(cards.first.first.source, 'external');
      expect(cards.first.first.reasons.first.type, 'series_missing_volume');
      expect(cards.first.first.reasons.first.params?['series'], 'Harry Potter');
    });

    test('a volume owned through a member ISBN is never suggested', () {
      final cards = DiscoveryService.buildSeriesCandidates(
        inputs: inputs(
          series: lookup(memberIsbns: {'9780747538486'}),
        ),
        cache: cacheWith([
          volume(2, 'Chamber of Secrets', editions: [
            {'isbn': '9780747538486', 'lang': 'en', 'cover_url': null},
          ]),
        ]),
        langs: const ['en'],
      );
      expect(cards, isEmpty);
    });

    test('a library ISBN (wishlist included) filters the volume', () {
      final cards = DiscoveryService.buildSeriesCandidates(
        inputs: inputs(libraryIsbns: {'9780747538486'}),
        cache: cacheWith([
          volume(2, 'Chamber of Secrets', editions: [
            {'isbn': '9780747538486', 'lang': 'en', 'cover_url': null},
          ]),
        ]),
        langs: const ['en'],
      );
      expect(cards, isEmpty);
    });

    test('owning a translation drops the volume by title+author', () {
      // The user owns "Dune" in French (no shared ISBN with the returned
      // English edition): the title+author half of the membrane must drop
      // it, translations are the main false-positive reservoir (4.2).
      final cards = DiscoveryService.buildSeriesCandidates(
        inputs: inputs(
          libraryKeys: {'dune|frank herbert'},
        ),
        cache: cacheWith([
          volume(1, 'Dune', authors: ['Frank Herbert'], editions: [
            {'isbn': '9780441172719', 'lang': 'en', 'cover_url': null},
          ]),
        ]),
        langs: const ['fr'],
      );
      expect(cards, isEmpty);
    });

    test('an inverted "Last, First" library key still drops the volume', () {
      // Catalogues imported as "Herbert, Frank" produce identity keys whose
      // author words are in the other order from the sources'. Without an
      // order-insensitive comparison the title half of the membrane matches
      // nothing for those libraries, and the reader is offered the
      // translation of a book on their shelf.
      final cards = DiscoveryService.buildSeriesCandidates(
        inputs: inputs(libraryKeys: {'dune|herbert frank'}),
        cache: cacheWith([
          volume(1, 'Dune', authors: ['Frank Herbert'], editions: [
            {'isbn': '9780441172719', 'lang': 'en', 'cover_url': null},
          ]),
        ]),
        langs: const ['fr'],
      );
      expect(cards, isEmpty);
    });

    test('prefers a reading-language edition, falls back to the original', () {
      final editions = [
        {'isbn': '9780747532699', 'lang': 'en', 'cover_url': null},
        {'isbn': '9782070518425', 'lang': 'fr', 'cover_url': null},
      ];
      final frCard = DiscoveryService.buildSeriesCandidates(
        inputs: inputs(),
        cache: cacheWith([volume(2, 'Chamber of Secrets', editions: editions)]),
        langs: const ['fr'],
      ).first.first;
      expect(frCard.book.isbn, '9782070518425');

      final noMatchCard = DiscoveryService.buildSeriesCandidates(
        inputs: inputs(),
        cache: cacheWith([volume(2, 'Chamber of Secrets', editions: editions)]),
        langs: const ['pt-BR'],
      ).first.first;
      // No reading-language edition: the first (original) edition wins.
      expect(noMatchCard.book.isbn, '9780747532699');
    });

    test('reading languages are honoured in order, not in payload order', () {
      // A trilingual reader: the payload happens to list Spanish first, but
      // French is their first reading language and a French edition exists.
      final editions = [
        {'isbn': '9788478884957', 'lang': 'es', 'cover_url': null},
        {'isbn': '9780439064866', 'lang': 'en', 'cover_url': null},
        {'isbn': '9782070643035', 'lang': 'fr', 'cover_url': null},
      ];
      final card = DiscoveryService.buildSeriesCandidates(
        inputs: inputs(),
        cache: cacheWith([volume(2, 'Chamber of Secrets', editions: editions)]),
        langs: const ['fr', 'es', 'en'],
      ).first.first;
      expect(card.book.isbn, '9782070643035');

      // Reordering the reader's languages reorders the pick.
      final esCard = DiscoveryService.buildSeriesCandidates(
        inputs: inputs(),
        cache: cacheWith([volume(2, 'Chamber of Secrets', editions: editions)]),
        langs: const ['es', 'fr', 'en'],
      ).first.first;
      expect(esCard.book.isbn, '9788478884957');
    });

    test('an edition-less volume still yields a title card with a series key',
        () {
      final card = DiscoveryService.buildSeriesCandidates(
        inputs: inputs(),
        cache: cacheWith([volume(5, 'Order of the Phoenix')]),
        langs: const ['en'],
      ).first.first;
      expect(card.book.isbn, isNull);
      expect(card.externalKey, 'series:Q8337:5');
    });
  });

  group('sweep (24h throttle, stale-while-error)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    DiscoveryService service({
      required List<http.Response> responses,
      required List<Uri> seen,
      DateTime Function()? now,
    }) {
      var call = 0;
      return DiscoveryService(
        baseUrl: 'https://hub.test',
        now: now,
        client: MockClient((request) async {
          seen.add(request.url);
          final response = responses[call < responses.length ? call : responses.length - 1];
          call++;
          return response;
        }),
      );
    }

    test('resolved payload is cached and the next sweep is throttled',
        () async {
      final seen = <Uri>[];
      final svc = service(
        seen: seen,
        responses: [
          http.Response(
            jsonEncode({
              'status': 'resolved',
              'series': {
                'source': 'wikidata',
                'source_id': 'Q8337',
                'label': 'Harry Potter',
                'volumes': [volume(2, 'Chamber of Secrets')],
              },
            }),
            200,
          ),
        ],
      );

      expect(await svc.sweep(inputs(), const ['fr']), isTrue);
      expect(seen, hasLength(1));
      expect(seen.first.path, '/api/discovery/series');

      final cards = await svc.buildFromCache(inputs(), const ['fr']);
      expect(cards.first.first.book.title, 'Chamber of Secrets');

      // Second sweep inside the 24h window: no request at all.
      await svc.sweep(inputs(), const ['fr']);
      expect(seen, hasLength(1));
    });

    test('a transport failure keeps the previous payload rendering',
        () async {
      SharedPreferences.setMockInitialValues({
        DiscoveryService.cacheKey: jsonEncode({
          'col-1': {
            // Stale timestamp so the sweep retries.
            'at': DateTime.now()
                .subtract(const Duration(days: 2))
                .millisecondsSinceEpoch,
            'status': 'resolved',
            'series': {
              'source': 'wikidata',
              'source_id': 'Q8337',
              'label': 'Harry Potter',
              'volumes': [volume(2, 'Chamber of Secrets')],
            },
          },
        }),
      });
      final seen = <Uri>[];
      final svc = service(
        seen: seen,
        responses: [http.Response('boom', 500)],
      );

      await svc.sweep(inputs(), const ['fr']);
      expect(seen, hasLength(1));

      final cards = await svc.buildFromCache(inputs(), const ['fr']);
      expect(cards.first.first.book.title, 'Chamber of Secrets',
          reason: 'stale-while-error: cached cards keep rendering');
    });

    test('a definitive negative drops the cached payload', () async {
      SharedPreferences.setMockInitialValues({
        DiscoveryService.cacheKey: jsonEncode({
          'col-1': {
            'at': DateTime.now()
                .subtract(const Duration(days: 2))
                .millisecondsSinceEpoch,
            'status': 'resolved',
            'series': {
              'source': 'wikidata',
              'source_id': 'Q8337',
              'label': 'Harry Potter',
              'volumes': [volume(2, 'Chamber of Secrets')],
            },
          },
        }),
      });
      final seen = <Uri>[];
      final svc = service(
        seen: seen,
        responses: [http.Response(jsonEncode({'status': 'ambiguous'}), 200)],
      );

      await svc.sweep(inputs(), const ['fr']);
      expect(await svc.buildFromCache(inputs(), const ['fr']), isEmpty);
    });

    test('a 429 does not burn the 24h throttle', () async {
      // The throttle counts attempts, but a 429 is our own burst hitting
      // the hub's anonymous per-IP limiter, not a resolution outcome.
      // Recording it would silence this series for a full day, which is
      // exactly what a first sweep on a large library would trigger.
      final seen = <Uri>[];
      final svc = service(
        seen: seen,
        responses: [
          http.Response('{"error":"rate limited"}', 429),
          http.Response(
            jsonEncode({
              'status': 'resolved',
              'series': {
                'source': 'wikidata',
                'source_id': 'Q8337',
                'label': 'Harry Potter',
                'volumes': [volume(2, 'Chamber of Secrets')],
              },
            }),
            200,
          ),
        ],
      );

      await svc.sweep(inputs(), const ['fr']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(DiscoveryService.cacheKey), isNull,
          reason: 'nothing cached, so nothing is throttled');

      // The next dashboard load retries instead of waiting a day.
      await svc.sweep(inputs(), const ['fr']);
      expect(seen, hasLength(2));
      final cards = await svc.buildFromCache(inputs(), const ['fr']);
      expect(cards.first.first.book.title, 'Chamber of Secrets');
    });

    test('entries whose series lookup disappeared are evicted', () async {
      SharedPreferences.setMockInitialValues({
        DiscoveryService.cacheKey: jsonEncode({
          'gone-collection': {
            'at': DateTime.now().millisecondsSinceEpoch,
            'status': 'resolved',
            'series': {'source_id': 'X', 'label': 'X', 'volumes': []},
          },
        }),
      });
      final seen = <Uri>[];
      final svc = service(
        seen: seen,
        responses: [http.Response(jsonEncode({'status': 'unknown'}), 200)],
      );

      await svc.sweep(inputs(), const ['fr']);

      final prefs = await SharedPreferences.getInstance();
      final cache =
          jsonDecode(prefs.getString(DiscoveryService.cacheKey)!) as Map;
      expect(cache.containsKey('gone-collection'), isFalse);
      expect(cache.containsKey('col-1'), isTrue);
    });
  });

  group('buildAuthorCandidates (the author lane membrane)', () {
    DiscoveryLookupInputs authorInputs({
      Set<String>? libraryIsbns,
      Set<String>? libraryKeys,
    }) {
      return DiscoveryLookupInputs(
        series: const [],
        authors: const [
          DiscoveryAuthorLookup(
            name: 'Albert Camus',
            anchorIsbns: ['9782070360024'],
          ),
        ],
        libraryIsbns: libraryIsbns ?? const {},
        libraryTitleAuthorKeys: libraryKeys ?? const {},
      );
    }

    Map<String, dynamic> work(
      String title, {
      int? editionsCount,
      List<String> titles = const [],
      List<String> authors = const ['Albert Camus'],
      List<Map<String, dynamic>> editions = const [],
    }) {
      return {
        'title': title,
        'titles': [title, ...titles],
        'authors': authors,
        'year': 1942,
        'editions_count': editionsCount,
        'editions': editions,
        'other_langs_exist': false,
      };
    }

    Map<String, dynamic> authorCache(List<Map<String, dynamic>> works) {
      return {
        'Albert Camus': {
          'at': DateTime.now().millisecondsSinceEpoch,
          'status': 'resolved',
          'author': {
            'source': 'wikidata',
            'source_id': 'Q34670',
            'label': 'Albert Camus',
            'works': works,
          },
        },
      };
    }

    test('works become cards ranked by edition count, unranked last', () {
      final cards = DiscoveryService.buildAuthorCandidates(
        inputs: authorInputs(),
        cache: authorCache([
          work('The Fall', editionsCount: 12),
          work('Youthful Writings'),
          work('The Plague', editionsCount: 41),
        ]),
        langs: const ['en'],
      );

      expect(cards, hasLength(1));
      expect(
        cards.first.map((c) => c.book.title),
        ['The Plague', 'The Fall', 'Youthful Writings'],
      );
      final first = cards.first.first;
      expect(first.source, 'external');
      expect(first.reasons.first.type, 'author_completion');
      expect(first.reasons.first.params?['author'], 'Albert Camus');
    });

    test('a work owned through any of its ISBNs is never suggested', () {
      final cards = DiscoveryService.buildAuthorCandidates(
        inputs: authorInputs(libraryIsbns: {'9782070360024'}),
        cache: authorCache([
          work(
            'The Stranger',
            editionsCount: 41,
            editions: [
              {'isbn': '9782070360024', 'lang': 'fr', 'cover_url': null},
            ],
          ),
        ]),
        langs: const ['fr'],
      );
      expect(cards, isEmpty);
    });

    test('owning the translation drops the work through its other titles', () {
      // The library holds "L'Etranger"; the sources answer "The Stranger"
      // and list the French title among the alternates. Without matching on
      // every known title, author completion offers people the translation
      // of a book they already own, which is the false-positive reservoir
      // ADR-060 section 4.2 calls out.
      final cards = DiscoveryService.buildAuthorCandidates(
        inputs: authorInputs(libraryKeys: {'l etranger|albert camus'}),
        cache: authorCache([
          work('The Stranger', editionsCount: 41, titles: ["L'Étranger"]),
        ]),
        langs: const ['fr'],
      );
      expect(cards, isEmpty);
    });

    test('an inverted "Last, First" library key still drops the work', () {
      final cards = DiscoveryService.buildAuthorCandidates(
        inputs: authorInputs(libraryKeys: {'the plague|camus albert'}),
        cache: authorCache([work('The Plague', editionsCount: 41)]),
        langs: const ['fr'],
      );
      expect(cards, isEmpty);
    });

    test('a work with no author falls back to the looked-up author', () {
      final cards = DiscoveryService.buildAuthorCandidates(
        inputs: authorInputs(libraryKeys: {'the stranger|albert camus'}),
        cache: authorCache([
          work('The Stranger', editionsCount: 41, authors: const []),
        ]),
        langs: const ['fr'],
      );
      // The membrane still fires: a source that forgets the author must not
      // disable half of it (the drift found in the volet 1 recette).
      expect(cards, isEmpty);
    });

    test('an edition-less work still yields a title card with an author key',
        () {
      final card = DiscoveryService.buildAuthorCandidates(
        inputs: authorInputs(),
        cache: authorCache([work('A Happy Death', editionsCount: 2)]),
        langs: const ['fr'],
      ).first.first;
      expect(card.book.isbn, isNull);
      expect(card.externalKey, 'author:Q34670:a happy death');
      expect(card.book.author, 'Albert Camus');
    });

    test('a work with an ISBN is dismissed in the ISBN namespace', () {
      // Same key shape as the series lane: a book waved away as a missing
      // volume stays waved away as an author work.
      final card = DiscoveryService.buildAuthorCandidates(
        inputs: authorInputs(),
        cache: authorCache([
          work(
            'The Plague',
            editionsCount: 41,
            editions: [
              {'isbn': '9782070360428', 'lang': 'fr', 'cover_url': null},
            ],
          ),
        ]),
        langs: const ['fr'],
      ).first.first;
      expect(card.externalKey, 'isbn:9782070360428');
    });

    test('two spellings of one author yield a single card set', () {
      // "J.K. Rowling" and "J. K. Rowling" survive the Rust profile
      // normalization as two favorite authors, so two lookups resolve to
      // the same entity: the resolved source_id is what tells us it is one
      // person, and the first lookup keeps the cards.
      const variants = DiscoveryLookupInputs(
        series: [],
        authors: [
          DiscoveryAuthorLookup(
            name: 'Albert Camus',
            anchorIsbns: ['9782070360024'],
          ),
          DiscoveryAuthorLookup(
            name: 'Camus, Albert',
            anchorIsbns: ['9782070360024'],
          ),
        ],
        libraryIsbns: {},
        libraryTitleAuthorKeys: {},
      );
      final resolved = authorCache([work('The Plague', editionsCount: 41)]);
      resolved['Camus, Albert'] = resolved['Albert Camus'];

      final cards = DiscoveryService.buildAuthorCandidates(
        inputs: variants,
        cache: resolved,
        langs: const ['fr'],
      );

      expect(cards, hasLength(1));
      expect(cards.first.first.reasons.first.params?['author'], 'Albert Camus');
    });

    test('candidates are bounded per author', () {
      final cards = DiscoveryService.buildAuthorCandidates(
        inputs: authorInputs(),
        cache: authorCache([
          for (var i = 0; i < 12; i++) work('Work $i', editionsCount: 12 - i),
        ]),
        langs: const ['fr'],
      );
      expect(
        cards.first,
        hasLength(DiscoveryService.authorCandidatesPerAuthor),
      );
    });
  });

  group('sweepAuthors (24h throttle, stale-while-error)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    final authorLookupInputs = DiscoveryLookupInputs(
      series: const [],
      authors: const [
        DiscoveryAuthorLookup(
          name: 'Albert Camus',
          anchorIsbns: ['9782070360024'],
        ),
      ],
      libraryIsbns: const {},
      libraryTitleAuthorKeys: const {},
    );

    test('posts the author contract and throttles the next sweep', () async {
      final seen = <Uri>[];
      final bodies = <String>[];
      final svc = DiscoveryService(
        baseUrl: 'https://hub.test',
        client: MockClient((request) async {
          seen.add(request.url);
          bodies.add(request.body);
          return http.Response(
            jsonEncode({
              'status': 'resolved',
              'author': {
                'source': 'wikidata',
                'source_id': 'Q34670',
                'label': 'Albert Camus',
                'works': [
                  {
                    'title': 'The Plague',
                    'titles': ['The Plague'],
                    'authors': ['Albert Camus'],
                    'year': 1947,
                    'editions_count': 41,
                    'editions': [],
                    'other_langs_exist': false,
                  },
                ],
              },
            }),
            200,
          );
        }),
      );

      expect(await svc.sweepAuthors(authorLookupInputs, const ['fr']), isTrue);
      expect(seen.single.path, '/api/discovery/author');
      final body = jsonDecode(bodies.single) as Map<String, dynamic>;
      expect(body['name'], 'Albert Camus');
      expect(body['anchor_isbns'], ['9782070360024']);
      expect(body['langs'], ['fr']);

      final cards = await svc.buildAuthorsFromCache(
        authorLookupInputs,
        const ['fr'],
      );
      expect(cards.first.first.book.title, 'The Plague');

      await svc.sweepAuthors(authorLookupInputs, const ['fr']);
      expect(seen, hasLength(1), reason: 'inside the 24h throttle window');
    });

    test('a homonym answer drops the cached bibliography', () async {
      SharedPreferences.setMockInitialValues({
        DiscoveryService.authorCacheKey: jsonEncode({
          'Albert Camus': {
            'at': DateTime.now()
                .subtract(const Duration(days: 2))
                .millisecondsSinceEpoch,
            'status': 'resolved',
            'author': {
              'source_id': 'Q34670',
              'label': 'Albert Camus',
              'works': [
                {
                  'title': 'The Plague',
                  'titles': ['The Plague'],
                  'authors': ['Albert Camus'],
                  'editions_count': 41,
                  'editions': [],
                },
              ],
            },
          },
        }),
      });
      final svc = DiscoveryService(
        baseUrl: 'https://hub.test',
        client: MockClient(
          (_) async => http.Response(jsonEncode({'status': 'ambiguous'}), 200),
        ),
      );

      await svc.sweepAuthors(authorLookupInputs, const ['fr']);
      expect(
        await svc.buildAuthorsFromCache(authorLookupInputs, const ['fr']),
        isEmpty,
      );
    });

    test('a transport failure keeps the previous bibliography rendering',
        () async {
      SharedPreferences.setMockInitialValues({
        DiscoveryService.authorCacheKey: jsonEncode({
          'Albert Camus': {
            'at': DateTime.now()
                .subtract(const Duration(days: 2))
                .millisecondsSinceEpoch,
            'status': 'resolved',
            'author': {
              'source_id': 'Q34670',
              'label': 'Albert Camus',
              'works': [
                {
                  'title': 'The Plague',
                  'titles': ['The Plague'],
                  'authors': ['Albert Camus'],
                  'editions_count': 41,
                  'editions': [],
                },
              ],
            },
          },
        }),
      });
      final svc = DiscoveryService(
        baseUrl: 'https://hub.test',
        client: MockClient((_) async => http.Response('boom', 500)),
      );

      await svc.sweepAuthors(authorLookupInputs, const ['fr']);
      final cards = await svc.buildAuthorsFromCache(
        authorLookupInputs,
        const ['fr'],
      );
      expect(cards.first.first.book.title, 'The Plague');
    });

    test('a 429 on the author lane does not burn the throttle', () async {
      var call = 0;
      final seen = <Uri>[];
      final svc = DiscoveryService(
        baseUrl: 'https://hub.test',
        client: MockClient((request) async {
          seen.add(request.url);
          return call++ == 0
              ? http.Response('{"error":"rate limited"}', 429)
              : http.Response(jsonEncode({'status': 'unknown'}), 200);
        }),
      );

      await svc.sweepAuthors(authorLookupInputs, const ['fr']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(DiscoveryService.authorCacheKey), isNull);

      await svc.sweepAuthors(authorLookupInputs, const ['fr']);
      expect(seen, hasLength(2));
    });

    test('an author who left the taste profile is evicted', () async {
      SharedPreferences.setMockInitialValues({
        DiscoveryService.authorCacheKey: jsonEncode({
          'Someone Else': {
            'at': DateTime.now().millisecondsSinceEpoch,
            'status': 'resolved',
            'author': {'source_id': 'Q1', 'label': 'Someone Else', 'works': []},
          },
        }),
      });
      final svc = DiscoveryService(
        baseUrl: 'https://hub.test',
        client: MockClient(
          (_) async => http.Response(jsonEncode({'status': 'unknown'}), 200),
        ),
      );

      await svc.sweepAuthors(authorLookupInputs, const ['fr']);

      final prefs = await SharedPreferences.getInstance();
      final cache =
          jsonDecode(prefs.getString(DiscoveryService.authorCacheKey)!) as Map;
      expect(cache.containsKey('Someone Else'), isFalse);
      expect(cache.containsKey('Albert Camus'), isTrue);
    });
  });
}
