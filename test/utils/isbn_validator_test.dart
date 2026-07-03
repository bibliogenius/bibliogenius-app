import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/utils/isbn_validator.dart';

void main() {
  // Canonical pair from the Wikipedia ISBN article.
  const isbn10 = '0306406152';
  const isbn13 = '9780306406157';

  group('IsbnValidator.toIsbn13', () {
    test('converts a valid ISBN-10 to its ISBN-13 form', () {
      expect(IsbnValidator.toIsbn13(isbn10), isbn13);
    });

    test('is the identity on a valid ISBN-13', () {
      expect(IsbnValidator.toIsbn13(isbn13), isbn13);
    });

    test('accepts hyphenated and spaced input', () {
      expect(IsbnValidator.toIsbn13('0-306-40615-2'), isbn13);
      expect(IsbnValidator.toIsbn13('978 0 306 40615 7'), isbn13);
    });

    test('handles an X check digit in ISBN-10', () {
      // 097522980X is the canonical X-check-digit example.
      expect(IsbnValidator.toIsbn13('097522980X'), '9780975229804');
      expect(IsbnValidator.toIsbn13('097522980x'), '9780975229804');
    });

    test('returns null for invalid or empty input', () {
      expect(IsbnValidator.toIsbn13(''), isNull);
      expect(IsbnValidator.toIsbn13('not-an-isbn'), isNull);
      expect(IsbnValidator.toIsbn13('12345'), isNull);
      // Valid length but wrong check digit.
      expect(IsbnValidator.toIsbn13('9780306406150'), isNull);
    });
  });

  group('IsbnValidator.canonicalKey', () {
    test('both forms of the same book share one key', () {
      expect(
        IsbnValidator.canonicalKey(isbn10),
        IsbnValidator.canonicalKey(isbn13),
      );
    });

    test('invalid or empty values pass through unchanged', () {
      expect(IsbnValidator.canonicalKey(''), '');
      expect(IsbnValidator.canonicalKey('not-an-isbn'), 'not-an-isbn');
    });

    test('two distinct invalid values never collide', () {
      expect(
        IsbnValidator.canonicalKey('bad-a'),
        isNot(IsbnValidator.canonicalKey('bad-b')),
      );
    });
  });
}
