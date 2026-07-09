import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/utils/book_filters.dart';
import 'package:flutter_test/flutter_test.dart';

Book book({required bool owned, String? status}) =>
    Book(title: 'Le Livre', owned: owned, readingStatus: status);

void main() {
  group('matchesStatusFilter', () {
    // The reported bug: a book borrowed from a peer, read, then given back stays
    // in the library as owned=false + read. It used to appear under no filter at
    // all, which made it look deleted.
    test('a book read but not owned appears under the "read" filter', () {
      expect(
        matchesStatusFilter(book(owned: false, status: 'read'), 'read'),
        isTrue,
      );
    });

    test('reading and to_read behave the same regardless of ownership', () {
      for (final status in ['reading', 'to_read']) {
        expect(
          matchesStatusFilter(book(owned: false, status: status), status),
          isTrue,
        );
        expect(
          matchesStatusFilter(book(owned: true, status: status), status),
          isTrue,
        );
      }
    });

    test('uncategorized covers a null or empty status, owned or not', () {
      expect(
        matchesStatusFilter(book(owned: false, status: null), 'uncategorized'),
        isTrue,
      );
      expect(
        matchesStatusFilter(book(owned: false, status: ''), 'uncategorized'),
        isTrue,
      );
      expect(
        matchesStatusFilter(book(owned: true, status: null), 'uncategorized'),
        isTrue,
      );
    });

    test('a book with a status is never uncategorized', () {
      expect(
        matchesStatusFilter(
          book(owned: false, status: 'read'),
          'uncategorized',
        ),
        isFalse,
      );
    });

    // Dropping the `owned` condition must not leak the wishlist into other
    // filters: a wanting book carries its own status and stays in its own bucket.
    test('a wishlist book stays out of the read and uncategorized filters', () {
      final wishlist = book(owned: false, status: 'wanting');
      expect(matchesStatusFilter(wishlist, 'wanting'), isTrue);
      expect(matchesStatusFilter(wishlist, 'read'), isFalse);
      expect(matchesStatusFilter(wishlist, 'uncategorized'), isFalse);
    });

    test('borrowed and lent keep matching their own filter', () {
      expect(
        matchesStatusFilter(book(owned: false, status: 'borrowed'), 'borrowed'),
        isTrue,
      );
      expect(
        matchesStatusFilter(book(owned: true, status: 'lent'), 'lent'),
        isTrue,
      );
    });
  });

  group('matchesDefaultView', () {
    test('hides a book that is read but not owned', () {
      expect(
        matchesDefaultView(
          book(owned: false, status: 'read'),
          showBorrowed: true,
        ),
        isFalse,
        reason: 'the default view shows what the user physically has',
      );
    });

    test('shows owned books', () {
      expect(
        matchesDefaultView(
          book(owned: true, status: 'read'),
          showBorrowed: true,
        ),
        isTrue,
      );
    });

    test('shows borrowed and lent books even though they are not owned', () {
      expect(
        matchesDefaultView(
          book(owned: false, status: 'borrowed'),
          showBorrowed: true,
        ),
        isTrue,
      );
      expect(
        matchesDefaultView(
          book(owned: false, status: 'lent'),
          showBorrowed: true,
        ),
        isTrue,
      );
    });

    test('hides borrowed and lent when the setting is off', () {
      expect(
        matchesDefaultView(
          book(owned: false, status: 'borrowed'),
          showBorrowed: false,
        ),
        isFalse,
      );
      expect(
        matchesDefaultView(
          book(owned: true, status: 'lent'),
          showBorrowed: false,
        ),
        isFalse,
        reason: 'the setting hides lent books even when the copy is owned',
      );
    });

    test('hides the wishlist', () {
      expect(
        matchesDefaultView(
          book(owned: false, status: 'wanting'),
          showBorrowed: true,
        ),
        isFalse,
      );
    });
  });
}
