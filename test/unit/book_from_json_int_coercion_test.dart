import 'package:bibliogenius/models/book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Book.fromJson int field coercion', () {
    // A peer catalogue may serialize numeric fields as strings depending on the
    // owner's app version or import pipeline. Parsing must not throw
    // "type 'String' is not a subtype of type 'int?'" and abort the whole sync.
    test('parses numeric int fields sent as strings', () {
      final json = {
        'id': 1,
        'title': 'T',
        'publication_year': '2014',
        'user_rating': '8',
        'available_copies': '3',
        'page_count': '256',
      };

      final book = Book.fromJson(json);

      expect(book.publicationYear, 2014);
      expect(book.userRating, 8);
      expect(book.availableCopies, 3);
      expect(book.pageCount, 256);
    });

    test('still parses int fields sent as numbers', () {
      final json = {
        'id': 2,
        'title': 'T',
        'publication_year': 2014,
        'user_rating': 8,
        'available_copies': 3,
        'page_count': 256,
      };

      final book = Book.fromJson(json);

      expect(book.publicationYear, 2014);
      expect(book.userRating, 8);
      expect(book.availableCopies, 3);
      expect(book.pageCount, 256);
    });

    test('leaves int fields null when absent or unparseable', () {
      final json = {
        'id': 3,
        'title': 'T',
        'publication_year': 'n/a',
        'page_count': null,
      };

      final book = Book.fromJson(json);

      expect(book.publicationYear, isNull);
      expect(book.userRating, isNull);
      expect(book.availableCopies, isNull);
      expect(book.pageCount, isNull);
    });

    test('coerces float-like numeric strings by truncation', () {
      final book = Book.fromJson({
        'id': 4,
        'title': 'T',
        'page_count': 256.0,
      });

      expect(book.pageCount, 256);
    });
  });
}
