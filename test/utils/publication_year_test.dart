import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/utils/publication_year.dart';

void main() {
  group('parsePublicationYear', () {
    test('parses a bare year', () {
      expect(parsePublicationYear('1998'), 1998);
    });

    test('parses an ISO date', () {
      expect(parsePublicationYear('2004-01-01'), 2004);
      expect(parsePublicationYear('2010-01'), 2010);
    });

    // The reported bug: OpenLibrary's free-text publish_date reached the year
    // field as its first four characters, i.e. a month prefix.
    test('parses a date that starts with a month name', () {
      expect(parsePublicationYear('Jan 01, 2004'), 2004);
      expect(parsePublicationYear('March 15, 2001'), 2001);
      expect(parsePublicationYear('1 janvier 2004'), 2004);
    });

    test('parses a year glued to a cataloguing prefix', () {
      expect(parsePublicationYear('c1998'), 1998);
      expect(parsePublicationYear('DL 2004'), 2004);
    });

    test('returns null when there is no year', () {
      expect(parsePublicationYear(null), isNull);
      expect(parsePublicationYear(''), isNull);
      expect(parsePublicationYear('Jan'), isNull);
      expect(parsePublicationYear('n/a'), isNull);
    });

    test('never truncates a digit group that is not a year', () {
      expect(parsePublicationYear('12345'), isNull);
      expect(parsePublicationYear('20045'), isNull);
      expect(parsePublicationYear('0042'), isNull);
    });
  });

  group('normalizePublicationYear', () {
    test('renders four digits', () {
      expect(normalizePublicationYear('Jan 01, 2004'), '2004');
    });

    test('returns null when there is no year', () {
      expect(normalizePublicationYear('n/a'), isNull);
    });
  });
}
