import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/collection.dart';
import 'package:bibliogenius/screens/book_list_screen.dart';
import 'package:bibliogenius/widgets/collection_stack_widget.dart';

/// The order the book page steps through must be the one the library view
/// shows, which is not always the filtered list as it stands.
Book _book(String id, {String? status}) =>
    Book(id: id, title: 'Book $id', readingStatus: status);

List<String?> _ids(List<Book> books) => [for (final b in books) b.id];

void main() {
  final filtered = [
    _book('a', status: 'read'),
    _book('b', status: 'reading'),
    _book('c', status: 'read'),
    _book('d'),
  ];

  test('flat views keep the filtered order', () {
    for (final mode in [
      ViewMode.list,
      ViewMode.spineShelf,
      ViewMode.coverGrid,
    ]) {
      final order = bookPageOrder(
        viewMode: mode,
        books: filtered,
        collectionGroups: const [],
        groupedByReadingStatus: false,
      );
      expect(_ids(order), ['a', 'b', 'c', 'd'], reason: '$mode');
    }
  });

  test('the sectioned covers grid follows its sections', () {
    final order = bookPageOrder(
      viewMode: ViewMode.coverGrid,
      books: filtered,
      collectionGroups: const [],
      groupedByReadingStatus: true,
    );
    // Sections run reading, to read, read, then the rest: the two finished
    // books sit together although the filtered list kept them apart.
    expect(_ids(order), ['b', 'a', 'c', 'd']);
  });

  test('sections only matter to the covers grid', () {
    final order = bookPageOrder(
      viewMode: ViewMode.list,
      books: filtered,
      collectionGroups: const [],
      groupedByReadingStatus: true,
    );
    expect(_ids(order), ['a', 'b', 'c', 'd']);
  });

  test('the collections view steps through its lone books only', () {
    final saga = Collection(
      id: 'saga',
      name: 'Saga',
      source: 'manual',
      createdAt: '2026-01-01',
      updatedAt: '2026-01-01',
    );
    final order = bookPageOrder(
      viewMode: ViewMode.groupedCollections,
      books: filtered,
      collectionGroups: [
        CollectionGroup(collection: null, books: [_book('x')]),
        CollectionGroup(collection: saga, books: [_book('s1'), _book('s2')]),
        CollectionGroup(collection: saga, books: [_book('s3')]),
        CollectionGroup(collection: null, books: [_book('y'), _book('z')]),
        CollectionGroup(collection: null, books: [_book('w')]),
      ],
      groupedByReadingStatus: false,
    );
    expect(_ids(order), ['x', 'w']);
  });
}
