import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/utils/reading_statistics.dart';

Book _book(String title, {DateTime? finishedAt, String? status}) => Book(
  title: title,
  finishedReadingAt: finishedAt,
  readingStatus: status,
);

List<String> _titles(List<Book> books) => books.map((b) => b.title).toList();

void main() {
  group('recentlyFinishedBooks', () {
    test('empty input yields an empty selection', () {
      expect(recentlyFinishedBooks(const []), isEmpty);
    });

    test('hides the strip below the minimum number of dated books', () {
      final books = [
        for (var i = 0; i < kMinRecentlyFinishedBooks - 1; i++)
          _book('b$i', finishedAt: DateTime(2026, 1, i + 1)),
      ];
      expect(recentlyFinishedBooks(books), isEmpty);
    });

    test('shows the strip once the minimum is reached', () {
      final books = [
        for (var i = 0; i < kMinRecentlyFinishedBooks; i++)
          _book('b$i', finishedAt: DateTime(2026, 1, i + 1)),
      ];
      expect(recentlyFinishedBooks(books), hasLength(kMinRecentlyFinishedBooks));
    });

    test('orders by finish date, most recent first', () {
      final books = [
        _book('older', finishedAt: DateTime(2026, 1, 5)),
        _book('newest', finishedAt: DateTime(2026, 3, 20)),
        _book('oldest', finishedAt: DateTime(2025, 11, 2)),
        _book('middle', finishedAt: DateTime(2026, 2, 14)),
      ];
      expect(_titles(recentlyFinishedBooks(books)), [
        'newest',
        'middle',
        'older',
        'oldest',
      ]);
    });

    test('excludes books marked read without a finish date', () {
      // The strip is ordered by finish date: a book read with the "No Date"
      // option has nothing to sort on, so it stays out even though
      // totalPagesReadFromFinishedBooks counts it.
      final books = [
        _book('dated_a', finishedAt: DateTime(2026, 1, 1)),
        _book('dated_b', finishedAt: DateTime(2026, 1, 2)),
        _book('dated_c', finishedAt: DateTime(2026, 1, 3)),
        _book('undated', status: 'read'),
      ];
      expect(_titles(recentlyFinishedBooks(books)), [
        'dated_c',
        'dated_b',
        'dated_a',
      ]);
    });

    test('undated read books do not count towards the threshold', () {
      final books = [
        _book('dated', finishedAt: DateTime(2026, 1, 1)),
        _book('undated_a', status: 'read'),
        _book('undated_b', status: 'read'),
      ];
      expect(recentlyFinishedBooks(books), isEmpty);
    });

    test('caps the selection at the requested limit', () {
      final books = [
        for (var i = 1; i <= 15; i++)
          _book('b$i', finishedAt: DateTime(2026, 1, i)),
      ];
      final selection = recentlyFinishedBooks(books, limit: 10);
      expect(selection, hasLength(10));
      expect(selection.first.title, 'b15');
      expect(selection.last.title, 'b6');
    });

    test('threshold is measured before the limit cap', () {
      // A tight limit must not turn a well-stocked history into an empty
      // selection, nor a thin one into a rendered strip.
      final thin = [
        _book('a', finishedAt: DateTime(2026, 1, 1)),
        _book('b', finishedAt: DateTime(2026, 1, 2)),
      ];
      expect(recentlyFinishedBooks(thin, limit: 2), isEmpty);

      final stocked = [
        for (var i = 1; i <= 6; i++)
          _book('b$i', finishedAt: DateTime(2026, 1, i)),
      ];
      expect(recentlyFinishedBooks(stocked, limit: 2), hasLength(2));
    });
  });
}
