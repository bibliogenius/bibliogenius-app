import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/utils/publisher_suggestions.dart';

void main() {
  group('distinctPublishers', () {
    test('drops empty names and trims spaces', () {
      expect(distinctPublishers([null, '', '  ', ' Seuil  ', 'Actes  Sud']), [
        'Actes Sud',
        'Seuil',
      ]);
    });

    test('one name per publisher, as most books spell it', () {
      expect(
        distinctPublishers([
          'gallimard',
          'Gallimard',
          'Gallimard',
          'Éditions de Minuit',
          'Editions de minuit',
        ]),
        // On a tie, the spelling met first wins.
        ['Éditions de Minuit', 'Gallimard'],
      );
    });

    test('sorted alphabetically, accents and case ignored', () {
      expect(distinctPublishers(['Seuil', 'éditions Allia', 'Actes Sud']), [
        'Actes Sud',
        'éditions Allia',
        'Seuil',
      ]);
    });
  });

  group('publisherSuggestions', () {
    const publishers = [
      'Actes Sud',
      'Éditions Gallimard',
      'Gallimard',
      'Gallimard Jeunesse',
      'Seuil',
    ];

    test('nothing typed, nothing suggested', () {
      expect(publisherSuggestions(publishers, '  '), isEmpty);
    });

    test('names starting with the text come before the others', () {
      expect(publisherSuggestions(publishers, 'gall'), [
        'Gallimard',
        'Gallimard Jeunesse',
        'Éditions Gallimard',
      ]);
    });

    test('accents and case do not matter', () {
      expect(publisherSuggestions(publishers, 'edi'), ['Éditions Gallimard']);
    });

    test('the name already typed is not offered again', () {
      expect(publisherSuggestions(publishers, 'Gallimard'), [
        'Gallimard Jeunesse',
        'Éditions Gallimard',
      ]);
    });

    test('a differently spelled name is offered in its library spelling', () {
      expect(publisherSuggestions(publishers, 'seuil'), ['Seuil']);
    });
  });
}
