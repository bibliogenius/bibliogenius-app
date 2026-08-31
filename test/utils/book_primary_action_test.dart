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
  }) {
    return primaryActionForBook(
      readingStatus: readingStatus,
      owned: owned,
      hasBorrowedCopies: hasBorrowedCopies,
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

    test('a wished book leads with getting hold of it', () {
      expect(
        action(readingStatus: 'wanting', owned: false),
        BookPrimaryAction.acquire,
      );
    });

    test('the wish, not the absence of a copy, promotes acquisition', () {
      // A book read years ago and never owned is not a book one wants.
      // Deducing the intent from `owned == false` is the amalgam the peer
      // model forbids, and it would put a filled button on a large part of
      // the library. The path stays reachable, as a chip, on the page.
      expect(action(readingStatus: 'read', owned: false), BookPrimaryAction.none);
      expect(
        action(readingStatus: null, owned: false),
        BookPrimaryAction.startReading,
      );
      // Owned and still wished (a second copy) is not an acquisition either.
      expect(action(readingStatus: 'wanting'), BookPrimaryAction.none);
    });

    test('reading a book you do not own still offers to finish it', () {
      // Borrowing it again is not the next step once it is in your hands.
      expect(
        action(readingStatus: 'reading', owned: false),
        BookPrimaryAction.markFinished,
      );
    });

    test('acquisition does not depend on the borrow module', () {
      // The sheet behind it also carries library and bookshop searches and
      // the "I got it" pair, none of which is borrowing, so the ranking takes
      // no module flag at all.
      expect(
        action(readingStatus: 'wanting', owned: false),
        BookPrimaryAction.acquire,
      );
    });

    test('giving back outranks a wish on the same book', () {
      // Wished, and a borrowed copy on the shelf while waiting: returning what
      // is owed comes first.
      expect(
        action(readingStatus: 'wanting', owned: false, hasBorrowedCopies: true),
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
