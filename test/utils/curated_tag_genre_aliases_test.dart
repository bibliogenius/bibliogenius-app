import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/utils/book_genres.dart';
import 'package:bibliogenius/utils/curated_tag_genre_aliases.dart';

/// ADR-066: the bridge between the corpus's free-text tags and the app's
/// closed genre vocabulary, and the two guards that keep a hand-written
/// table honest.

/// Mirrors the Rust `FAVORITE_SHELF_LABELS`. A favorites shelf marks
/// affection, not theme; anything filed under it would make any two
/// favorites count as thematically similar (the ADR-059 poisoning rule).
const _favoriteLabels = {
  'favoris',
  'favori',
  'favorites',
  'favorite',
  'favourites',
};

/// Every tag carried by a list reachable through `index.yml`.
///
/// Read from disk rather than through the asset bundle on purpose: this is a
/// guard on the CORPUS, and it must see the files as they ship.
Set<String> _corpusTags() {
  final root = Directory('assets/curated_lists');
  final tags = <String>{};
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.yml')) continue;
    if (entity.path.endsWith('index.yml')) continue;
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].startsWith('tags:')) continue;
      final inline = lines[i].substring(5).trim();
      if (inline.startsWith('[')) {
        tags.addAll(
          inline
              .replaceAll(RegExp(r'[\[\]]'), '')
              .split(',')
              .map((t) => t.trim().replaceAll('"', '').replaceAll("'", ''))
              .where((t) => t.isNotEmpty),
        );
      } else {
        for (var j = i + 1; j < lines.length; j++) {
          final line = lines[j];
          if (line.trim().isEmpty) continue;
          if (!line.trimLeft().startsWith('- ')) break;
          tags.add(
            line.trim().substring(2).trim().replaceAll('"', '').replaceAll(
              "'",
              '',
            ),
          );
        }
      }
      break;
    }
  }
  return tags;
}

void main() {
  setUp(() {
    resetGenreLabelIndexForTest();
    TranslationService.setPoTranslationsForTest({});
  });

  group('normalization', () {
    test('folds case, diacritics and separators to one token', () {
      expect(normalizeGenreToken('Science-Fiction'), 'science fiction');
      expect(normalizeGenreToken('science fiction'), 'science fiction');
      expect(normalizeGenreToken('  Rentrée '), 'rentree');
      expect(normalizeGenreToken('XXe-siècle'), 'xxe siecle');
      expect(normalizeGenreToken('lgbtq+'), 'lgbtq');
      expect(normalizeGenreToken('   '), '');
    });
  });

  group('tags to genre keys', () {
    test('maps the corpus vocabulary the translations do not cover', () {
      expect(genreKeysForTags(['polar']), {'genre_detective'});
      expect(genreKeysForTags(['sf']), {'genre_scifi'});
      expect(genreKeysForTags(['shonen', 'seinen']), {'genre_manga'});
      expect(genreKeysForTags(['science-fiction']), {'genre_scifi'});
    });

    test('several tags collapse onto one key without duplicating it', () {
      expect(genreKeysForTags(['cuisine', 'gastronomie', 'recettes']), {
        'genre_cooking',
      });
    });

    test('a tag that names no genre contributes nothing', () {
      // The hundred tags that are prizes, languages, trades or school
      // levels. Those lists match through books-in-common instead.
      expect(
        genreKeysForTags(['prix', 'nobel', 'francais', 'backend', 'CM1']),
        isEmpty,
      );
    });

    test('`hugo` is a prize here, never Victor Hugo', () {
      expect(genreKeysForTags(['hugo', 'nebula']), isEmpty);
    });
  });

  group('stored labels back to genre keys (the language trap)', () {
    test('a genre filed in French is recognised by an English reader', () {
      TranslationService.setPoTranslationsForTest({
        'fr': {'genre_detective': 'Roman policier'},
        'en': {'genre_detective': 'Detective novel'},
      });
      resetGenreLabelIndexForTest();

      // The label as the French UI stored it, read back with no reference
      // to the current UI language: the KEY is the invariant.
      expect(genreKeysForStoredLabels(['Roman policier']), {
        'genre_detective',
      });
      expect(genreKeysForStoredLabels(['Detective novel']), {
        'genre_detective',
      });
    });

    test('a naive match would only have worked in one language', () {
      TranslationService.setPoTranslationsForTest({
        'fr': {'genre_scifi': 'Science-fiction'},
        'de': {'genre_scifi': 'Science-Fiction'},
        'es': {'genre_scifi': 'Ciencia ficción'},
      });
      resetGenreLabelIndexForTest();

      expect(genreKeysForStoredLabels(['Ciencia ficción']), {'genre_scifi'});
    });

    test("a reader's own shelf that names no genre is ignored", () {
      expect(genreKeysForStoredLabels(['Drupal', 'CMS', 'Littérature']), isEmpty);
    });
  });

  group('the poisoning rule', () {
    test('every value is a key of the closed genre list', () {
      final known = allBookGenres.map((g) => g.key).toSet();
      for (final entry in curatedTagGenreAliases.entries) {
        expect(
          known,
          contains(entry.value),
          reason:
              'Tag "${entry.key}" maps to "${entry.value}", which is not a '
              'genre of the closed list. A dead entry files nothing and '
              'nobody would notice.',
        );
      }
    });

    test('no genre label is favorites-like in any supported language', () {
      TranslationService.setPoTranslationsForTest({
        for (final locale in TranslationService.supportedLocales)
          locale: {
            for (final genre in allBookGenres) genre.key: 'Label ${genre.key}',
          },
      });
      resetGenreLabelIndexForTest();

      for (final genre in allBookGenres) {
        for (final alias in genreAliases(genre.key)) {
          expect(
            _favoriteLabels,
            isNot(contains(normalizeGenreToken(alias))),
            reason:
                'Genre ${genre.key} carries a favorites-like label. Filing '
                'imported books under it would make any two favorites read '
                'as thematically similar.',
          );
        }
      }
    });

    test('no alias key is itself favorites-like', () {
      for (final tag in curatedTagGenreAliases.keys) {
        expect(_favoriteLabels, isNot(contains(tag)));
      }
    });
  });

  group('the table stays live', () {
    test('every alias key is a tag the corpus actually carries', () {
      final corpus = _corpusTags().map(normalizeGenreToken).toSet();
      expect(corpus, isNotEmpty, reason: 'The corpus should be readable.');

      final orphans = curatedTagGenreAliases.keys
          .where((tag) => !corpus.contains(tag))
          .toList();
      expect(
        orphans,
        isEmpty,
        reason:
            'These alias entries name tags no list carries any more: '
            '$orphans. Remove them rather than letting the table accumulate '
            'entries for lists that were withdrawn.',
      );
    });
  });
}
