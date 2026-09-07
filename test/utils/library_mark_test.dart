import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/utils/library_mark.dart';

void main() {
  group('libraryMarkFor', () {
    test('says nothing about a book the library never met', () {
      expect(libraryMarkFor(owned: null, readingStatus: null), isNull);
    });

    test('possession outranks the reading state', () {
      expect(
        libraryMarkFor(owned: true, readingStatus: 'to_read'),
        LibraryMark.owned,
      );
      expect(
        libraryMarkFor(owned: true, readingStatus: 'read'),
        LibraryMark.ownedAndRead,
      );
    });

    test('a book read without being owned reads as read', () {
      expect(
        libraryMarkFor(owned: false, readingStatus: 'read'),
        LibraryMark.read,
      );
    });

    test('a wish is a wish, not a book on the shelf', () {
      expect(
        libraryMarkFor(owned: false, readingStatus: 'wanting'),
        LibraryMark.wanted,
      );
    });

    test('an unowned book with no reading intent says nothing', () {
      // A copy borrowed from someone else, or a row with no status: the peer
      // screen already speaks about loans, and a second badge would confuse.
      expect(libraryMarkFor(owned: false, readingStatus: ''), isNull);
      expect(libraryMarkFor(owned: false, readingStatus: 'to_read'), isNull);
    });

    test('a reading recorded during this visit counts before the refetch', () {
      expect(
        libraryMarkFor(
          owned: null,
          readingStatus: null,
          recordedReadHere: true,
        ),
        LibraryMark.read,
      );
      expect(
        libraryMarkFor(
          owned: true,
          readingStatus: 'to_read',
          recordedReadHere: true,
        ),
        LibraryMark.ownedAndRead,
      );
    });
  });
}
