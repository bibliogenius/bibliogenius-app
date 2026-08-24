import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/collection.dart';
import 'package:bibliogenius/services/collection_import_service.dart';
import 'package:bibliogenius/services/curated_lists_service.dart';

import '../helpers/mock_classes.dart';

/// ADR-066: two changes to the curated import.
///
/// The edition follows the READER'S order of languages rather than the order
/// of the file (the ADR-061 recette A4 lesson), and the shelving option
/// rides the existing `createBook` subjects field, with no second pass over
/// the catalogue.

class _ImportApi extends MockApiService {
    String? createdSource;

  @override
  Future<Collection> createCollection(
    String name, {
    String? description,
    String source = 'manual',
  }) async {
    createdSource = source;
    return Collection(
      id: 'c1',
      name: name,
      description: description,
      source: 'manual',
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
    );
  }
}

CuratedList _list(List<CuratedBook> books) => CuratedList(
  id: 'sample',
  version: 1,
  title: const {'fr': 'Sélection', 'en': 'Selection'},
  description: const {'fr': '', 'en': ''},
  tags: const [],
  books: books,
  contentLanguages: const ['fr'],
);

/// One entry with three localized editions, listed Spanish first so file
/// order and reader order genuinely disagree.
const _multilingual = CuratedBook(
  isbn: '9780000000001',
  note: 'The Book - An Author',
  altEditions: {
    'es': '9788400000002',
    'fr': '9782000000003',
    'en': '9781000000004',
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('getIsbnForLanguages', () {
    test('honours the reader order, not the order of the file', () {
      expect(
        _multilingual.getIsbnForLanguages(const ['fr', 'es', 'en']),
        '9782000000003',
      );
      expect(
        _multilingual.getIsbnForLanguages(const ['en', 'fr']),
        '9781000000004',
      );
    });

    test('falls back to the contributor edition when nothing matches', () {
      expect(
        _multilingual.getIsbnForLanguages(const ['de', 'it']),
        '9780000000001',
      );
      expect(_multilingual.getIsbnForLanguages(const []), '9780000000001');
    });
  });

  group('entry identity', () {
    test('the explicit title wins over a volume caption note', () {
      const entry = CuratedBook(
        isbn: '9780000000001',
        note: 'Tome 1 : Dieu, le sexe et les bretelles',
        title: 'Dieu, le sexe et les bretelles',
        authors: ['Zep'],
      );
      expect(entry.identityTitle, 'Dieu, le sexe et les bretelles');
      expect(entry.identityAuthors, ['Zep']);
    });

    test('a note without a dash yields no title rather than a wrong one', () {
      const entry = CuratedBook(
        isbn: '9780000000001',
        note: 'Tome 4 : C\'est pô juste...',
      );
      expect(entry.identityTitle, isNull);
      expect(entry.identityAuthors, isEmpty);
    });

    test('the note form is split on the dash and loses its year', () {
      const entry = CuratedBook(
        isbn: '9780000000001',
        note: "L'Anomalie - Hervé Le Tellier (2020)",
      );
      expect(entry.identityTitle, "L'Anomalie");
      expect(entry.identityAuthors, ['Hervé Le Tellier']);
    });

    test('every edition is a recognisable identity', () {
      expect(_multilingual.allIsbns, [
        '9780000000001',
        '9788400000002',
        '9782000000003',
        '9781000000004',
      ]);
    });
  });

  group('the import', () {
    test('creates the reader-language edition, not the file one', () async {
      final api = _ImportApi();
      await CollectionImportService(api).importList(
        list: _list(const [_multilingual]),
        langCode: 'fr',
        readerLanguages: const ['fr', 'en'],
        readingStatus: 'to_read',
        shouldMarkAsOwned: true,
      );

      expect(api.createdBooks.single['isbn'], '9782000000003');
    });

    test('with no reader languages the old single-language behaviour '
        'is unchanged', () async {
      final api = _ImportApi();
      await CollectionImportService(api).importList(
        list: _list(const [_multilingual]),
        langCode: 'es',
        readingStatus: 'to_read',
        shouldMarkAsOwned: true,
      );

      expect(api.createdBooks.single['isbn'], '9788400000002');
    });

    test('shelf labels ride the existing createBook subjects', () async {
      final api = _ImportApi();
      await CollectionImportService(api).importList(
        list: _list(const [_multilingual]),
        langCode: 'fr',
        readerLanguages: const ['fr'],
        readingStatus: 'to_read',
        shouldMarkAsOwned: true,
        subjects: const ['Science-fiction', 'Cyberpunk'],
      );

      expect(api.createdBooks.single['subjects'], [
        'Science-fiction',
        'Cyberpunk',
      ]);
    });

    test('no shelving sends no subjects key at all', () async {
      // An empty list is a VALUE: sending it would write over whatever an
      // existing book already carries.
      final api = _ImportApi();
      await CollectionImportService(api).importList(
        list: _list(const [_multilingual]),
        langCode: 'fr',
        readerLanguages: const ['fr'],
        readingStatus: 'to_read',
        shouldMarkAsOwned: true,
      );

      expect(api.createdBooks.single.containsKey('subjects'), isFalse);
    });

    test('every imported book of the list gets the shelves', () async {
      final api = _ImportApi();
      await CollectionImportService(api).importList(
        list: _list(const [
          _multilingual,
          CuratedBook(isbn: '9780000000009', note: 'Other - Someone'),
        ]),
        langCode: 'fr',
        readerLanguages: const ['fr'],
        readingStatus: 'to_read',
        shouldMarkAsOwned: true,
        subjects: const ['Polar'],
      );

      expect(api.createdBooks, hasLength(2));
      for (final book in api.createdBooks) {
        expect(book['subjects'], ['Polar']);
      }
    });
  });
}
