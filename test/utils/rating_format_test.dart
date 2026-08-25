import 'package:bibliogenius/utils/rating_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatStarRating', () {
    test('drops the decimal on a whole rating', () {
      // Ratings are stored 0-10 and halved, so one value in two is whole.
      // "4 out of 5" is what a reader expects to hear, not "4.0 out of 5".
      expect(formatStarRating(4.0, 'en'), '4');
      expect(formatStarRating(4.0, 'fr'), '4');
      expect(formatStarRating(0.0, 'fr'), '0');
      expect(formatStarRating(5.0, 'ja'), '5');
    });

    test('uses the locale decimal separator on a half rating', () {
      expect(formatStarRating(3.5, 'en'), '3.5');
      expect(formatStarRating(3.5, 'fr'), '3,5');
      expect(formatStarRating(3.5, 'de'), '3,5');
      expect(formatStarRating(3.5, 'tr'), '3,5');
      expect(formatStarRating(3.5, 'bg'), '3,5');
      expect(formatStarRating(3.5, 'es'), '3,5');
      expect(formatStarRating(3.5, 'it'), '3,5');
      expect(formatStarRating(3.5, 'ja'), '3.5');
      expect(formatStarRating(3.5, 'ko'), '3.5');
      expect(formatStarRating(3.5, 'zh'), '3.5');
    });

    test('accepts a BCP-47 tag with a dash', () {
      // Localizations.localeOf(context).toLanguageTag() yields `pt-BR`, while
      // intl canonicalises to `pt_BR`. The helper must not care.
      expect(formatStarRating(3.5, 'pt-BR'), '3,5');
      expect(formatStarRating(4.0, 'pt-BR'), '4');
    });

    test('falls back instead of throwing on an unknown locale', () {
      expect(() => formatStarRating(3.5, 'xx-YY'), returnsNormally);
      expect(() => formatStarRating(3.5, ''), returnsNormally);
    });

    test('the memoised formatter is invalidated when the locale changes', () {
      // The formatter is cached across calls, so a stale entry would render the
      // previous reader's separator. Alternate to pin the invalidation.
      expect(formatStarRating(3.5, 'fr'), '3,5');
      expect(formatStarRating(3.5, 'en'), '3.5');
      expect(formatStarRating(3.5, 'fr'), '3,5');
      expect(formatStarRating(4.0, 'fr'), '4');
      expect(formatStarRating(3.5, 'en'), '3.5');
    });

    test('never announces more than one decimal', () {
      expect(formatStarRating(3.25, 'en'), '3.3');
      expect(formatStarRating(2.999, 'en'), '3');
    });
  });
}
