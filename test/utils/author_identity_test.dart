import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/utils/author_identity.dart';

/// ADR-061 section 7, decision A3: the author page derives its identity from
/// a FLATTENED author string, because `populate_authors` joins the Rust
/// `authors` list with ", " and `FrbBook` carries only the joined form.
///
/// The whole point of this file is that the two shapes below are
/// indistinguishable as strings and must not be treated alike:
///
///   "Le Guin, Ursula K."          one author, French cataloguing
///   "Ursula K. Le Guin, Alia Sun" two authors, joined by the FFI
///
/// The library's own vocabulary of individual author names (read off the
/// Rust identity keys) is what tells them apart.
void main() {
  // The author halves of "title|author" keys, exactly as
  // `title_author_keys` emits them: ONE per individual author.
  const libraryKeys = {
    'a wizard of earthsea|ursula k le guin',
    'the left hand of darkness|ursula k le guin',
    'the dispossessed|alia sun',
    'letranger|albert camus',
  };

  group('matchKey', () {
    test('folds an inverted name onto its natural order', () {
      expect(
        AuthorIdentity.matchKey('Le Guin, Ursula K.'),
        AuthorIdentity.matchKey('Ursula K. Le Guin'),
      );
    });

    test('does not merge two different people sharing words', () {
      expect(
        AuthorIdentity.matchKey('Alexandre Dumas'),
        isNot(AuthorIdentity.matchKey('Alexandre Dumas fils')),
      );
    });

    test('folds diacritics and punctuation like the discovery membrane', () {
      expect(
        AuthorIdentity.matchKey('Émile Zola'),
        AuthorIdentity.matchKey('emile  zola'),
      );
    });
  });

  group('vocabularyOf', () {
    test('keeps the author half of every identity key', () {
      expect(
        AuthorIdentity.vocabularyOf(libraryKeys),
        {
          AuthorIdentity.matchKey('Ursula K. Le Guin'),
          AuthorIdentity.matchKey('Alia Sun'),
          AuthorIdentity.matchKey('Albert Camus'),
        },
      );
    });

    test('ignores a malformed key rather than inventing an author', () {
      expect(AuthorIdentity.vocabularyOf({'no separator here'}), isEmpty);
    });
  });

  group('split', () {
    final vocabulary = AuthorIdentity.vocabularyOf(libraryKeys);

    test('a "Last, First" name stays ONE author', () {
      // The comma is part of the name, not a separator: neither "Le Guin"
      // nor "Ursula K." is a name the library knows. Splitting here is the
      // bug this rule exists to prevent (ApiService.getAllAuthors still has
      // it).
      expect(
        AuthorIdentity.split('Le Guin, Ursula K.', vocabulary),
        ['Le Guin, Ursula K.'],
      );
    });

    test('two co-signing authors split into two', () {
      expect(
        AuthorIdentity.split('Ursula K. Le Guin, Alia Sun', vocabulary),
        ['Ursula K. Le Guin', 'Alia Sun'],
      );
    });

    test('one part unknown to the library blocks the whole split', () {
      // Half-recognized is not recognized: falling back to the whole string
      // gives a narrow page, splitting would give a page naming nobody.
      expect(
        AuthorIdentity.split('Ursula K. Le Guin, Someone Unknown', vocabulary),
        ['Ursula K. Le Guin, Someone Unknown'],
      );
    });

    test('an empty vocabulary never splits (below the profile floor)', () {
      expect(
        AuthorIdentity.split('Ursula K. Le Guin, Alia Sun', const {}),
        ['Ursula K. Le Guin, Alia Sun'],
      );
    });

    test('a single name is returned trimmed', () {
      expect(AuthorIdentity.split('  Albert Camus  ', vocabulary), [
        'Albert Camus',
      ]);
    });

    test('no author at all yields no name', () {
      expect(AuthorIdentity.split(null, vocabulary), isEmpty);
      expect(AuthorIdentity.split('   ', vocabulary), isEmpty);
    });
  });

  group('names', () {
    final vocabulary = AuthorIdentity.vocabularyOf(libraryKeys);

    test('finds an author inside a co-signed book', () {
      expect(
        AuthorIdentity.names(
          'Ursula K. Le Guin, Alia Sun',
          AuthorIdentity.matchKey('Alia Sun'),
          vocabulary,
        ),
        isTrue,
      );
    });

    test('matches an inverted catalogue entry', () {
      expect(
        AuthorIdentity.names(
          'Le Guin, Ursula K.',
          AuthorIdentity.matchKey('Ursula K. Le Guin'),
          vocabulary,
        ),
        isTrue,
      );
    });

    test('does not match a substring of a longer name', () {
      // "Le Guin" alone is not the author of "Le Guin, Ursula K.": the
      // whole-string fallback compares whole names, never prefixes.
      expect(
        AuthorIdentity.names(
          'Le Guin, Ursula K.',
          AuthorIdentity.matchKey('Le Guin'),
          vocabulary,
        ),
        isFalse,
      );
    });

    test('an empty key never matches', () {
      expect(AuthorIdentity.names('Albert Camus', '', vocabulary), isFalse);
    });
  });
}
