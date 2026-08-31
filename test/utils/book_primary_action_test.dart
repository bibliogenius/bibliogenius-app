import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/utils/book_primary_action.dart';

/// Ranking cover for the book detail page's single primary action.
///
/// The rule these pin, and the reason the ranking exists at all: the reading
/// cycle had no button before this (its handlers were dead code), while
/// lending had up to five competing ones. Lending must stay reachable in every
/// state without ever becoming the primary action of a reading step, and it
/// must never depend on the rating.
void main() {
  BookPrimaryAction action({
    String? readingStatus,
    bool owned = true,
    bool hasBorrowedCopies = false,
    bool canBorrow = true,
  }) {
    return primaryActionForBook(
      readingStatus: readingStatus,
      owned: owned,
      hasBorrowedCopies: hasBorrowedCopies,
      canBorrow: canBorrow,
    );
  }

  group('reading cycle', () {
    test('an owned book with no status offers to start reading', () {
      expect(action(readingStatus: null), BookPrimaryAction.startReading);
      expect(action(readingStatus: ''), BookPrimaryAction.startReading);
      expect(action(readingStatus: 'to_read'), BookPrimaryAction.startReading);
    });

    test('a book being read offers to finish it', () {
      expect(action(readingStatus: 'reading'), BookPrimaryAction.markFinished);
    });

    test('a finished or abandoned book offers no primary action', () {
      expect(action(readingStatus: 'read'), BookPrimaryAction.none);
      expect(action(readingStatus: 'abandoned'), BookPrimaryAction.none);
    });

    test('an inventory status is left alone', () {
      // The librarian preset stores these in the same column; none of them is
      // a reading step, so none of them may produce a reading button.
      for (final status in ['available', 'checked_out', 'reference_only']) {
        expect(
          action(readingStatus: status),
          BookPrimaryAction.none,
          reason: '$status is an inventory state, not a reading step',
        );
      }
    });
  });

  group('borrowing', () {
    test('a borrowed copy outranks every reading step', () {
      for (final status in [null, 'to_read', 'reading', 'read']) {
        expect(
          action(readingStatus: status, hasBorrowedCopies: true),
          BookPrimaryAction.giveBack,
          reason: 'giving back what is owed comes first, whatever the status',
        );
      }
    });

    test('a book that is not owned offers to borrow it from a contact', () {
      expect(
        action(readingStatus: 'wanting', owned: false),
        BookPrimaryAction.borrowFromContact,
      );
      expect(
        action(readingStatus: null, owned: false),
        BookPrimaryAction.borrowFromContact,
      );
    });

    test('reading a book you do not own still offers to finish it', () {
      // Borrowing it again is not the next step once it is in your hands.
      expect(
        action(readingStatus: 'reading', owned: false),
        BookPrimaryAction.markFinished,
      );
    });

    test('the borrow offer disappears when the module is off', () {
      expect(
        action(readingStatus: 'wanting', owned: false, canBorrow: false),
        BookPrimaryAction.none,
        reason: 'a wanted book with borrowing off has no reading step either',
      );
      expect(
        action(readingStatus: 'to_read', owned: false, canBorrow: false),
        BookPrimaryAction.startReading,
      );
    });

    test('giving back does not depend on the borrow module being on', () {
      // The copy is already on the shelf: hiding the way to return it would
      // strand it, exactly as the standalone button did not gate on the module.
      expect(
        action(hasBorrowedCopies: true, canBorrow: false),
        BookPrimaryAction.giveBack,
      );
    });
  });

  test('an owned, rated or unrated finished book behaves the same', () {
    // The ranking takes no rating input at all: this pins that lending stays a
    // secondary chip in both cases rather than appearing once the book is
    // rated, which is what an earlier draft of the design implied.
    expect(action(readingStatus: 'read'), BookPrimaryAction.none);
    expect(action(readingStatus: 'read', owned: true), BookPrimaryAction.none);
  });
}
