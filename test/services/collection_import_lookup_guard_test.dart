// The import skips its per-book network lookup when the curated entry already
// carries everything createBook needs. These tests pin both halves of that
// claim: the guard fires on the fully described lists, and it can never fire
// on the ones written before it.

import 'package:bibliogenius/services/collection_import_service.dart';
import 'package:bibliogenius/services/curated_lists_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CuratedBook full({
    String? note = 'Yvain ou Le chevalier au lion - Chrétien de Troyes',
    List<String>? authors = const ['Chrétien de Troyes'],
    String? publisher = 'Gallimard',
    String? publishedDate = '2017',
    String? description = 'Le roman de chevalerie fondateur.',
    String? coverUrl = 'https://example.invalid/cover.jpg',
  }) => CuratedBook(
    isbn: '9782070793693',
    note: note,
    authors: authors,
    publisher: publisher,
    publishedDate: publishedDate,
    description: description,
    coverUrl: coverUrl,
  );

  group('CollectionImportService.isSelfSufficient', () {
    test('a fully described entry needs no lookup', () {
      expect(CollectionImportService.isSelfSufficient(full()), isTrue);
    });

    // Each field is load-bearing: title comes from note, author from authors,
    // and the other four are what the lookup would otherwise supply.
    test('any missing field sends the entry back to the lookup', () {
      expect(
        CollectionImportService.isSelfSufficient(full(note: null)),
        isFalse,
      );
      expect(
        CollectionImportService.isSelfSufficient(full(authors: null)),
        isFalse,
      );
      expect(
        CollectionImportService.isSelfSufficient(full(publisher: null)),
        isFalse,
      );
      expect(
        CollectionImportService.isSelfSufficient(full(publishedDate: null)),
        isFalse,
      );
      expect(
        CollectionImportService.isSelfSufficient(full(description: null)),
        isFalse,
      );
      expect(
        CollectionImportService.isSelfSufficient(full(coverUrl: null)),
        isFalse,
      );
    });

    test('an empty string counts as missing, not as present', () {
      expect(CollectionImportService.isSelfSufficient(full(note: '')), isFalse);
      expect(
        CollectionImportService.isSelfSufficient(full(authors: const [])),
        isFalse,
      );
      expect(
        CollectionImportService.isSelfSufficient(full(coverUrl: '')),
        isFalse,
      );
    });

    test('a bare-ISBN entry is never self-sufficient', () {
      expect(
        CollectionImportService.isSelfSufficient(
          CuratedBook.fromYaml('9782070793693'),
        ),
        isFalse,
      );
    });
  });

  group('the guard against the real catalogue', () {
    // The point of the guard: importing this list must cost zero network
    // round-trips. If an entry ever loses a field, this fails and tells us the
    // import silently went back to being slow.
    test('every book of entree-en-6e skips the lookup', () async {
      final service = CuratedListsService.instance;
      service.clearCache();
      final list = await service.loadList('entree-en-6e');

      expect(list, isNotNull);
      final needing = list!.books
          .where((b) => !CollectionImportService.isSelfSufficient(b))
          .map((b) => b.isbn);

      expect(
        needing,
        isEmpty,
        reason:
            'entree-en-6e is fully described, so its import must make no '
            'network call at all; these entries would still trigger one',
      );
    });

    // The other half: lists written before the guard must be untouched by it,
    // otherwise the optimisation would be silently degrading their metadata.
    test('a list written before the guard always keeps its lookup', () async {
      final list = await CuratedListsService.instance.loadList('goncourt');

      expect(list, isNotNull);
      final skipping = list!.books
          .where(CollectionImportService.isSelfSufficient)
          .map((b) => b.isbn);

      expect(
        skipping,
        isEmpty,
        reason:
            'goncourt entries carry only isbn and note, so the guard must '
            'never fire for them and their import behaviour is unchanged',
      );
    });
  });
}
