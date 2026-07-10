import 'package:bibliogenius/models/book.dart';
import 'package:flutter_test/flutter_test.dart';

/// `reading_status` used to be overwritten with "borrowed"/"lent" by the
/// backend. Payloads written that way still reach the decoder (a peer cache
/// row, a stale response), so decoding must recover the possession and hand the
/// reading status back its own meaning.
void main() {
  Map<String, dynamic> payload(Map<String, dynamic> extra) => {
    'title': 'Le Livre',
    ...extra,
  };

  group('Book.fromJson possession flags', () {
    test('reads the explicit flags', () {
      final book = Book.fromJson(
        payload({
          'reading_status': 'read',
          'is_borrowed': true,
          'is_lent': false,
        }),
      );
      expect(book.readingStatus, 'read');
      expect(book.isBorrowed, isTrue);
      expect(book.isLent, isFalse);
      expect(book.isOnLoan, isTrue);
    });

    test('absent flags stay null, meaning unknown rather than false', () {
      final book = Book.fromJson(payload({'reading_status': 'read'}));
      expect(book.isBorrowed, isNull);
      expect(book.isLent, isNull);
      expect(book.isOnLoan, isFalse);
    });

    test('a legacy "borrowed" status becomes a flag, not a reading status', () {
      final book = Book.fromJson(payload({'reading_status': 'borrowed'}));
      expect(
        book.readingStatus,
        isNull,
        reason: '"borrowed" is absent from the reading-status picker',
      );
      expect(book.isBorrowed, isTrue);
      expect(book.isLent, isNull);
    });

    test('a legacy "lent" status becomes a flag', () {
      final book = Book.fromJson(payload({'reading_status': 'lent'}));
      expect(book.readingStatus, isNull);
      expect(book.isLent, isTrue);
      expect(book.isBorrowed, isNull);
    });

    test('an explicit flag wins over the legacy status', () {
      final book = Book.fromJson(
        payload({'reading_status': 'borrowed', 'is_borrowed': false}),
      );
      expect(book.isBorrowed, isFalse);
    });

    test('a real reading status is left alone', () {
      for (final status in ['to_read', 'reading', 'read', 'wanting']) {
        final book = Book.fromJson(payload({'reading_status': status}));
        expect(book.readingStatus, status);
        expect(book.isBorrowed, isNull);
      }
    });

    // The normalization the decoder already applied must survive the split.
    test('legacy "wanted" still folds into "wanting"', () {
      expect(
        Book.fromJson(payload({'reading_status': 'wanted'})).readingStatus,
        'wanting',
      );
    });
  });
}
