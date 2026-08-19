// Test to validate all curated list YAML assets parse correctly
// This ensures no runtime errors when users browse curated lists

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';
import 'package:bibliogenius/services/curated_lists_service.dart';
import 'package:bibliogenius/utils/isbn_validator.dart';

/// ISBNs already in the catalogue that fail their own check digit. See the
/// comment at the assertion that uses this set.
const knownBadLegacyIsbns = <String>{
  '9782253059536', // genres/romans-historiques
  '9781033903178', // genres/thriller-psychologique
  '9781789537965', // tech/programming-drupal
  '9781594200318', // themes/cuisine-gastronomie
  '9782874950317', // themes/histoire-essentiels
  // Three more live in lists index.yml has commented out
  // (classics/guardian-100-21st-century, themes/dev-personnel-classiques).
  // They are deliberately NOT listed here: re-enabling one of those lists
  // should fail this test until its ISBNs are sourced again.
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Curated Lists Validation', () {
    test('index.yml parses correctly', () async {
      final indexYaml = await rootBundle.loadString(
        'assets/curated_lists/index.yml',
      );
      final parsed = loadYaml(indexYaml) as YamlMap;

      expect(parsed['version'], isNotNull);
      expect(parsed['categories'], isA<YamlList>());
      expect((parsed['categories'] as YamlList).length, greaterThan(0));
    });

    test('all category lists have valid references', () async {
      final indexYaml = await rootBundle.loadString(
        'assets/curated_lists/index.yml',
      );
      final parsed = loadYaml(indexYaml) as YamlMap;
      final categories = parsed['categories'] as YamlList;

      for (final category in categories) {
        final cat = category as YamlMap;
        expect(cat['id'], isNotNull, reason: 'Category must have id');
        expect(cat['title'], isNotNull, reason: 'Category must have title');
        expect(
          cat['lists'],
          isA<YamlList>(),
          reason: 'Category must have lists',
        );
      }
    });

    // Test a sample list to validate structure
    test('goncourt.yml has valid structure', () async {
      final listYaml = await rootBundle.loadString(
        'assets/curated_lists/awards/goncourt.yml',
      );
      final parsed = loadYaml(listYaml) as YamlMap;

      expect(parsed['id'], equals('goncourt'));
      expect(parsed['title'], isNotNull);
      expect(parsed['description'], isNotNull);
      expect(parsed['books'], isA<YamlList>());
      expect((parsed['books'] as YamlList).length, greaterThan(0));
    });
  });

  group('Curated Lists Asset Bundling', () {
    // Two independent things must line up for a category to render, and
    // neither failure produces a build error or an analyzer warning:
    //  1. its directory is declared under `flutter: assets:` in pubspec.yaml,
    //     otherwise the YAML is absent from the bundle;
    //  2. its directory name is listed in `loadList`'s `directories` array,
    //     which is hardcoded and NOT derived from the category ids.
    // Going through the real service covers both. Reading rootBundle directly
    // only covers the first, and passes while the category shows up empty.
    test('every category resolves all the lists index.yml declares', () async {
      final service = CuratedListsService.instance;
      service.clearCache();
      final categories = await service.loadCategories();

      expect(categories, isNotEmpty, reason: 'index.yml declared no category');

      for (final category in categories) {
        final lists = await service.loadListsForCategory(category);
        final resolved = lists.map((l) => l.id).toSet();
        final missing = category.listIds.where((id) => !resolved.contains(id));

        expect(
          missing,
          isEmpty,
          reason:
              'Category "${category.id}" declares ${category.listIds.length} '
              'list(s) but resolved ${lists.length}. Unresolved: '
              '${missing.join(', ')}. Check that '
              '"assets/curated_lists/${category.id}/" is declared under '
              'flutter > assets in pubspec.yaml AND that "${category.id}" is '
              'in the directories array of CuratedListsService.loadList.',
        );

        for (final list in lists) {
          expect(
            list.books,
            isNotEmpty,
            reason: '${category.id}/${list.id} has an empty books list',
          );
        }
      }
    });

    // Editorial decision, not an oversight: the `rentree` category keeps a
    // French-only title so its chip does not invite readers with no French
    // into a French-curriculum list. `partitionCuratedListsByLanguage` never
    // hides a list, and a category with nothing in the reader's languages
    // renders expanded, so the chip label is the only honest signal left.
    // Delete this test if that decision is reversed.
    test('the rentree chip stays in French for every locale', () async {
      final service = CuratedListsService.instance;
      final categories = await service.loadCategories();
      final rentree = categories.firstWhere((c) => c.id == 'rentree');

      for (final locale in ['fr', 'en', 'es', 'de', 'it']) {
        expect(
          rentree.getTitle(locale),
          equals('Rentrée des classes'),
          reason:
              'Adding a "$locale" title to the rentree category in index.yml '
              'makes the chip advertise content that does not exist in that '
              'language.',
        );
      }
    });

    // The import service falls back to the title parsed out of `note` when the
    // ISBN lookup returns nothing, and the backend refuses books without a
    // title. An entry with a malformed ISBN and no note fails to import.
    test('every curated book has a well-formed ISBN', () async {
      final service = CuratedListsService.instance;
      final categories = await service.loadCategories();

      for (final category in categories) {
        for (final list in await service.loadListsForCategory(category)) {
          for (final book in list.books) {
            final clean = book.isbn.replaceAll(RegExp(r'[^0-9X]'), '');
            expect(
              clean.length,
              anyOf(10, 13),
              reason:
                  '${category.id}/${list.id}: "${book.isbn}" is not a 10 or '
                  '13 character ISBN',
            );
            // Length alone is not enough: a typo inside the digits keeps the
            // length and still points at nothing. A curated entry whose ISBN
            // does not resolve fails its import outright, because the backend
            // refuses books without a title.
            //
            // Ratchet, not a clean sweep: five entries authored before this
            // check already fail it. Measured 2026-08-19: 8 invalid ISBNs out
            // of 894 across every list, five in lists index.yml loads and three
            // in lists it has commented out.
            // They are named here so the debt stays visible and cannot grow,
            // rather than weakening the assertion for everyone. Fixing them
            // means sourcing a real edition per title, which is content work,
            // not a test change. Remove an entry from this set as it is fixed.
            if (!knownBadLegacyIsbns.contains(clean)) {
              expect(
                IsbnValidator.isValid(clean),
                isTrue,
                reason:
                    '${category.id}/${list.id}: "${book.isbn}" fails its own '
                    'ISBN check digit, so it identifies no real edition',
              );
            }
          }
        }
      }
    });
  });
}
