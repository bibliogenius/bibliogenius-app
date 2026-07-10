/// Pure predicates behind the library list filters.
///
/// `owned` and `readingStatus` are orthogonal axes. A book read but not owned
/// ("read at a friend's", or borrowed, read and given back) is a first-class
/// state: it must stay reachable under its reading-status filter. Only the
/// default view filters on physical presence.
///
/// Extracted from `BookListScreen` so these rules can be tested directly.
library;

import '../models/book.dart';

/// Books shown when no status filter is selected: the ones the user physically
/// has. Wishlist and read-but-not-owned books are excluded on purpose.
///
/// A borrowed book is not owned and stays visible only because it is on loan,
/// so possession is read from the flags. It used to be read from
/// `readingStatus == 'borrowed'`, a value the backend wrote over the user's
/// real reading status.
///
/// [showBorrowed] mirrors the user setting that hides borrowed and lent books.
bool matchesDefaultView(Book book, {required bool showBorrowed}) {
  if (!showBorrowed && book.isOnLoan) return false;

  return book.owned || book.isOnLoan;
}

/// Books shown when [status] is explicitly selected in the dropdown.
///
/// The dropdown mixes two axes. "borrowed" and "lent" are possession, answered
/// by the copies; everything else is a reading status carried by the book. A
/// borrowed book you finished therefore matches both "borrowed" and "read".
///
/// Ownership is never a criterion for a reading status: a book the user read
/// without owning belongs under "read" like any other.
bool matchesStatusFilter(Book book, String status) {
  if (status == 'borrowed') return book.isBorrowed ?? false;
  if (status == 'lent') return book.isLent ?? false;
  if (status == 'uncategorized') {
    return book.readingStatus == null || book.readingStatus!.isEmpty;
  }
  return book.readingStatus == status;
}
