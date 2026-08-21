import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/widgets/recently_added_carousel.dart';

/// ADR-062 section 4: the library top slot needs to know whether the
/// Activity segment has anything to show, so the small-library auto-hide
/// heuristic is promoted out of the carousel's private scope instead of
/// being copied into the slot.
///
/// These pin the heuristic as it already shipped: nothing to show hides,
/// a book being read always wins, and an untouched small library hides.
Book _book({
  required String id,
  String status = 'to_read',
  DateTime? addedAt,
  DateTime? startedAt,
}) {
  return Book(
    id: id,
    title: 'Book $id',
    readingStatus: status,
    addedAt: addedAt ?? DateTime.now().subtract(const Duration(days: 400)),
    startedReadingAt: startedAt,
  );
}

void main() {
  test('an empty library has no activity', () {
    expect(RecentlyAddedCarousel.activitySelection(const []), isEmpty);
  });

  test('a currently-read book always makes activity, however small', () {
    final books = [
      _book(id: '1', status: 'reading', startedAt: DateTime.now()),
      _book(id: '2'),
    ];

    final selection = RecentlyAddedCarousel.activitySelection(books);

    expect(selection, isNotEmpty);
    expect(selection.first.id, '1', reason: 'reading books lead the strip');
  });

  test('a small library with nothing recent has no activity', () {
    final books = [for (var i = 0; i < 4; i++) _book(id: '$i')];

    expect(RecentlyAddedCarousel.activitySelection(books), isEmpty);
  });

  test('a library that is mostly brand-new has no activity', () {
    // The strip would just duplicate the grid underneath.
    final books = [
      for (var i = 0; i < 12; i++)
        _book(id: '$i', addedAt: DateTime.now().subtract(Duration(hours: i))),
    ];

    expect(RecentlyAddedCarousel.activitySelection(books), isEmpty);
  });

  test('a settled library with a few recent additions has activity', () {
    final books = [
      for (var i = 0; i < 20; i++)
        _book(id: 'old$i', addedAt: DateTime.now().subtract(const Duration(days: 400))),
      _book(id: 'new1', addedAt: DateTime.now()),
      _book(id: 'new2', addedAt: DateTime.now()),
    ];

    expect(RecentlyAddedCarousel.activitySelection(books), isNotEmpty);
  });

  test('the selection honours the item cap', () {
    final books = [
      _book(id: 'r', status: 'reading', startedAt: DateTime.now()),
      for (var i = 0; i < 30; i++)
        _book(id: '$i', addedAt: DateTime.now().subtract(Duration(days: i))),
    ];

    expect(
      RecentlyAddedCarousel.activitySelection(books, maxItems: 5).length,
      5,
    );
  });
}
