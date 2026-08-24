import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/utils/book_filters.dart';
import 'package:flutter_test/flutter_test.dart';

Book book({
  required bool owned,
  String? status,
  bool? isBorrowed,
  bool? isLent,
  String title = 'Le Livre',
  String? author,
}) => Book(
  title: title,
  author: author,
  owned: owned,
  readingStatus: status,
  isBorrowed: isBorrowed,
  isLent: isLent,
);

void main() {
  group('shelfBooksHiddenByOwnership', () {
    // The reported case: a curated list imported as a wishlist files ten
    // books on the "Dystopie" shelf, and the shelf renders empty. Nothing
    // is broken: the import writes owned=false on purpose, the library list
    // applies the ownership axis BEFORE the shelf axis, and the Rust
    // subject_counts scopes its count the same way. Three deliberate rules
    // compose into a dead end, so the empty state has to be able to name it.
    bool onTheShelf(Book b) => b.title.startsWith('Dystopie');

    test('counts the shelf books the possession view hides', () {
      final books = [
        book(owned: false, status: 'wanting', title: 'Dystopie 1'),
        book(owned: false, status: 'wanting', title: 'Dystopie 2'),
        book(owned: true, title: 'Dystopie 3'),
        book(owned: false, status: 'wanting', title: 'Ailleurs'),
      ];

      expect(
        shelfBooksHiddenByOwnership(
          books: books,
          matchesShelf: onTheShelf,
          scope: OwnershipScope.library,
          showBorrowed: true,
        ),
        2,
        reason: 'Only the wishlist books ON the shelf count.',
      );
    });

    test('says nothing when the scope hides nothing', () {
      final books = [
        book(owned: false, status: 'wanting', title: 'Dystopie 1'),
      ];

      expect(
        shelfBooksHiddenByOwnership(
          books: books,
          matchesShelf: onTheShelf,
          scope: OwnershipScope.all,
          showBorrowed: true,
        ),
        0,
        reason: 'Under "all" the list already shows them, so there is no '
            'dead end to explain.',
      );
    });

    test('a shelf whose books are all present has nothing hidden', () {
      final books = [book(owned: true, title: 'Dystopie 3')];

      expect(
        shelfBooksHiddenByOwnership(
          books: books,
          matchesShelf: onTheShelf,
          scope: OwnershipScope.library,
          showBorrowed: true,
        ),
        0,
      );
    });

    test('it counts what the switch would actually reveal', () {
      // A lent book is hidden from the possession view by the borrowed
      // setting, and "all" filters nothing at all, so the switch DOES bring
      // it back. The count has to say so: an empty state offering a button
      // that reveals nothing would be worse than the dead end it replaces.
      final books = [book(owned: false, isLent: true, title: 'Dystopie 4')];

      expect(
        shelfBooksHiddenByOwnership(
          books: books,
          matchesShelf: onTheShelf,
          scope: OwnershipScope.library,
          showBorrowed: false,
        ),
        1,
      );
    });
  });

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
        matchesDefaultView(
          book(owned: false, isLent: true),
          showBorrowed: true,
        ),
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
        matchesDefaultView(
          book(owned: true, isLent: true),
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

    // Null flags mean "not computed". An owned book must not vanish because of
    // it, and an unowned one must not appear.
    test('unknown possession flags fall back to ownership', () {
      expect(
        matchesDefaultView(
          book(owned: true, status: 'read'),
          showBorrowed: true,
        ),
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

  // The explicit ownership axis (ADR-063), orthogonal to the status filter.
  group('matchesOwnershipFilter', () {
    test("'library' mirrors the default view", () {
      expect(
        matchesOwnershipFilter(
          book(owned: true),
          OwnershipScope.library,
          showBorrowed: true,
        ),
        isTrue,
      );
      expect(
        matchesOwnershipFilter(
          book(owned: false, status: 'wanting'),
          OwnershipScope.library,
          showBorrowed: true,
        ),
        isFalse,
      );
      expect(
        matchesOwnershipFilter(
          book(owned: false, isBorrowed: true),
          OwnershipScope.library,
          showBorrowed: true,
        ),
        isTrue,
        reason: 'a borrowed copy is physically on the shelf',
      );
    });

    test("'library' honours the hide-borrowed preference", () {
      expect(
        matchesOwnershipFilter(
          book(owned: false, isBorrowed: true),
          OwnershipScope.library,
          showBorrowed: false,
        ),
        isFalse,
      );
    });

    // The state that used to be inexpressible: not owned, whatever the status.
    test("'not_owned' matches neither owned nor on-loan books", () {
      expect(
        matchesOwnershipFilter(
          book(owned: false, status: 'wanting'),
          OwnershipScope.notOwned,
          showBorrowed: true,
        ),
        isTrue,
      );
      expect(
        matchesOwnershipFilter(
          book(owned: false, status: 'read'),
          OwnershipScope.notOwned,
          showBorrowed: true,
        ),
        isTrue,
        reason: 'read at a friend\'s: not owned, all statuses reachable',
      );
      expect(
        matchesOwnershipFilter(
          book(owned: true),
          OwnershipScope.notOwned,
          showBorrowed: true,
        ),
        isFalse,
      );
      expect(
        matchesOwnershipFilter(
          book(owned: false, isBorrowed: true),
          OwnershipScope.notOwned,
          showBorrowed: true,
        ),
        isFalse,
        reason: 'an on-loan copy is physically present, not "not owned"',
      );
    });

    test("'all' matches everything", () {
      for (final b in [
        book(owned: true),
        book(owned: false, status: 'wanting'),
        book(owned: false, isBorrowed: true),
      ]) {
        expect(
          matchesOwnershipFilter(b, OwnershipScope.all, showBorrowed: true),
          isTrue,
        );
      }
    });
  });

  group('resolveOwnershipScope', () {
    test('defaults to the physical library when browsing without a status', () {
      expect(resolveOwnershipScope(), OwnershipScope.library);
    });

    // Historical rule kept: a book read-but-not-owned must stay reachable
    // under its status filter, so a status alone never scopes to ownership.
    test('a status filter alone keeps every ownership reachable', () {
      expect(resolveOwnershipScope(status: 'read'), OwnershipScope.all);
    });

    test('an explicit user choice always wins', () {
      expect(
        resolveOwnershipScope(
          explicit: OwnershipScope.notOwned,
          status: 'read',
        ),
        OwnershipScope.notOwned,
      );
      expect(
        resolveOwnershipScope(explicit: OwnershipScope.library),
        OwnershipScope.library,
      );
    });
  });

  // Shared by the result grid and the autocomplete dropdown: the two used to
  // search different corpuses, and a wishlist book could appear in the
  // dropdown while the grid said "no books found" (ADR-063).
  group('matchesSearchQuery', () {
    test('matches on title, case-insensitive', () {
      expect(
        matchesSearchQuery(book(owned: true, title: 'Vaincre à Rome'), 'rome'),
        isTrue,
      );
      expect(
        matchesSearchQuery(book(owned: true, title: 'Vaincre à Rome'), 'dune'),
        isFalse,
      );
    });

    test('matches on author, case-insensitive', () {
      expect(
        matchesSearchQuery(
          book(owned: false, author: 'Sylvain Coher'),
          'coher',
        ),
        isTrue,
      );
    });

    test('a missing author never matches an author query', () {
      expect(matchesSearchQuery(book(owned: true), 'coher'), isFalse);
    });
  });
}
