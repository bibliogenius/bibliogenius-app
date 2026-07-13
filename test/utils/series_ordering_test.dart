import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/models/collection_book.dart';
import 'package:bibliogenius/utils/series_ordering.dart';

/// Unit tests for the pure reorder helper that backs drag-and-drop on both the
/// collection detail screen and the book-detail frise.
void main() {
  CollectionBook vol(String id, int? number) => CollectionBook(
    bookId: id,
    title: id,
    addedAt: DateTime(2026, 7, 13),
    isOwned: true,
    volumeNumber: number,
  );

  List<(String, int?)> pairs(List<CollectionBook> l) =>
      [for (final b in l) (b.bookId, b.volumeNumber)];

  group('reorderedSequentialVolumes', () {
    test('moving an item forward renumbers 1..N in the new order', () {
      final books = [vol('a', 1), vol('b', 2), vol('c', 3)];
      // Drag 'a' (index 0) to the end. Flutter passes newIndex = length.
      final result = reorderedSequentialVolumes(books, 0, 3);
      expect(pairs(result), [('b', 1), ('c', 2), ('a', 3)]);
    });

    test('moving an item backward renumbers 1..N in the new order', () {
      final books = [vol('a', 1), vol('b', 2), vol('c', 3)];
      // Drag 'c' (index 2) to the front.
      final result = reorderedSequentialVolumes(books, 2, 0);
      expect(pairs(result), [('c', 1), ('a', 2), ('b', 3)]);
    });

    test('unnumbered volumes get sequential numbers once ordered', () {
      final books = [vol('a', null), vol('b', null)];
      final result = reorderedSequentialVolumes(books, 1, 0);
      expect(pairs(result), [('b', 1), ('a', 2)]);
    });

    test('does not mutate the input list', () {
      final books = [vol('a', 1), vol('b', 2)];
      reorderedSequentialVolumes(books, 0, 2);
      expect(pairs(books), [('a', 1), ('b', 2)]);
    });
  });
}
