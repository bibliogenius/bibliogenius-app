import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/book_rating_row.dart';
import 'package:bibliogenius/widgets/star_rating_widget.dart';

/// Layout cover for the rating / pages pair of the book detail metadata card.
///
/// The five stars have a fixed intrinsic width, so splitting the row into two
/// equal halves left them wider than their half on a phone: the last star
/// painted on top of the page count. These pin the two properties that defect
/// broke - the star row stays inside its own column, and it never reaches the
/// page count.

/// Inner width of the metadata card on a given screen width: the detail page
/// pads by 24 on each side and the card by another 20.
double _cardInnerWidth(double screenWidth) => screenWidth - 2 * 24 - 2 * 20;

Future<void> _pump(
  WidgetTester tester, {
  required double screenWidth,
  int? rating,
  int? pageCount = 247,
  double textScale = 1.0,
  ValueChanged<int?>? onRatingChanged,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: _cardInnerWidth(screenWidth),
                child: BookRatingRow(
                  rating: rating,
                  pageCount: pageCount,
                  onRatingChanged: onRatingChanged ?? (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {'rating_label': 'My rating', 'page_count_label': 'Pages'},
    });
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  // 393 is the iPhone 15 / 16 logical width the defect was reported on; 320 is
  // the narrowest phone still supported.
  for (final screenWidth in <double>[393, 375, 320]) {
    testWidgets('stars stay clear of the page count at ${screenWidth}px', (
      tester,
    ) async {
      await _pump(tester, screenWidth: screenWidth);

      final stars = tester.getRect(find.byType(StarRatingWidget));
      final pageCount = tester.getRect(find.text('247'));

      expect(
        stars.right,
        lessThanOrEqualTo(pageCount.left - BookRatingRow.gutter),
        reason: 'the last star must stay a gutter clear of the page count',
      );
    });

    testWidgets(
      'the star row does not overflow its column at ${screenWidth}px',
      (tester) async {
        await _pump(tester, screenWidth: screenWidth);

        expect(
          tester.takeException(),
          isNull,
          reason:
              'a RenderFlex overflow means the stars are drawn out of bounds',
        );
      },
    );
  }

  // The captions scale with the system text size while the stars do not, so a
  // large setting grows the labels inside their own column and must not push
  // anything sideways.
  for (final textScale in <double>[1.5, 2.0]) {
    testWidgets('a x$textScale text size grows the captions, not the row', (
      tester,
    ) async {
      await _pump(tester, screenWidth: 393, textScale: textScale);

      final stars = tester.getRect(find.byType(StarRatingWidget));
      final pageCount = tester.getRect(find.text('247'));

      expect(
        stars.right,
        lessThanOrEqualTo(pageCount.left - BookRatingRow.gutter),
        reason: 'a large text size must not bring the columns into contact',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the pages column is dropped when the page count is unknown', (
    tester,
  ) async {
    await _pump(tester, screenWidth: 393, rating: 8, pageCount: null);

    expect(find.byType(StarRatingWidget), findsOneWidget);
    expect(find.text('PAGES'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a star reports the rating on the 0-10 scale', (
    tester,
  ) async {
    int? reported;
    await _pump(
      tester,
      screenWidth: 320,
      onRatingChanged: (value) => reported = value,
    );

    // Scaling the stars down must not break hit testing: the third star still
    // reports 6 (3 stars on the 0-10 scale).
    await tester.tap(find.byIcon(Icons.star_outline_rounded).at(2));
    expect(reported, 6);
  });
}
