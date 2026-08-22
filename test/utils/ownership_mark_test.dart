import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/utils/ownership_mark.dart';
import 'package:flutter_test/flutter_test.dart';

Book book({required bool owned, String? status, bool? isBorrowed}) => Book(
  title: 'Le Livre',
  owned: owned,
  readingStatus: status,
  isBorrowed: isBorrowed,
);

void main() {
  group('ownershipMarkOf', () {
    test('an owned book carries no mark', () {
      expect(ownershipMarkOf(book(owned: true)), OwnershipMark.none);
    });

    // The loan badge already says where the book stands; stacking the
    // not-owned treatment on a physically present copy would be noise.
    test('an on-loan book carries no mark even though it is not owned', () {
      expect(
        ownershipMarkOf(book(owned: false, isBorrowed: true)),
        OwnershipMark.none,
      );
    });

    // ADR-063 settles the old disagreement between surfaces: a wished book
    // IS a not-owned book, marked as such PLUS its own wish marker.
    test('a wished book is a not-owned book with its wish marker', () {
      expect(
        ownershipMarkOf(book(owned: false, status: 'wanting')),
        OwnershipMark.wishedNotOwned,
      );
    });

    test('a book read without being owned is marked not owned', () {
      expect(
        ownershipMarkOf(book(owned: false, status: 'read')),
        OwnershipMark.notOwned,
      );
    });
  });

  group('ownershipMarkFromFlags', () {
    test('mirrors the Book-based selector', () {
      expect(ownershipMarkFromFlags(owned: true), OwnershipMark.none);
      expect(
        ownershipMarkFromFlags(owned: false, onLoan: true),
        OwnershipMark.none,
      );
      expect(ownershipMarkFromFlags(owned: false), OwnershipMark.notOwned);
      expect(
        ownershipMarkFromFlags(owned: false, wished: true),
        OwnershipMark.wishedNotOwned,
      );
    });
  });

  // A wished book's heart is already told by its wanting STATUS badge on the
  // surfaces that render one; badging it a second time put two hearts on the
  // same cover. The treatment (desaturation) is never affected.
  group('badgeMarkFor', () {
    test('a wished mark stands down next to a status badge', () {
      expect(
        badgeMarkFor(OwnershipMark.wishedNotOwned, statusBadgeShown: true),
        OwnershipMark.none,
      );
    });

    test('a wished mark keeps its badge on status-less surfaces', () {
      expect(
        badgeMarkFor(OwnershipMark.wishedNotOwned, statusBadgeShown: false),
        OwnershipMark.wishedNotOwned,
      );
    });

    test('a plain not-owned mark always badges: the status says read, not '
        'not-owned', () {
      expect(
        badgeMarkFor(OwnershipMark.notOwned, statusBadgeShown: true),
        OwnershipMark.notOwned,
      );
      expect(
        badgeMarkFor(OwnershipMark.none, statusBadgeShown: true),
        OwnershipMark.none,
      );
    });
  });

  group('saturationMatrix', () {
    test('full saturation is the identity matrix', () {
      final m = saturationMatrix(1.0);
      const identity = [
        1.0, 0.0, 0.0, 0.0, 0.0, //
        0.0, 1.0, 0.0, 0.0, 0.0, //
        0.0, 0.0, 1.0, 0.0, 0.0, //
        0.0, 0.0, 0.0, 1.0, 0.0,
      ];
      for (var i = 0; i < identity.length; i++) {
        expect(m[i], closeTo(identity[i], 1e-9));
      }
    });

    test('zero saturation weighs channels by Rec. 709 luma', () {
      final m = saturationMatrix(0.0);
      // Every color row collapses to the same luma weights.
      for (final row in [0, 5, 10]) {
        expect(m[row + 0], closeTo(0.2126, 1e-9));
        expect(m[row + 1], closeTo(0.7152, 1e-9));
        expect(m[row + 2], closeTo(0.0722, 1e-9));
      }
      // Alpha row untouched.
      expect(m[18], 1.0);
    });

    test('rows stay normalized for any saturation', () {
      // r+g+b of a color row must sum to 1 so white stays white.
      final m = saturationMatrix(notOwnedSaturation);
      expect(m[0] + m[1] + m[2], closeTo(1.0, 1e-9));
    });

    test(
      'the chosen treatment is partial, never opacity nor full grayscale',
      () {
        expect(notOwnedSaturation, greaterThan(0.0));
        expect(notOwnedSaturation, lessThan(1.0));
      },
    );
  });
}
