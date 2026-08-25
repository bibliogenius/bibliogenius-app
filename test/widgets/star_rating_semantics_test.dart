import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/star_rating_widget.dart';

/// Accessibility cover for the star rating (Rule A4: every `semanticLabel` goes
/// through `TranslationService`, with keys in the catalogues).
///
/// The label used to be a hardcoded French string, so a screen reader announced
/// French to every reader whatever their locale, and the value could not be
/// corrected without a code change.

const _catalogues = {
  'en': {'rating_semantic_label': 'Rating: {rating} out of 5'},
  'fr': {'rating_semantic_label': 'Note : {rating} sur 5'},
};

/// Pumps [child] with a ThemeProvider already on [languageCode].
///
/// The locale is settled BEFORE the first frame on purpose, twice over: the
/// stored preference drives the provider's async startup load, and
/// `setLocaleSync` gives the first frame the right value without waiting for
/// it. Flipping the language after the first pump would not work:
/// `TranslationService.translate` reads the provider with `listen: false`, so
/// nothing rebuilds and the assertion would silently run on the old language.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  String languageCode = 'en',
}) async {
  SharedPreferences.setMockInitialValues({'languageCode': languageCode});
  final provider = ThemeProvider()..setLocaleSync(Locale(languageCode));
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>.value(
      value: provider,
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pump();
}

Future<void> _pumpStars(
  WidgetTester tester, {
  int? rating,
  String languageCode = 'en',
}) => _pump(
  tester,
  StarRatingWidget(rating: rating, onRatingChanged: (_) {}),
  languageCode: languageCode,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest(_catalogues);
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  testWidgets('the rating is announced through the translation catalogue', (
    tester,
  ) async {
    await _pumpStars(tester, rating: 7);

    // 7 on the 0-10 scale is 3.5 stars out of 5.
    expect(find.bySemanticsLabel('Rating: 3.5 out of 5'), findsOneWidget);
  });

  testWidgets('an unrated book announces zero rather than nothing', (
    tester,
  ) async {
    await _pumpStars(tester, rating: null);

    // "0", not "0.0": a whole rating carries no decimal. Half of all ratings
    // are whole (the 0-10 scale is halved), so this is the common case.
    expect(find.bySemanticsLabel('Rating: 0 out of 5'), findsOneWidget);
  });

  testWidgets('a whole rating drops its decimal', (tester) async {
    await _pumpStars(tester, rating: 8);

    expect(find.bySemanticsLabel('Rating: 4 out of 5'), findsOneWidget);
  });

  testWidgets('the decimal separator follows the reader locale', (
    tester,
  ) async {
    // `toStringAsFixed` always emitted a dot, so a French reader was read a
    // separator their language does not use.
    await _pumpStars(tester, rating: 7, languageCode: 'fr');

    expect(find.bySemanticsLabel('Note : 3,5 sur 5'), findsOneWidget);
  });
}
