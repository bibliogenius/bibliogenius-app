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

/// Values of the explicit ownership axis (ADR-063). Plain strings so they
/// travel through the `/books?owned=` deep link unchanged.
abstract final class OwnershipScope {
  static const String library = 'library';
  static const String notOwned = 'not_owned';
  static const String all = 'all';
  static const Set<String> values = {library, notOwned, all};
}

/// Effective ownership scope for the library list (ADR-063).
///
/// Once the user picks a value it is explicit and wins. Before that, the
/// historical behavior holds: browsing with no status filter shows the
/// physical library, while a status filter alone keeps every ownership
/// reachable (a book read but not owned must stay findable under "read").
String resolveOwnershipScope({String? explicit, String? status}) {
  if (explicit != null) return explicit;
  return status == null ? OwnershipScope.library : OwnershipScope.all;
}

/// Ownership axis predicate, orthogonal to the reading-status axis.
///
/// 'library' is the default view (physically present); 'not_owned' is its
/// exact complement before the [showBorrowed] preference (neither owned nor
/// on loan: wishlist, read at a friend's...); 'all' filters nothing.
bool matchesOwnershipFilter(
  Book book,
  String scope, {
  required bool showBorrowed,
}) {
  switch (scope) {
    case OwnershipScope.library:
      return matchesDefaultView(book, showBorrowed: showBorrowed);
    case OwnershipScope.notOwned:
      return !book.owned && !book.isOnLoan;
    default:
      return true;
  }
}

/// Books a shelf holds that the current ownership scope is hiding.
///
/// The library list applies the ownership axis BEFORE the shelf axis, so a
/// shelf filled entirely with books the reader does not own renders as "this
/// shelf is empty" with nothing to say why. That is not a bug in any one
/// rule: a curated list imported as a wishlist writes `owned = false` on
/// purpose, the possession view is the documented default (ADR-063), and the
/// Rust `subject_counts` scopes its badge the same way. Three deliberate
/// rules compose into a dead end, and this is what lets the empty state name
/// it and offer the way out.
///
/// Counts what switching to [OwnershipScope.all] would actually reveal, which
/// is why it measures the scope predicate rather than `owned` alone: a lent
/// book hidden by the borrowed setting comes back under "all" too. Returns 0
/// under a scope that hides nothing, where there is no dead end to explain.
int shelfBooksHiddenByOwnership({
  required Iterable<Book> books,
  required bool Function(Book book) matchesShelf,
  required String scope,
  required bool showBorrowed,
}) {
  if (scope == OwnershipScope.all) return 0;
  return books
      .where(matchesShelf)
      .where(
        (b) => !matchesOwnershipFilter(b, scope, showBorrowed: showBorrowed),
      )
      .length;
}

/// Search predicate shared by the result grid and the autocomplete dropdown.
///
/// The two MUST evaluate the same rule on the same corpus (ADR-063):
/// diverging predicates let a book appear as a suggestion while the grid
/// behind it says "no books found".
bool matchesSearchQuery(Book book, String query) {
  final q = query.toLowerCase();
  return book.title.toLowerCase().contains(q) ||
      (book.author?.toLowerCase().contains(q) ?? false);
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
