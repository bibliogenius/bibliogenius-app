import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/utils/book_filters.dart';
import 'package:flutter_test/flutter_test.dart';

Book book({
  required bool owned,
  String? status,
  bool? isBorrowed,
  bool? isLent,
}) => Book(
  title: 'Le Livre',
  owned: owned,
  readingStatus: status,
  isBorrowed: isBorrowed,
  isLent: isLent,
);

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

    // "Empruntés" and "Prêtés" are possession filters, not reading statuses.
    // They read the flags; `reading_status` never carries those values.
    test('borrowed and lent match on the possession flags', () {
      expect(
        matchesStatusFilter(book(owned: false, isBorrowed: true), 'borrowed'),
        isTrue,
      );
      expect(
        matchesStatusFilter(book(owned: true, isLent: true), 'lent'),
        isTrue,
      );
    });

    test('a book is not borrowed just because it is lent, and vice versa', () {
      expect(
        matchesStatusFilter(book(owned: true, isLent: true), 'borrowed'),
        isFalse,
      );
      expect(
        matchesStatusFilter(book(owned: false, isBorrowed: true), 'lent'),
        isFalse,
      );
    });

    // The reason the whole overload had to go: possession used to mask the
    // reading status, so a borrowed book you finished never showed under "Lus".
    test('a borrowed book marked read appears under the read filter', () {
      final borrowedAndRead = book(
        owned: false,
        status: 'read',
        isBorrowed: true,
      );
      expect(matchesStatusFilter(borrowedAndRead, 'read'), isTrue);
      expect(matchesStatusFilter(borrowedAndRead, 'borrowed'), isTrue);
    });

    // Null means "the backend did not compute it", which must not read as true.
    test('an unknown possession flag matches no possession filter', () {
      expect(
        matchesStatusFilter(book(owned: true, status: 'read'), 'borrowed'),
        isFalse,
      );
      expect(
        matchesStatusFilter(book(owned: true, status: 'read'), 'lent'),
        isFalse,
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

    // A borrowed book is not owned. It stays in the default view only because
    // it is on loan: read the possession flag, never the reading status, or the
    // whole "Empruntés" shelf disappears from the library.
    test('shows borrowed and lent books even though they are not owned', () {
      expect(
        matchesDefaultView(
          book(owned: false, isBorrowed: true),
          showBorrowed: true,
        ),
        isTrue,
      );
      expect(
        matchesDefaultView(book(owned: false, isLent: true), showBorrowed: true),
        isTrue,
      );
    });

    // A book borrowed from a contact is stored as a permanent copy. It used to
    // carry no loan marker and, being unowned, vanished from the library.
    test('a borrowed book keeps its own reading status and stays visible', () {
      expect(
        matchesDefaultView(
          book(owned: false, status: 'read', isBorrowed: true),
          showBorrowed: true,
        ),
        isTrue,
      );
    });

    test('hides borrowed and lent when the setting is off', () {
      expect(
        matchesDefaultView(
          book(owned: false, isBorrowed: true),
          showBorrowed: false,
        ),
        isFalse,
      );
      expect(
        matchesDefaultView(book(owned: true, isLent: true), showBorrowed: false),
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

    // Null flags mean "not computed". An owned book must not vanish because of
    // it, and an unowned one must not appear.
    test('unknown possession flags fall back to ownership', () {
      expect(
        matchesDefaultView(book(owned: true, status: 'read'), showBorrowed: true),
        isTrue,
      );
      expect(
        matchesDefaultView(
          book(owned: false, status: 'read'),
          showBorrowed: true,
        ),
        isFalse,
      );
    });
  });
}
