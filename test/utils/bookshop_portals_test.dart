import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/utils/bookshop_portals.dart';
import 'package:bibliogenius/utils/library_portals.dart';

void main() {
  group('bookshopPortalsForCountry', () {
    test('FR resolves to Place des libraires', () {
      final portals = bookshopPortalsForCountry('FR');
      expect(portals, hasLength(1));
      expect(portals.single.id, 'placedeslibraires');
    });

    test('non-default portals stay out of the country fallback', () {
      final ids = bookshopPortalsForCountry('FR').map((p) => p.id);
      expect(ids, isNot(contains('leslibraires-fr')));
    });

    test('is case-insensitive', () {
      expect(bookshopPortalsForCountry('fr'), isNotEmpty);
    });

    test('unknown country yields no portal', () {
      expect(bookshopPortalsForCountry('XX'), isEmpty);
    });
  });

  group('BookshopPortal.bookUri', () {
    final portal = bookshopPortalsForCountry('FR').single;

    test('appends the EAN-13 to the book URL', () {
      expect(
        portal.bookUri('9782072895098').toString(),
        'https://www.placedeslibraires.fr/livre/9782072895098',
      );
    });

    test('normalises ISBN-10 to EAN-13 (portals reject ISBN-10)', () {
      expect(
        portal.bookUri('207036822X').toString(),
        'https://www.placedeslibraires.fr/livre/9782070368228',
      );
    });

    test('strips hyphens', () {
      expect(
        portal.bookUri('978-2-07-289509-8').toString(),
        'https://www.placedeslibraires.fr/livre/9782072895098',
      );
    });

    test('returns null for an invalid ISBN', () {
      expect(portal.bookUri('not-an-isbn'), isNull);
      expect(portal.bookUri('9782072895099'), isNull); // bad check digit
    });
  });

  group('searchBookshopPortals', () {
    test('empty query lists the whole registry', () {
      expect(
        searchBookshopPortals(''),
        hasLength(bookshopPortalRegistry.length),
      );
    });

    test('matches case- and diacritic-insensitively', () {
      final hits = searchBookshopPortals('INDEPENDANTES');
      expect(hits.map((p) => p.id), contains('librairiesindependantes'));
    });

    test('no hit yields an empty list', () {
      expect(searchBookshopPortals('amazon'), isEmpty);
    });
  });

  group('bookshopPortalsForDisplay', () {
    test('selection wins over country defaults, order preserved', () {
      final portals = bookshopPortalsForDisplay(
        selectedIds: ['leslibraires-fr', 'placedeslibraires'],
        country: 'FR',
      );
      expect(portals.map((p) => (p as BookshopPortal).id).toList(), [
        'leslibraires-fr',
        'placedeslibraires',
      ]);
    });

    test('unknown ids are skipped silently', () {
      final portals = bookshopPortalsForDisplay(
        selectedIds: ['gone-portal', 'todostuslibros'],
        country: 'FR',
      );
      expect(portals.map((p) => (p as BookshopPortal).id).toList(), [
        'todostuslibros',
      ]);
    });

    test('empty selection falls back to the country defaults', () {
      final portals = bookshopPortalsForDisplay(
        selectedIds: [],
        country: 'ES',
      );
      expect(portals.map((p) => (p as BookshopPortal).id).toList(), [
        'todostuslibros',
      ]);
    });

    const custom = LocalLibraryPortal(
      name: 'Ma librairie',
      urlTemplate: 'https://shop.example.fr/?q={ean13}',
    );

    test('hand-added entries alone suppress the country defaults', () {
      final portals = bookshopPortalsForDisplay(
        selectedIds: [],
        country: 'FR',
        customs: [custom],
      );
      expect(portals.map((p) => p.name).toList(), ['Ma librairie']);
    });

    test('registry selection comes before hand-added entries', () {
      final portals = bookshopPortalsForDisplay(
        selectedIds: ['placedeslibraires'],
        country: 'FR',
        customs: [custom],
      );
      expect(portals.map((p) => p.name).toList(), [
        'Place des libraires',
        'Ma librairie',
      ]);
    });
  });

  group('query-style templates', () {
    test('leslibraires.fr builds a search URL', () {
      expect(
        bookshopPortalById('leslibraires-fr')!
            .bookUri('9782072895098')
            .toString(),
        'https://www.leslibraires.fr/recherche?q=9782072895098',
      );
    });
  });
}
