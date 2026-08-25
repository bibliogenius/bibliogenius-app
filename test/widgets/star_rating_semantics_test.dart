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

Future<void> _pump(WidgetTester tester, {int? rating}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: StarRatingWidget(rating: rating, onRatingChanged: (_) {}),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  testWidgets('the rating is announced through the translation catalogue', (
    tester,
  ) async {
    TranslationService.setPoTranslationsForTest({
      'en': {'rating_semantic_label': 'Rating: {rating} out of 5'},
    });

    await _pump(tester, rating: 7);

    // 7 on the 0-10 scale is 3.5 stars out of 5.
    expect(find.bySemanticsLabel('Rating: 3.5 out of 5'), findsOneWidget);
  });

  testWidgets('an unrated book announces zero rather than nothing', (
    tester,
  ) async {
    TranslationService.setPoTranslationsForTest({
      'en': {'rating_semantic_label': 'Rating: {rating} out of 5'},
    });

    await _pump(tester, rating: null);

    expect(find.bySemanticsLabel('Rating: 0.0 out of 5'), findsOneWidget);
  });
}
