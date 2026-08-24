import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/collection.dart';
import 'package:bibliogenius/models/collection_book.dart';
import 'package:bibliogenius/services/collection_export_service.dart';
import 'package:bibliogenius/services/collection_import_service.dart';

import '../helpers/mock_classes.dart';

/// The shared-list round trip: one reader exports a collection, another
/// imports the YAML. Both halves shipped without a single test, so nothing
/// held the two formats together; this is the contract, written down.
///
/// It stops at the PARSE boundary on purpose. What comes after (creating the
/// books) is network and FFI, and what breaks silently when either side is
/// refactored is the agreement on the format.
void main() {
  const exporter = CollectionExportService();
  final importer = CollectionImportService(MockApiService());

  Collection collection({String name = 'Mangas essentiels', String? description}) =>
      Collection(
        id: 'c1',
        name: name,
        description: description,
        source: 'manual',
        createdAt: '2026-08-24T06:00:00Z',
        updatedAt: '2026-08-24T06:00:00Z',
      );

  // Typed, and that is the point: the exporter used to take a list of maps
  // and read a key the real collection DTO never carried, so every export
  // came out empty while a test built on hand-made maps stayed green.
  CollectionBook member(String? isbn, String title, {String? author}) =>
      CollectionBook(
        bookId: 'b-$title',
        title: title,
        isbn: isbn,
        author: author,
        isOwned: true,
      );

  final books = [
    member('9782723488525', 'One Piece', author: 'Eiichiro Oda'),
    member('9782505010616', 'Naruto', author: 'Masashi Kishimoto'),
  ];

  test('every ISBN survives the trip', () {
    final yaml = exporter.exportToYaml(collection(), books);
    final parsed = CollectionImportService.parseSharedList(yaml);

    expect(
      parsed.books.map((b) => b.isbn),
      ['9782723488525', '9782505010616'],
    );
    expect(parsed.books.first.note, 'One Piece - Eiichiro Oda');
  });

  test('a member with no ISBN is dropped, the others still travel', () {
    // An entry IS an ISBN in this format. Exporting one half-formed would
    // hand the receiver a book they can never resolve.
    final yaml = exporter.exportToYaml(collection(), [
      member(null, 'Sans ISBN', author: 'Personne'),
      member('9782723488525', 'One Piece', author: 'Eiichiro Oda'),
    ]);
    final parsed = CollectionImportService.parseSharedList(yaml);

    expect(parsed.books.map((b) => b.isbn), ['9782723488525']);
  });

  test('a member with no author keeps its title alone in the note', () {
    // Never "Titre - Unknown": a note read back the wrong way round names the
    // book after its author, and "Unknown" is the worst of those names.
    final yaml = exporter.exportToYaml(collection(), [
      member('9782723488525', 'One Piece'),
    ]);
    final parsed = CollectionImportService.parseSharedList(yaml);

    expect(parsed.books.single.note, 'One Piece');
  });

  test('the title and the contributor survive it too', () {
    final yaml = exporter.exportToYaml(
      collection(description: 'Pour commencer'),
      books,
      contributorName: 'Une amie',
    );
    final parsed = CollectionImportService.parseSharedList(yaml);

    expect(parsed.getTitle('fr'), 'Mangas essentiels');
    expect(parsed.getDescription('fr'), 'Pour commencer');
    expect(parsed.contributor, 'Une amie');
  });

  test('a name of pure punctuation still yields a usable id', () {
    // `_sanitizeId` strips everything that is not alphanumeric, so a name
    // like this exports `id:` empty. The importer only invented an id when
    // the KEY was missing, so an empty one used to travel as-is.
    final yaml = exporter.exportToYaml(collection(name: '★★★'), books);
    final parsed = CollectionImportService.parseSharedList(yaml);

    expect(parsed.id, isNotEmpty);
  });

  test('the declared languages survive, so the list can be suggested', () {
    // Without them the editorial affinity tier can never surface an imported
    // list: its language gate treats an undeclared list as ineligible.
    final yaml = exporter.exportToYaml(
      collection(),
      books,
      contentLanguages: const ['fr'],
    );

    expect(yaml, contains('content_languages'));
    expect(CollectionImportService.parseSharedList(yaml).contentLanguages, ['fr']);
  });

  test('an imported list is never promoted by the sender', () {
    // A stranger's YAML must not be able to declare itself audited: the
    // editorial tier would then push it. Curation is ours, never the file's.
    final parsed = CollectionImportService.parseSharedList('''
id: hostile
title: "Une liste"
curation_status: reviewed
books:
  - isbn: "9782723488525"
    note: "One Piece - Eiichiro Oda"
''');

    expect(parsed.isReviewed, isFalse);
  });

  test('a carriage return survives instead of collapsing to a space', () {
    // It never broke the file, which is what made it dangerous: a raw CR is
    // folded into a space by the parser, so the value arrived quietly wrong.
    final yaml = exporter.exportToYaml(
      collection(name: 'Avant\rAprès'),
      [member('9782723488525', 'T\ritre', author: 'Oda')],
    );
    final parsed = CollectionImportService.parseSharedList(yaml);

    expect(parsed.getTitle('fr'), 'Avant\rAprès');
    expect(parsed.books.single.note, 'T\ritre - Oda');
  });

  test('a quote inside an ISBN does not break the file', () {
    // Imported metadata reaches this field, and the file is parsed on someone
    // else's machine: a stray quote must not be their problem.
    final yaml = exporter.exportToYaml(collection(), [
      member('978-2"723488525', 'One Piece', author: 'Eiichiro Oda'),
    ]);

    expect(
      CollectionImportService.parseSharedList(yaml).books.single.isbn,
      '978-2"723488525',
    );
  });

  test('quotes and backslashes in a name do not break the YAML', () {
    final yaml = exporter.exportToYaml(
      collection(name: r'Le "grand" \ chelem'),
      books,
    );

    expect(
      CollectionImportService.parseSharedList(yaml).getTitle('fr'),
      r'Le "grand" \ chelem',
    );
  });

  test('a cover URL that is not https is dropped at the door', () {
    // The file comes from someone else and the app FETCHES what it points at.
    // An attacker-chosen URL would turn the reader's device into a beacon:
    // their IP and the moment they opened the list, in cleartext, with no
    // gesture of theirs. The bundled corpus is held to the same rule by the
    // audit tool; a shared list has no audit, so the door enforces it.
    final parsed = CollectionImportService.parseSharedList('''
id: hostile
title: "Une liste"
cover_url: "http://tracker.example/pixel.png"
books:
  - isbn: "9782723488525"
    note: "One Piece - Eiichiro Oda"
    cover_url: "http://tracker.example/one-piece.png"
''');

    expect(parsed.coverUrl, isNull);
    expect(parsed.books.single.coverUrl, isNull);
    expect(parsed.books.single.isbn, '9782723488525', reason: 'The list still imports.');
  });

  test('an https cover is kept', () {
    final parsed = CollectionImportService.parseSharedList('''
id: ok
title: "Une liste"
cover_url: "https://example.org/cover.jpg"
books:
  - isbn: "9782723488525"
    note: "One Piece - Eiichiro Oda"
''');

    expect(parsed.coverUrl, 'https://example.org/cover.jpg');
  });

  test('a file too big to be a list is refused before any parsing', () {
    // The entry-count warning can only speak AFTER parsing, so it does
    // nothing about the cost of the parse itself. This is the bound that
    // does. Generous: the whole bundled corpus is 396 KB and its longest
    // single list is 12 KB.
    expect(CollectionImportService.isTooLargeToParse(12 * 1024), isFalse);
    expect(CollectionImportService.isTooLargeToParse(396 * 1024), isFalse);
    expect(
      CollectionImportService.isTooLargeToParse(
        CollectionImportService.maxSharedListBytes,
      ),
      isFalse,
      reason: 'The boundary itself passes.',
    );
    expect(
      CollectionImportService.isTooLargeToParse(
        CollectionImportService.maxSharedListBytes + 1,
      ),
      isTrue,
    );
  });

  test('a very long list earns a warning, an ordinary one does not', () {
    // The import calls the metadata lookup once per book, each with its own
    // timeout, so the cost is what the reader is warned about. The threshold
    // sits far above anything real: the longest bundled list is 72 entries
    // and the reference library is 492 books.
    expect(CollectionImportService.isLargeSharedList(72), isFalse);
    expect(CollectionImportService.isLargeSharedList(492), isFalse);
    expect(
      CollectionImportService.isLargeSharedList(
        CollectionImportService.largeListWarningThreshold,
      ),
      isFalse,
      reason: 'The boundary itself stays quiet.',
    );
    expect(
      CollectionImportService.isLargeSharedList(
        CollectionImportService.largeListWarningThreshold + 1,
      ),
      isTrue,
    );
  });

  group('naming an imported list', () {
    // The case that raised this: someone shares their favourites, and the
    // receiver already has favourites of their own. Merging is never an
    // option there, because for that collection membership IS the star and
    // liked books weigh double in the ADR-066 ranking: a merge would bend the
    // receiver's recommendations toward someone else's taste, silently.
    const format = '{title} de {contributor}';

    String resolve({
      String title = 'Favoris',
      String? contributor,
      List<String> existing = const [],
    }) => CollectionImportService.resolveImportedCollectionName(
      title: title,
      contributor: contributor,
      existingNames: existing,
      withContributorFormat: format,
    );

    test('no collision keeps the sender title untouched', () {
      expect(
        resolve(title: 'Polars nordiques', contributor: 'Nohemi'),
        'Polars nordiques',
        reason: 'Decorating a name nothing clashes with is noise.',
      );
    });

    test('a collision borrows the contributor', () {
      expect(
        resolve(contributor: 'Nohemi', existing: ['Favoris']),
        'Favoris de Nohemi',
      );
    });

    test('a collision without a contributor keeps the bare title', () {
      expect(resolve(existing: ['Favoris']), 'Favoris');
      expect(resolve(contributor: '   ', existing: ['Favoris']), 'Favoris');
    });

    test('the collision test ignores case and surrounding spaces', () {
      // The receiver's own list is compared by its DISPLAYED name, which for
      // a favourites collection is the translated label and never the stored
      // `__favorites__` sentinel. Getting that wrong would miss exactly the
      // collision this exists for.
      expect(
        resolve(contributor: 'Nohemi', existing: ['  favoris ']),
        'Favoris de Nohemi',
      );
    });

    test('without a format nothing is invented', () {
      expect(
        CollectionImportService.resolveImportedCollectionName(
          title: 'Favoris',
          contributor: 'Nohemi',
          existingNames: const ['Favoris'],
        ),
        'Favoris',
      );
    });
  });

  test('previewing junk answers, it does not throw', () {
    // The paste button hands over whatever is on the clipboard.
    for (final junk in ['', 'bonjour', '- just\n- a\n- list', '{{{']) {
      expect(importer.getPreview(junk)['title'], isNotNull);
    }
  });
}
