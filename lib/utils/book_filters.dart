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
/// [showBorrowed] mirrors the user setting that hides borrowed and lent books.
bool matchesDefaultView(Book book, {required bool showBorrowed}) {
  final isBorrowedOrLent =
      book.readingStatus == 'borrowed' || book.readingStatus == 'lent';

  if (!showBorrowed && isBorrowedOrLent) return false;

  return book.owned || isBorrowedOrLent;
}

/// Books shown when [status] is explicitly selected in the dropdown.
///
/// Ownership is never a criterion here: these are reading-status filters, and a
/// book the user read without owning belongs under "read" like any other.
bool matchesStatusFilter(Book book, String status) {
  if (status == 'uncategorized') {
    return book.readingStatus == null || book.readingStatus!.isEmpty;
  }
  return book.readingStatus == status;
}
