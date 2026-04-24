import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/utils/reading_statistics.dart';

Book _book({int? pageCount, DateTime? finishedAt, String? status}) => Book(
  title: 't',
  pageCount: pageCount,
  finishedReadingAt: finishedAt,
  readingStatus: status,
);

void main() {
  group('totalPagesReadFromFinishedBooks', () {
    test('empty input returns 0', () {
      expect(totalPagesReadFromFinishedBooks(const []), 0);
    });

    test('ignores books that are not finished', () {
      // Regression: a "reading" book with page_count should NOT contribute.
      final books = [
        _book(pageCount: 300, status: 'reading'), // unfinished — excluded
        _book(pageCount: 200, finishedAt: DateTime(2026, 1, 1)),
      ];
      expect(totalPagesReadFromFinishedBooks(books), 200);
    });

    test('status=read with no finished date still counts', () {
      // Regression: marking a book as read via the "No Date" option leaves
      // finished_reading_at null. Those books must still be counted.
      final books = [
        _book(pageCount: 180, status: 'read'),
        _book(pageCount: 90, status: 'read'),
      ];
      expect(totalPagesReadFromFinishedBooks(books), 270);
    });

    test('ignores finished books with missing page_count', () {
      // Regression: null pageCount must not crash; zero must not inflate.
      final books = [
        _book(finishedAt: DateTime(2026, 1, 1)), // pageCount null
        _book(pageCount: 0, finishedAt: DateTime(2026, 1, 2)),
        _book(pageCount: 150, finishedAt: DateTime(2026, 1, 3)),
      ];
      expect(totalPagesReadFromFinishedBooks(books), 150);
    });

    test('sums across all eligible books', () {
      final books = [
        _book(pageCount: 100, finishedAt: DateTime(2026, 1, 1)),
        _book(pageCount: 250, finishedAt: DateTime(2026, 2, 1)),
        _book(pageCount: 75, finishedAt: DateTime(2026, 3, 1)),
      ];
      expect(totalPagesReadFromFinishedBooks(books), 425);
    });
  });
}
