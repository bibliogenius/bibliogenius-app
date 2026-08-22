import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/utils/library_stats.dart';
import 'package:flutter_test/flutter_test.dart';

Book book({
  required bool owned,
  String? status,
  bool? isBorrowed,
  bool? isLent,
  String title = 'Le Livre',
}) => Book(
  title: title,
  owned: owned,
  readingStatus: status,
  isBorrowed: isBorrowed,
  isLent: isLent,
);

void main() {
  // The reported bug: statistics totals were `_books.length`, so wishlist
  // entries and read-but-not-owned books inflated the total and skewed the
  // completion rate (ADR-063).
  group('physicalLibrary', () {
    test('keeps owned books and drops wishlist entries', () {
      final books = [
        book(owned: true, status: 'read', title: 'Owned and read'),
        book(owned: false, status: 'wanting', title: 'Wished'),
        book(owned: false, status: 'read', title: 'Read at a friend\'s'),
      ];
      final library = physicalLibrary(books);
      expect(library.map((b) => b.title), ['Owned and read']);
    });

    test('keeps on-loan copies even though they are not owned', () {
      final books = [
        book(owned: false, isBorrowed: true, title: 'Borrowed'),
        book(owned: true, isLent: true, title: 'Lent out'),
        book(owned: false, status: 'wanting', title: 'Wished'),
      ];
      final library = physicalLibrary(books);
      expect(library.map((b) => b.title), ['Borrowed', 'Lent out']);
    });

    test(
      'ignores the hide-borrowed display preference: a lent copy still counts',
      () {
        // The preference hides on-loan books from the LIST view; the
        // statistics still describe them as part of the library.
        final books = [book(owned: false, isBorrowed: true)];
        expect(physicalLibrary(books), hasLength(1));
      },
    );
  });

  group('borrowedBooks', () {
    // `!owned` used to be the "borrowed" bucket. It also matches wishlist
    // entries and read-not-owned books, so the borrowed card over-counted.
    test('counts only copy-backed borrows, not every not-owned book', () {
      final books = [
        book(owned: false, isBorrowed: true, title: 'Really borrowed'),
        book(owned: false, status: 'wanting', title: 'Wished'),
        book(owned: false, status: 'read', title: 'Read at a friend\'s'),
        book(owned: true, title: 'Owned'),
      ];
      expect(borrowedBooks(books).map((b) => b.title), ['Really borrowed']);
    });

    test('a null flag (not computed) never counts as borrowed', () {
      expect(borrowedBooks([book(owned: false)]), isEmpty);
    });
  });
}
