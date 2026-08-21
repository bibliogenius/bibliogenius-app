import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/services/discovery_service.dart';

/// ADR-062 section 11: a series-lane card carries the LOCAL series
/// collection it completes, so the preview sheet can file the added volume
/// back into that collection from any surface.
///
/// The identity has to ride on the card rather than be looked up later: two
/// series collections resolving to the same hub series (a cycle plus an
/// omnibus, legitimate per ADR-052) produce two cards sharing one
/// `externalKey`, so a reverse lookup by key is ambiguous by construction
/// while a field set inside the per-lookup loop is not.
DiscoverySeriesLookup _lookup(String collectionId, String name) {
  return DiscoverySeriesLookup(
    collectionId: collectionId,
    name: name,
    anchorIsbns: const ['9782070541270'],
    memberIsbns: const {},
    memberTitleAuthorKeys: const {},
  );
}

Map<String, dynamic> _cachedSeries(String sourceId, List<(int, String)> vols) {
  return {
    'at': DateTime.now().millisecondsSinceEpoch,
    'status': 'resolved',
    'series': {
      'source': 'wikidata',
      'source_id': sourceId,
      'label': 'Series $sourceId',
      'volumes': [
        for (final (ordinal, title) in vols)
          {
            'ordinal': ordinal,
            'title': title,
            'authors': const ['J. K. Rowling'],
            'year': 2000,
            'editions': const [],
          },
      ],
    },
  };
}

Map<String, dynamic> _cachedAuthor(String sourceId, List<String> titles) {
  return {
    'at': DateTime.now().millisecondsSinceEpoch,
    'status': 'resolved',
    'author': {
      'source': 'wikidata',
      'source_id': sourceId,
      'name': 'Ursula K. Le Guin',
      'works': [
        for (final title in titles)
          {
            'title': title,
            'titles': <String>[],
            'authors': const ['Ursula K. Le Guin'],
            'year': 1969,
            'editions': const [],
            'editions_count': 12,
          },
      ],
    },
  };
}

DiscoveryLookupInputs _inputs({
  List<DiscoverySeriesLookup> series = const [],
  List<DiscoveryAuthorLookup> authors = const [],
}) {
  return DiscoveryLookupInputs(
    series: series,
    authors: authors,
    libraryIsbns: const {},
    libraryTitleAuthorKeys: const {},
  );
}

void main() {
  group('series lane carries the local collection id', () {
    test('a volume card names the collection it completes', () {
      final cards = DiscoveryService.buildSeriesCandidates(
        inputs: _inputs(series: [_lookup('col-1', 'Harry Potter')]),
        cache: {
          'col-1': _cachedSeries('Q1', [(2, 'Chamber of Secrets')]),
        },
        langs: const ['fr'],
      );

      final card = cards['col-1']!.single;
      expect(card.seriesCollectionId, 'col-1');
    });

    test('cycle and omnibus each keep their own collection', () {
      // Both collections resolve to the same hub series, so both cards
      // share `externalKey`. Only a per-lookup field can tell them apart.
      final cards = DiscoveryService.buildSeriesCandidates(
        inputs: _inputs(
          series: [_lookup('col-cycle', 'Cycle'), _lookup('col-omni', 'Omnibus')],
        ),
        cache: {
          'col-cycle': _cachedSeries('Q1', [(2, 'Chamber of Secrets')]),
          'col-omni': _cachedSeries('Q1', [(2, 'Chamber of Secrets')]),
        },
        langs: const ['fr'],
      );

      final cycle = cards['col-cycle']!.single;
      final omnibus = cards['col-omni']!.single;

      expect(cycle.externalKey, omnibus.externalKey);
      expect(cycle.seriesCollectionId, 'col-cycle');
      expect(omnibus.seriesCollectionId, 'col-omni');
    });

    test('the ordinal stays available for the volume number', () {
      final cards = DiscoveryService.buildSeriesCandidates(
        inputs: _inputs(series: [_lookup('col-1', 'Harry Potter')]),
        cache: {
          'col-1': _cachedSeries('Q1', [(7, 'Deathly Hallows')]),
        },
        langs: const ['fr'],
      );

      final card = cards['col-1']!.single;
      expect(card.reasons.first.params?['ordinal'], '7');
    });
  });

  group('other lanes file nothing', () {
    test('an author-lane card names no collection', () {
      final cards = DiscoveryService.buildAuthorCandidates(
        inputs: _inputs(
          authors: const [
            DiscoveryAuthorLookup(name: 'Ursula K. Le Guin', anchorIsbns: []),
          ],
        ),
        cache: {
          'Ursula K. Le Guin': _cachedAuthor('Q2', ['The Left Hand of Darkness']),
        },
        langs: const ['fr'],
      );

      final card = cards['Ursula K. Le Guin']!.first;
      expect(
        card.seriesCollectionId,
        isNull,
        reason: 'an author work belongs to no series collection',
      );
    });

    test('a library card names no collection', () {
      final card = Recommendation(
        book: Book(title: 'Local book'),
        score: 1,
        reasons: const [],
      );
      expect(card.seriesCollectionId, isNull);
    });
  });
}
