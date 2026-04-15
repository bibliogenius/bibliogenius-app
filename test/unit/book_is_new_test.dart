import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/utils/app_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Book.isNew', () {
    test('returns false when addedAt is null', () {
      final book = Book(title: 'T');
      expect(book.isNew, isFalse);
    });

    test('returns true when addedAt is within the threshold', () {
      final recent = DateTime.now().subtract(const Duration(days: 1));
      final json = {
        'id': 1,
        'title': 'T',
        'added_at': recent.toIso8601String(),
      };
      expect(Book.fromJson(json).isNew, isTrue);
    });

    test('returns false when addedAt is older than the threshold', () {
      final old = DateTime.now().subtract(
        Duration(days: AppConstants.newBadgeDays + 1),
      );
      final json = {
        'id': 2,
        'title': 'T',
        'added_at': old.toIso8601String(),
      };
      expect(Book.fromJson(json).isNew, isFalse);
    });

    test('parses added_at from JSON into addedAt', () {
      final json = {
        'id': 3,
        'title': 'T',
        'added_at': '2026-04-15T10:00:00Z',
      };
      expect(
        Book.fromJson(json).addedAt,
        DateTime.parse('2026-04-15T10:00:00Z'),
      );
    });

    test('round-trips addedAt through toJson', () {
      final iso = '2026-04-15T10:00:00.000Z';
      final book = Book(title: 'T', addedAt: DateTime.parse(iso));
      expect(book.toJson()['added_at'], iso);
    });
  });
}
