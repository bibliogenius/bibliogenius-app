import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/utils/settings_search.dart';

void main() {
  group('settingsKeyMatches', () {
    const key = 'settings_linked_devices';
    const label = 'Synchroniser mes appareils';

    test('empty query matches everything', () {
      expect(settingsKeyMatches(key: key, label: label, query: ''), isTrue);
    });

    test('matches on the visible label (case-insensitive)', () {
      expect(
        settingsKeyMatches(key: key, label: label, query: 'SYNCHRON'),
        isTrue,
      );
    });

    test('matches on hidden synonyms not present in the label', () {
      // The regression we are fixing: these words do not appear in the French
      // label "Synchroniser mes appareils" but a user expects to find it.
      for (final term in ['appairage', 'pairing', 'code', 'wifi', 'tablette']) {
        expect(
          settingsKeyMatches(key: key, label: label, query: term),
          isTrue,
          reason: 'synonym "$term" should surface linked devices',
        );
      }
    });

    test('does not match an unrelated query', () {
      expect(
        settingsKeyMatches(key: key, label: label, query: 'gamification'),
        isFalse,
      );
    });

    test('a key without synonyms still matches on its label only', () {
      expect(
        settingsKeyMatches(
          key: 'some_key_without_synonyms',
          label: 'Hello World',
          query: 'world',
        ),
        isTrue,
      );
      expect(
        settingsKeyMatches(
          key: 'some_key_without_synonyms',
          label: 'Hello World',
          query: 'pairing',
        ),
        isFalse,
      );
    });

    test('every synonym entry points to a non-empty term list', () {
      for (final entry in settingsSearchSynonyms.entries) {
        expect(
          entry.value.trim(),
          isNotEmpty,
          reason: '${entry.key} has empty synonyms',
        );
      }
    });
  });
}
