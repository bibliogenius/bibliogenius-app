import 'package:bibliogenius/providers/hangman_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HangmanProvider hint availability', () {
    test('an empty or blank author is not a hint', () {
      expect(HangmanProvider.hasAuthorHint(''), isFalse);
      expect(HangmanProvider.hasAuthorHint('   '), isFalse);
      expect(HangmanProvider.hasAuthorHint('Ursula K. Le Guin'), isTrue);
    });

    test('a null, empty or blank cover is not a hint', () {
      expect(HangmanProvider.hasCoverHint(null), isFalse);
      expect(HangmanProvider.hasCoverHint(''), isFalse);
      expect(HangmanProvider.hasCoverHint('  '), isFalse);
      expect(
        HangmanProvider.hasCoverHint('https://covers.example/1.jpg'),
        isTrue,
      );
    });
  });
}
