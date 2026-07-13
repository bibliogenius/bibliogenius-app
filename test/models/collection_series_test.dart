import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/models/collection.dart';
import 'package:bibliogenius/models/collection_book.dart';

/// Locks in the model-level contract the series frise relies on: how a series
/// collection is recognised, how "read" (full opacity) is decided, and that the
/// new `volume_number` / `reading_status` fields round-trip from JSON.
void main() {
  group('Collection.isSeries', () {
    Collection make(String source) => Collection(
      id: '1',
      name: 'Cycle',
      source: source,
      createdAt: '2026-07-13',
      updatedAt: '2026-07-13',
    );

    test('true only for the series source', () {
      expect(make('series').isSeries, isTrue);
      expect(make('manual').isSeries, isFalse);
      expect(make('csv_import').isSeries, isFalse);
      expect(make('open_library').isSeries, isFalse);
    });
  });

  group('CollectionBook.isRead (frise dimming)', () {
    CollectionBook withStatus(String? status) => CollectionBook(
      bookId: 'b',
      title: 'Tome',
      addedAt: DateTime(2026, 7, 13),
      isOwned: true,
      readingStatus: status,
    );

    test('only a finished read counts as read', () {
      expect(withStatus('read').isRead, isTrue);
      // Every other status renders dimmed.
      for (final s in ['to_read', 'reading', 'wanting', 'abandoned', null]) {
        expect(withStatus(s).isRead, isFalse, reason: 'status $s must dim');
      }
    });
  });

  group('CollectionBook.fromJson', () {
    test('maps volume_number and reading_status', () {
      final cb = CollectionBook.fromJson({
        'book_id': 'b-1',
        'title': 'Tome 2',
        'added_at': '2026-07-13T00:00:00Z',
        'is_owned': false,
        'reading_status': 'to_read',
        'volume_number': 2,
      });
      expect(cb.volumeNumber, 2);
      expect(cb.readingStatus, 'to_read');
      expect(cb.isOwned, isFalse);
      expect(cb.isRead, isFalse);
    });

    test('tolerates a missing volume_number (unnumbered) and status', () {
      final cb = CollectionBook.fromJson({
        'book_id': 'b-1',
        'title': 'Unnumbered',
        'added_at': '2026-07-13T00:00:00Z',
        'is_owned': true,
      });
      expect(cb.volumeNumber, isNull);
      expect(cb.readingStatus, isNull);
    });
  });
}
