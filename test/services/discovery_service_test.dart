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

  /// ADR-061 section 4: the client keeps a projection of the resolved author
  /// payload, not the hub's full one. What this group defends is the LIMIT of
  /// that reduction: every field the precision membrane reads survives it.
  /// A projection that saved more bytes by dropping alternate titles,
  /// authors or editions would not fail anything visibly, it would just
  /// start offering people translations of books on their shelf.
  group('projectAuthorPayload (what the client keeps)', () {
    Map<String, dynamic> hubWork() => {
      'title': 'La Distinction',
      'titles': ['La Distinction', 'Distinction', 'La distincion'],
      'authors': ['Pierre Bourdieu'],
      'year': 1979,
      'editions_count': 11,
      'other_langs_exist': true,
      'editions': [
        {
          'isbn': '9782707302267',
          'lang': 'fr',
          'cover_url': 'https://covers.test/1.jpg',
          'unused_extra': 'dead weight',
        },
      ],
    };

    test('keeps every field the membrane and the card read', () {
      final work =
          (DiscoveryService.projectAuthorPayload({
                'source': 'wikidata',
                'source_id': 'Q156268',
                'label': 'Pierre Bourdieu',
                'works': [hubWork()],
              })['works']
              as List)
              .single
          as Map<String, dynamic>;

      expect(work['title'], 'La Distinction');
      expect(
        work['titles'],
        ['Distinction', 'La distincion'],
        reason: 'alternate titles survive; only the echo of `title` goes',
      );
      expect(work['authors'], ['Pierre Bourdieu']);
      expect(work['editions_count'], 11);
      expect(work['year'], 1979);
      expect((work['editions'] as List).single, {
        'isbn': '9782707302267',
        'lang': 'fr',
        'cover_url': 'https://covers.test/1.jpg',
      });
    });

    test('drops what no client code reads', () {
      final work =
          (DiscoveryService.projectAuthorPayload({
                'works': [hubWork()],
              })['works']
              as List)
              .single
          as Map<String, dynamic>;

      // Never read anywhere in lib/: the "no edition at all" versus "none in
      // my languages" distinction was specified but never built.
      expect(work.containsKey('other_langs_exist'), isFalse);
      expect(
        (work['editions'] as List).single,
        isNot(contains('unused_extra')),
      );
    });

    test('the stored entry is materially smaller', () {
      final full = {
        'source_id': 'Q1',
        'label': 'A',
        'works': [for (var i = 0; i < 40; i++) hubWork()],
      };
      final projected = DiscoveryService.projectAuthorPayload(full);
      final before = jsonEncode(full).length;
      final after = jsonEncode(projected).length;

      expect(
        after,
        lessThan(before * 0.8),
        reason: 'measured 37% on a real 40-work bibliography',
      );
    });

    test('a projected entry still feeds the membrane', () async {
      // End to end: what the sweep WRITES must still let the membrane drop
      // an owned translation on the next read.
      SharedPreferences.setMockInitialValues({});
      final svc = DiscoveryService(
        baseUrl: 'https://hub.test',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'status': 'resolved',
              'author': {
                'source_id': 'Q156268',
                'label': 'Pierre Bourdieu',
                'works': [hubWork()],
              },
            }),
            200,
          ),
        ),
      );
      const owner = DiscoveryLookupInputs(
        series: [],
        authors: [],
        libraryIsbns: {},
        // The reader owns it under an ALTERNATE title only.
        libraryTitleAuthorKeys: {'distinction|pierre bourdieu'},
      );

      final cards = await svc.resolveAuthorForVisit(
        lookup: const DiscoveryAuthorLookup(
          name: 'Pierre Bourdieu',
          anchorIsbns: ['9782070360024'],
        ),
        inputs: owner,
        langs: const ['fr'],
        limit: 10,
      );

      expect(
        cards,
        isEmpty,
        reason: 'the alternate title kept by the projection did its job',
      );
    });
  });

  /// Anchor building must stay the mirror of the Rust `push_anchor`: the hub
  /// validates format AND checksum and rejects the whole request on the
  /// first malformed entry, while the client counts any non-200 as an
  /// attempt, so a value that slips through here silences a lookup for 24h.
  group('anchorIsbnsFrom (mirror of the Rust push_anchor)', () {
    test('drops a checksum-invalid ISBN and keeps the valid neighbour', () {
      expect(
        DiscoveryService.anchorIsbnsFrom([
          '9780553383042', // last digit off by one
          '9780553383041',
        ]),
        ['9780553383041'],
      );
    });

    test('canonicalizes to ISBN-13 and tolerates formatting', () {
      expect(
        DiscoveryService.anchorIsbnsFrom(['0-553-38304-3']),
        ['9780553383041'],
      );
    });

    test('deduplicates across the two forms of one ISBN', () {
      expect(
        DiscoveryService.anchorIsbnsFrom(['0553383043', '9780553383041']),
        ['9780553383041'],
      );
    });

    test('skips nulls and caps at the hub-accepted width', () {
      expect(
        DiscoveryService.anchorIsbnsFrom([
          null,
          '9782070360024',
          '9780553383041',
          '9780441172719',
          '9780747532699', // fourth valid one: the hub would 400 on it
        ]),
        hasLength(DiscoveryService.anchorIsbnsMax),
      );
    });

    test('an entirely unusable shelf produces no anchor, hence no request',
        () {
      expect(
        DiscoveryService.anchorIsbnsFrom([null, '', 'not-an-isbn', '123']),
        isEmpty,
      );
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
      expect(cards.values.first.map((c) => c.reasons.first.value), ['2', '4']);
      expect(cards.values.first.first.externalKey, 'isbn:9780747538486');
      expect(cards.values.first.first.source, 'external');
      expect(cards.values.first.first.reasons.first.type, 'series_missing_volume');
      expect(cards.values.first.first.reasons.first.params?['series'], 'Harry Potter');
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
      ).values.first.first;
      expect(frCard.book.isbn, '9782070518425');

      final noMatchCard = DiscoveryService.buildSeriesCandidates(
        inputs: inputs(),
        cache: cacheWith([volume(2, 'Chamber of Secrets', editions: editions)]),
        langs: const ['pt-BR'],
      ).values.first.first;
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
      ).values.first.first;
      expect(card.book.isbn, '9782070643035');

      // Reordering the reader's languages reorders the pick.
      final esCard = DiscoveryService.buildSeriesCandidates(
        inputs: inputs(),
        cache: cacheWith([volume(2, 'Chamber of Secrets', editions: editions)]),
        langs: const ['es', 'fr', 'en'],
      ).values.first.first;
      expect(esCard.book.isbn, '9788478884957');
    });

    test('an edition-less volume still yields a title card with a series key',
        () {
      final card = DiscoveryService.buildSeriesCandidates(
        inputs: inputs(),
        cache: cacheWith([volume(5, 'Order of the Phoenix')]),
        langs: const ['en'],
      ).values.first.first;
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
      expect(cards.values.first.first.book.title, 'Chamber of Secrets');

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
      expect(cards.values.first.first.book.title, 'Chamber of Secrets',
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
      expect(cards.values.first.first.book.title, 'Chamber of Secrets');
    });

    /// The client's own throttle is a blind 24h. An 'unavailable' answer is
    /// not a definitive negative: nothing was cached hub-side, and since the
    /// admission check exists a budget refusal costs the hub no outbound
    /// call at all. Pacing that like a homonym costs the reader a day for an
    /// outcome the hub meant as transient, so the hub names its own window
    /// and this side honours it.
    test('an unavailable answer is retried on the window the hub named',
        () async {
      final seen = <Uri>[];
      var clock = DateTime.utc(2026, 8, 25, 8);
      final svc = service(
        seen: seen,
        now: () => clock,
        responses: [
          http.Response(
            jsonEncode({'status': 'unavailable', 'retry_after': 300}),
            200,
          ),
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
      expect(seen, hasLength(1));

      // Inside the hub's window: still silent.
      clock = clock.add(const Duration(minutes: 2));
      await svc.sweep(inputs(), const ['fr']);
      expect(seen, hasLength(1), reason: 'inside the window the hub named');

      // Past it, and long before the 24h the old throttle would have cost.
      clock = clock.add(const Duration(minutes: 4));
      await svc.sweep(inputs(), const ['fr']);
      expect(seen, hasLength(2));
      final cards = await svc.buildFromCache(inputs(), const ['fr']);
      expect(cards.values.first.first.book.title, 'Chamber of Secrets');
    });

    /// A transport failure never reaches the hub, so there is no hint and no
    /// reason to assume the outage is brief: the 24h throttle stands.
    test('an unavailable answer with no hint keeps the 24h throttle',
        () async {
      final seen = <Uri>[];
      var clock = DateTime.utc(2026, 8, 25, 8);
      final svc = service(
        seen: seen,
        now: () => clock,
        responses: [http.Response(jsonEncode({'status': 'unavailable'}), 200)],
      );

      await svc.sweep(inputs(), const ['fr']);
      clock = clock.add(const Duration(hours: 6));
      await svc.sweep(inputs(), const ['fr']);

      expect(seen, hasLength(1), reason: 'no hint means the blind 24h window');
    });

    /// The floor is what keeps a bad or hostile value from turning every
    /// dashboard load into a hub call, which is the retry storm the throttle
    /// exists to prevent.
    test('a hint below the floor is clamped to the floor', () async {
      final seen = <Uri>[];
      var clock = DateTime.utc(2026, 8, 25, 8);
      final svc = service(
        seen: seen,
        now: () => clock,
        responses: [
          http.Response(
            jsonEncode({'status': 'unavailable', 'retry_after': 1}),
            200,
          ),
        ],
      );

      await svc.sweep(inputs(), const ['fr']);
      clock = clock.add(const Duration(seconds: 10));
      await svc.sweep(inputs(), const ['fr']);
      expect(seen, hasLength(1), reason: 'the floor holds, not the hub value');

      clock = clock.add(DiscoveryService.minRetryWindow);
      await svc.sweep(inputs(), const ['fr']);
      expect(seen, hasLength(2));
    });

    /// The floor is what stands between one hostile field and a retry storm.
    /// A value at the top of a 64-bit int overflows Duration to a NEGATIVE
    /// one, which no ceiling can catch (-1s is not greater than 24h) and
    /// which would make every dashboard load call the hub. Only the floor
    /// turns it into a window, and this test is what keeps the floor there.
    test('a pathological hint overflows to the floor, never to no window',
        () async {
      final seen = <Uri>[];
      var clock = DateTime.utc(2026, 8, 25, 8);
      final svc = service(
        seen: seen,
        now: () => clock,
        responses: [
          http.Response(
            jsonEncode({
              'status': 'unavailable',
              'retry_after': 9223372036854775807,
            }),
            200,
          ),
        ],
      );

      await svc.sweep(inputs(), const ['fr']);
      clock = clock.add(const Duration(seconds: 10));
      await svc.sweep(inputs(), const ['fr']);
      expect(seen, hasLength(1), reason: 'not a call on every load');

      clock = clock.add(DiscoveryService.minRetryWindow);
      await svc.sweep(inputs(), const ['fr']);
      expect(seen, hasLength(2), reason: 'the floor, not an unbounded window');
    });

    /// The ceiling keeps the hub from silencing a lookup for longer than
    /// this side already would on its own.
    test('a hint above the 24h throttle is capped at the throttle', () async {
      final seen = <Uri>[];
      var clock = DateTime.utc(2026, 8, 25, 8);
      final svc = service(
        seen: seen,
        now: () => clock,
        responses: [
          http.Response(
            jsonEncode({'status': 'unavailable', 'retry_after': 864000}),
            200,
          ),
        ],
      );

      await svc.sweep(inputs(), const ['fr']);
      clock = clock.add(const Duration(hours: 25));
      await svc.sweep(inputs(), const ['fr']);

      expect(seen, hasLength(2), reason: 'never silenced beyond the throttle');
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
        cards.values.first.map((c) => c.book.title),
        ['The Plague', 'The Fall', 'Youthful Writings'],
      );
      final first = cards.values.first.first;
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
      ).values.first.first;
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
      ).values.first.first;
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
      expect(cards.values.first.first.reasons.first.params?['author'], 'Albert Camus');
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
        cards.values.first,
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
      expect(cards.values.first.first.book.title, 'The Plague');

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
      expect(cards.values.first.first.book.title, 'The Plague');
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

    // ADR-061 section 4 inverts the volet 2 rule: the sweep used to drop
    // every key absent from the taste profile. Since the author page
    // resolves consulted authors into the SAME cache, absence from the
    // profile no longer means "no longer derivable", and evicting would
    // erase a page-warmed entry on the next dashboard load, defeating the
    // 24h throttle it exists to enforce. The bound is the LRU cap instead.
    test('an author absent from the taste profile survives the sweep',
        () async {
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
      expect(
        cache.containsKey('Someone Else'),
        isTrue,
        reason: 'a page-warmed author must not be evicted by a profile sweep',
      );
      expect(cache.containsKey('Albert Camus'), isTrue);
    });

    test('the author cache is bounded by LRU on the attempt timestamp',
        () async {
      // One entry per slot plus one, the oldest attempt being the one the
      // cap must drop.
      final now = DateTime.now().millisecondsSinceEpoch;
      final seeded = <String, dynamic>{
        for (var i = 0; i < DiscoveryService.maxAuthorCacheEntries; i++)
          'Author $i': {
            'at': now - (i * 1000),
            'status': 'resolved',
            'author': {'source_id': 'Q$i', 'label': 'Author $i', 'works': []},
          },
      };
      final oldest = 'Author ${DiscoveryService.maxAuthorCacheEntries - 1}';
      SharedPreferences.setMockInitialValues({
        DiscoveryService.authorCacheKey: jsonEncode(seeded),
      });
      final svc = DiscoveryService(
        baseUrl: 'https://hub.test',
        client: MockClient(
          (_) async => http.Response(jsonEncode({'status': 'unknown'}), 200),
        ),
      );

      // Albert Camus is not in the seeded cache, so the sweep adds a
      // 51st entry and the cap has to evict.
      await svc.sweepAuthors(authorLookupInputs, const ['fr']);

      final prefs = await SharedPreferences.getInstance();
      final cache =
          jsonDecode(prefs.getString(DiscoveryService.authorCacheKey)!) as Map;
      expect(cache, hasLength(DiscoveryService.maxAuthorCacheEntries));
      expect(cache.containsKey('Albert Camus'), isTrue);
      expect(
        cache.containsKey(oldest),
        isFalse,
        reason: 'the least recently attempted lookup is the one evicted',
      );
    });
  });

  /// ADR-061 section 2: the author page resolves ON OPEN, under the same
  /// 24h throttle and into the same cache as the profile sweep. The visit
  /// is the explicit gesture, so no local-suggestion floor applies, but the
  /// anchor rule does.
  group('resolveAuthorForVisit (the author page lane)', () {
    const camus = DiscoveryAuthorLookup(
      name: 'Albert Camus',
      anchorIsbns: ['9782070360024'],
    );

    const membrane = DiscoveryLookupInputs(
      series: [],
      // Deliberately EMPTY: the visited author is routinely not a favorite,
      // so the lane must work off the passed lookup, never off this list.
      authors: [],
      libraryIsbns: {'9782070360024'},
      libraryTitleAuthorKeys: {'l etranger|albert camus'},
    );

    Map<String, dynamic> resolvedPayload() => {
      'status': 'resolved',
      'author': {
        'source': 'wikidata',
        'source_id': 'Q34670',
        'label': 'Albert Camus',
        'works': [
          {
            'title': 'The Plague',
            'titles': ['The Plague', 'La Peste'],
            'authors': ['Albert Camus'],
            'year': 1947,
            'editions_count': 64,
            'editions': const [],
          },
          {
            // Already on the shelf through the identity index: the membrane
            // must drop it here exactly as on the dashboard.
            'title': 'The Stranger',
            'titles': ['The Stranger', "L'Etranger"],
            'authors': ['Albert Camus'],
            'year': 1942,
            'editions_count': 84,
            'editions': const [],
          },
        ],
      },
    };

    test('a cold visit resolves once and caches like a profile lookup',
        () async {
      SharedPreferences.setMockInitialValues({});
      final seen = <Uri>[];
      final svc = DiscoveryService(
        baseUrl: 'https://hub.test',
        client: MockClient((request) async {
          seen.add(request.url);
          return http.Response(jsonEncode(resolvedPayload()), 200);
        }),
      );

      final cards = await svc.resolveAuthorForVisit(
        lookup: camus,
        inputs: membrane,
        langs: const ['fr'],
        limit: 10,
      );

      expect(seen.single.path, '/api/discovery/author');
      expect(
        cards.map((c) => c.book.title),
        ['The Plague'],
        reason: 'the owned work is dropped by the shared membrane',
      );
      // Same key shape as the sweep, so a visit warms the dashboard.
      final prefs = await SharedPreferences.getInstance();
      final cache =
          jsonDecode(prefs.getString(DiscoveryService.authorCacheKey)!) as Map;
      expect(cache.keys, ['Albert Camus']);
      expect(cache['Albert Camus']['status'], 'resolved');
    });

    test('a second visit inside 24h serves the cache without a call',
        () async {
      SharedPreferences.setMockInitialValues({
        DiscoveryService.authorCacheKey: jsonEncode({
          'Albert Camus': {
            'at': DateTime.now().millisecondsSinceEpoch,
            'status': 'resolved',
            'author': resolvedPayload()['author'],
          },
        }),
      });
      final seen = <Uri>[];
      final svc = DiscoveryService(
        baseUrl: 'https://hub.test',
        client: MockClient((request) async {
          seen.add(request.url);
          return http.Response(jsonEncode(resolvedPayload()), 200);
        }),
      );

      final cards = await svc.resolveAuthorForVisit(
        lookup: camus,
        inputs: membrane,
        langs: const ['fr'],
        limit: 10,
      );

      expect(seen, isEmpty, reason: 'opening a page must not re-resolve');
      expect(cards.map((c) => c.book.title), ['The Plague']);
    });

    test('an author with no anchor ISBN produces no request at all', () async {
      SharedPreferences.setMockInitialValues({});
      final seen = <Uri>[];
      final svc = DiscoveryService(
        baseUrl: 'https://hub.test',
        client: MockClient((request) async {
          seen.add(request.url);
          return http.Response(jsonEncode(resolvedPayload()), 200);
        }),
      );

      final cards = await svc.resolveAuthorForVisit(
        lookup: const DiscoveryAuthorLookup(
          name: 'Albert Camus',
          anchorIsbns: [],
        ),
        inputs: membrane,
        langs: const ['fr'],
        limit: 10,
      );

      expect(seen, isEmpty);
      expect(cards, isEmpty);
    });

    test('an ambiguous answer shows nothing, never an error', () async {
      SharedPreferences.setMockInitialValues({});
      final svc = DiscoveryService(
        baseUrl: 'https://hub.test',
        client: MockClient(
          (_) async => http.Response(jsonEncode({'status': 'ambiguous'}), 200),
        ),
      );

      final cards = await svc.resolveAuthorForVisit(
        lookup: camus,
        inputs: membrane,
        langs: const ['fr'],
        limit: 10,
      );

      expect(cards, isEmpty);
    });

    test('a 429 does not burn the throttle of a visited author', () async {
      SharedPreferences.setMockInitialValues({});
      final svc = DiscoveryService(
        baseUrl: 'https://hub.test',
        client: MockClient((_) async => http.Response('rate limited', 429)),
      );

      await svc.resolveAuthorForVisit(
        lookup: camus,
        inputs: membrane,
        langs: const ['fr'],
        limit: 10,
      );

      // Nothing written: back-pressure is our own burst, not an outcome,
      // so the next visit retries instead of going silent for a day.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(DiscoveryService.authorCacheKey), isNull);
    });

    test('the page limit goes deeper than the dashboard cap', () async {
      SharedPreferences.setMockInitialValues({});
      final payload = {
        'status': 'resolved',
        'author': {
          'source_id': 'Q34670',
          'label': 'Albert Camus',
          'works': [
            for (var i = 0; i < 12; i++)
              {
                'title': 'Work $i',
                'titles': ['Work $i'],
                'authors': ['Albert Camus'],
                'editions_count': 100 - i,
                'editions': const [],
              },
          ],
        },
      };
      final svc = DiscoveryService(
        baseUrl: 'https://hub.test',
        client: MockClient(
          (_) async => http.Response(jsonEncode(payload), 200),
        ),
      );

      final cards = await svc.resolveAuthorForVisit(
        lookup: camus,
        inputs: membrane,
        langs: const ['fr'],
        limit: 10,
      );

      expect(cards, hasLength(10));
      expect(
        cards.first.book.title,
        'Work 0',
        reason: 'the popularity ranking of the lane is preserved',
      );
    });
  });
}
