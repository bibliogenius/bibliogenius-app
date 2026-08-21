import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/services/discovery_service.dart';

/// Freezes the ADR-060 client contracts: the identity normalization mirror
/// (same fixtures as the Rust `discovery_lookup_service` tests), the
/// precision membrane of section 4.2 (ISBN or title+author, translations
/// and re-editions dropped), candidate ordering, and the 24h throttle with
/// stale-while-error caching of section 4.3.
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
}
