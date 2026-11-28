import 'package:bibliogenius/utils/book_status.dart';
import 'package:flutter/material.dart';
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

    // The service gate accepts these five (`models::book::READING_STATUSES`),
    // the statistics charts colour them, the CSV export translates them and the
    // MCP filter enumerates them. A value the whole stack knows about but the
    // picker never offers is worse than absent: `edit_book_screen` builds its
    // `validStatuses` from this very list and silently rewrites anything it
    // does not recognise back to the default, so a book that reached that state
    // by any other route loses it on the next save.
    test('every stored reading status is offered', () {
      const storedByTheServiceGate = [
        'to_read',
        'reading',
        'read',
        'wanting',
        'abandoned',
      ];

      final offered = individualStatuses.map((s) => s.value).toSet();

      for (final status in storedByTheServiceGate) {
        expect(
          offered,
          contains(status),
          reason:
              '$status is accepted by the backend but unreachable from the UI',
        );
      }
    });

    // Chips sit side by side: two entries sharing a colour make the row
    // unreadable, and the reader cannot tell which one is selected at a glance.
    test('no two offered statuses share a colour', () {
      final colours = individualStatuses.map((s) => s.color).toList();

      expect(
        colours.toSet().length,
        colours.length,
        reason: 'each chip must be distinguishable from its neighbours',
      );
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

  // A status pill is white or black text in 10 px bold, which WCAG 2.1 AA
  // (RGAA 3.2) holds to 4.5:1. The grid, the list and the dashboard all draw
  // their pill from this one rule, so it is checked here once for every status.
  group('statusBadgeColors', () {
    for (final status in [...individualStatuses, ...librarianStatuses]) {
      test('the ${status.value} pill text reaches 4.5:1', () {
        final colors = statusBadgeColors(status);
        expect(
          colors.background.a,
          1.0,
          reason:
              'a translucent fill lets '
              'the cover underneath change the contrast',
        );
        expect(
          textContrastRatio(colors.foreground, colors.background),
          greaterThanOrEqualTo(4.5),
        );
      });
    }

    // The pill keeps the bright status colour, the one the grid always wore,
    // so it stands out on a cover. Contrast is luminance alone and white on
    // bright blue stops at 3.1:1, so the text turns dark rather than the fill:
    // a dark shade of the pill's own hue, softer than black, with a margin
    // above the floor.
    for (final (value, hue) in [
      ('reading', Colors.blue),
      ('to_read', Colors.orange),
      ('read', Colors.green),
    ]) {
      test('the $value pill stays bright, with dark text of its hue', () {
        final colors = statusBadgeColors(
          individualStatuses.firstWhere((s) => s.value == value),
        );
        expect(colors.background.toARGB32(), hue.toARGB32());
        expect(colors.foreground, isNot(Colors.black));
        expect(
          HSLColor.fromColor(colors.foreground).hue,
          closeTo(HSLColor.fromColor(hue).hue, 1),
        );
        expect(
          textContrastRatio(colors.foreground, colors.background),
          greaterThanOrEqualTo(5.0),
        );
      });
    }

    // A deep hue keeps the white text it reads best in.
    test('the brown abandoned pill keeps white text', () {
      final colors = statusBadgeColors(
        individualStatuses.firstWhere((s) => s.value == 'abandoned'),
      );
      expect(colors.background.toARGB32(), Colors.brown.toARGB32());
      expect(colors.foreground, Colors.white);
    });

    // A value outside the active vocabulary (a reading status while the
    // cataloguing statuses are on) still gets a compliant, neutral pill.
    test('an unknown status falls back on a neutral pill', () {
      final colors = statusBadgeColors(null);
      expect(colors.background.toARGB32(), Colors.blueGrey.toARGB32());
      expect(
        textContrastRatio(colors.foreground, colors.background),
        greaterThanOrEqualTo(4.5),
      );
    });
  });
}
