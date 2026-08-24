import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/collection.dart';
import 'package:bibliogenius/services/collection_import_service.dart';
import 'package:bibliogenius/services/curated_lists_service.dart';

import '../helpers/mock_classes.dart';

/// Importing a curated list is a network call PER BOOK, in sequence, each
/// with its own timeout. On a ten-book list that is a long silence between
/// the tap and the SnackBar, and today the reader is shown nothing at all
/// during it and cannot stop it.
///
/// These pin the two things the loop owes its caller: it says where it is,
/// and it stops when asked, keeping what it already created.

class _CountingApi extends MockApiService {
  int created = 0;

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

CuratedList _list(int count) => CuratedList(
  id: 'sample',
  version: 1,
  title: const {'fr': 'Sélection', 'en': 'Selection'},
  description: const {'fr': '', 'en': ''},
  tags: const [],
  contentLanguages: const ['fr'],
  books: [
    for (var i = 0; i < count; i++)
      CuratedBook(
        isbn: '978000000000$i',
        note: 'Book $i - An Author',
        // Self-sufficient, so the loop makes no lookup call and the test
        // measures the loop rather than the network.
        authors: const ['An Author'],
        publisher: 'A Publisher',
        publishedDate: '2020',
        description: 'A description',
        coverUrl: 'https://example.org/c.jpg',
      ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the import reports where it is, book by book', () async {
    final seen = <List<int>>[];

    await CollectionImportService(_CountingApi()).importList(
      list: _list(5),
      langCode: 'fr',
      readingStatus: 'wanting',
      shouldMarkAsOwned: false,
      onProgress: (done, total) => seen.add([done, total]),
    );

    expect(seen.first, [0, 5], reason: 'it announces itself before the first '
        'book, so the reader sees a dialog rather than a frozen screen');
    expect(seen.last, [5, 5]);
    expect(seen.length, 6);
    expect(seen.every((p) => p[1] == 5), isTrue);
  });

  test('the import stops when asked and keeps what it created', () async {
    var done = 0;

    final result = await CollectionImportService(_CountingApi()).importList(
      list: _list(10),
      langCode: 'fr',
      readingStatus: 'wanting',
      shouldMarkAsOwned: false,
      onProgress: (d, _) => done = d,
      isCancelled: () => done >= 3,
    );

    expect(result.successCount, 3);
    expect(result.totalCount, 10);
    expect(
      result.hasError,
      isFalse,
      reason: 'stopping on request is not a failure, and the reader keeps '
          'the books already created',
    );
  });

  test('an import nobody stops still completes', () async {
    final result = await CollectionImportService(_CountingApi()).importList(
      list: _list(4),
      langCode: 'fr',
      readingStatus: 'wanting',
      shouldMarkAsOwned: false,
      isCancelled: () => false,
    );

    expect(result.successCount, 4);
  });

  test('the callbacks are optional, and their absence changes nothing',
      () async {
    final result = await CollectionImportService(_CountingApi()).importList(
      list: _list(3),
      langCode: 'fr',
      readingStatus: 'wanting',
      shouldMarkAsOwned: false,
    );

    expect(result.successCount, 3);
  });

  test('the book stored is the one the preview promised', () async {
    // The preview shows the entry's own title and the import used to store
    // whatever the metadata source returned, so a reader who validated
    // "Les androides revent-ils de moutons electriques ?" found "Blade
    // runner" in their library. One rule, both surfaces.
    final api = _CountingApi();

    await CollectionImportService(api).importList(
      list: CuratedList(
        id: 'sample',
        version: 1,
        title: const {'fr': 'S'},
        description: const {'fr': ''},
        tags: const [],
        contentLanguages: const ['fr'],
        books: const [
          CuratedBook(
            isbn: '9782505114741',
            note: 'Naruto - Tome 52',
            title: 'Naruto - Tome 52',
            authors: ['Masashi Kishimoto'],
            publisher: 'Kana',
            publishedDate: '2011',
            description: 'x',
            coverUrl: 'https://example.org/c.jpg',
          ),
        ],
      ),
      langCode: 'fr',
      readingStatus: 'wanting',
      shouldMarkAsOwned: false,
    );

    expect(api.createdBooks.single['title'], 'Naruto - Tome 52');
  });

  test('the collection records the list it came from', () async {
    // Without this the deletion has nothing to look at, and the dismissal
    // the import wrote can never be undone.
    final api = _CountingApi();

    await CollectionImportService(api).importList(
      list: _list(2),
      langCode: 'fr',
      readingStatus: 'wanting',
      shouldMarkAsOwned: false,
    );

    expect(api.createdSource, 'curated:sample');
  });
}
