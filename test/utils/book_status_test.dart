import 'package:bibliogenius/utils/book_status.dart';
import 'package:flutter_test/flutter_test.dart';

// The absence of a reading status is a value the reader picks, not a gap in
// the data. It has to be spelled the same way everywhere: the empty string,
// never null, because the column it lands in is NOT NULL and a book decoded
// from any payload always carries the field.
void main() {
  group('the personal reading vocabulary', () {
    test('offers the absence of a status', () {
      expect(individualStatuses.map((s) => s.value), contains(noReadingStatus));
    });

    // The cataloguing list describes a copy on a shelf, not a reader: every
    // item there is a positive state and none of them may be blank.
    test('the cataloguing list has no blank entry', () {
      expect(librarianStatuses.any((s) => s.value == noReadingStatus), isFalse);
    });

    // Creating a book still commits to a status; only clearing one later
    // produces the absence.
    test('neither default status is the absence', () {
      expect(getDefaultStatus(false), isNot(noReadingStatus));
      expect(getDefaultStatus(true), isNot(noReadingStatus));
    });
  });

  // The statistics charts tally the RAW column, which is reached by cr-sqlite
  // replication and by the possession values older payloads overlaid onto it,
  // not only by the picker. Every bucket it draws has to name itself.
  group('tallying reading statuses for the charts', () {
    test('a cleared status and an absent one share one bucket', () {
      final counts = tallyReadingStatuses([null, '', 'read']);

      expect(counts[noReadingStatus], 2);
      expect(counts['read'], 1);
      expect(counts.length, 2);
    });

    test('every book lands in exactly one bucket', () {
      final statuses = <String?>['read', 'read', null, '', 'wanting', 'lent'];

      final counts = tallyReadingStatuses(statuses);

      expect(
        counts.values.fold<int>(0, (sum, n) => sum + n),
        statuses.length,
        reason: 'the slices must add up to the library',
      );
    });

    test('an empty library tallies nothing', () {
      expect(tallyReadingStatuses(const <String?>[]), isEmpty);
    });
  });

  group('readingStatusLabelKey', () {
    test('the absence of a status is named, not left blank', () {
      expect(readingStatusLabelKey(noReadingStatus), 'no_reading_status');
    });

    test('every offered status is named', () {
      for (final s in individualStatuses) {
        expect(readingStatusLabelKey(s.value), isNotNull, reason: s.label);
      }
    });

    // Never stored by the service gate, but `populate_authors` overlays them
    // on the HTTP/MCP path and old payloads carried them in this column.
    test('the possession values older payloads overlaid are named', () {
      expect(readingStatusLabelKey('borrowed'), 'reading_status_borrowed');
      expect(readingStatusLabelKey('lent'), 'reading_status_lent');
      expect(readingStatusLabelKey('owned'), 'owned_status');
    });

    // The caller's cue to print the raw token instead of an empty label.
    test('a value from no vocabulary we know returns null', () {
      expect(readingStatusLabelKey('some_future_status'), isNull);
    });
  });

  group('hasReadingStatus', () {
    // Badges key on this rather than on a null check: a book whose status was
    // explicitly cleared carries an empty string, and rendering a badge for it
    // prints an untranslated `reading_status_` and claims a state the book
    // does not have.
    test('an empty status is no status', () {
      expect(hasReadingStatus(''), isFalse);
    });

    test('an absent status is no status', () {
      expect(hasReadingStatus(null), isFalse);
    });

    test('a real status is one', () {
      for (final s in individualStatuses.where(
        (s) => s.value != noReadingStatus,
      )) {
        expect(hasReadingStatus(s.value), isTrue, reason: s.label);
      }
    });
  });
}
