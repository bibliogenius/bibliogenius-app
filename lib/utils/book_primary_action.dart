/// The single primary action a book detail page offers, derived from the
/// book's state.
///
/// The page used to stack up to five filled, full-width buttons — lend,
/// return, borrow, give back, sell — each in its own hardcoded colour, while
/// the reading cycle itself had no button at all: `_startReading` and
/// `_markAsFinished` existed on the screen and were never called, so marking a
/// book read meant opening the status picker. This inverts that: one primary
/// action, everything else demoted to the secondary row.
///
/// Kept out of the screen so the ranking is testable on its own and cannot
/// drift between the button and whatever else comes to depend on it.
library;

/// What the page's one primary button does, or that there is none.
enum BookPrimaryAction {
  /// A copy borrowed from someone else is on the shelf: giving it back
  /// outranks everything, it is the only action that is owed to another
  /// person.
  giveBack,

  /// Reading is under way; the next step is closing it.
  markFinished,

  /// The book is not owned and the borrow module is on: asking a contact for
  /// it is the way to get hold of it.
  borrowFromContact,

  /// Owned, unread: start the reading cycle.
  startReading,

  /// Nothing in the reading cycle is pending (read, abandoned, an inventory
  /// status...). The secondary row — edit, lend, copies — takes over, and the
  /// page shows no primary button at all rather than inventing one.
  none,
}

/// Ranks the states a book can be in and returns the one action that deserves
/// the primary button.
///
/// Lending is deliberately absent: it never depends on the reading status or
/// on the rating, only on owning a free copy with the module enabled, and it
/// lives in the secondary row for every state. Only its placement is ranked
/// here, never its existence.
BookPrimaryAction primaryActionForBook({
  required String? readingStatus,
  required bool owned,
  required bool hasBorrowedCopies,
  required bool canBorrow,
}) {
  if (hasBorrowedCopies) return BookPrimaryAction.giveBack;
  if (readingStatus == 'reading') return BookPrimaryAction.markFinished;
  // Matches the condition the standalone "Borrow from a contact" button
  // carried before it moved here, so no book loses the offer.
  if (!owned && canBorrow) return BookPrimaryAction.borrowFromContact;
  if (readingStatus == null ||
      readingStatus.isEmpty ||
      readingStatus == 'to_read') {
    return BookPrimaryAction.startReading;
  }
  return BookPrimaryAction.none;
}
