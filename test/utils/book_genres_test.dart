import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/utils/book_genres.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the real catalogues so the uniqueness guard runs against the labels
/// actually shipped, not against a fixture.
Future<void> _loadRealCatalogues() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await TranslationService.loadTranslations();
}

void main() {
  group('taxonomy shape', () {
    test('every genre key is unique', () {
      final keys = allBookGenres.map((g) => g.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('parentOfGenre links a subgenre back to its genre', () {
      final thriller = allBookGenres.firstWhere((g) => g.key == 'genre_thriller');
      expect(parentOfGenre(thriller)?.key, 'genre_crime');

      final crime = allBookGenres.firstWhere((g) => g.key == 'genre_crime');
      expect(parentOfGenre(crime), isNull);
    });

    test('only top-level genres carry a chip icon', () {
      for (final genre in bookGenres) {
        expect(genre.icon, isNotNull, reason: '${genre.key} is a chip');
        for (final child in genre.children) {
          expect(child.icon, isNull, reason: '${child.key} is a subgenre');
        }
      }
    });
  });

  group('labels vs the UNIQUE(name) constraint on tags', () {
    setUpAll(_loadRealCatalogues);

    // `tags.name` is unique across the whole tree, so two genres sharing a label
    // could never coexist as shelves: the second one would collide with the
    // first. Guard the shipped catalogues, in every language.
    for (final locale in TranslationService.supportedLocales) {
      test('no two genres share a label in $locale', () {
        final labels = <String, String>{};

        for (final genre in [...allBookGenres.map((g) => g.key), genreRootKey]) {
          final label = TranslationService.translateByLocale(locale, genre)
              .trim()
              .toLowerCase();

          expect(
            label,
            isNot(genre),
            reason: '$genre has no $locale translation',
          );
          expect(
            labels,
            isNot(contains(label)),
            reason: '$genre collides with ${labels[label]} on "$label"',
          );
          labels[label] = genre;
        }
      });
    }
  });

  group('selectedGenres', () {
    setUp(() {
      TranslationService.setPoTranslationsForTest({
        'en': {'genre_crime': 'Crime & thriller', 'genre_thriller': 'Thriller'},
        'fr': {'genre_crime': 'Polar & thriller', 'genre_thriller': 'Thriller'},
      });
    });

    test('recognises a genre filed in another language', () {
      // The shelf keeps the label it was created with. A library filed in French
      // and later read in English must still light its "Crime & thriller" chip.
      final found = selectedGenres(['Polar & thriller']);

      expect(found.map((g) => g.key), ['genre_crime']);
    });

    test('ignores the user own shelves', () {
      expect(selectedGenres(['À relire cet été', 'Prêté à Paul']), isEmpty);
    });

    test('returns nothing for a book with no shelf', () {
      expect(selectedGenres([]), isEmpty);
    });
  });
}
