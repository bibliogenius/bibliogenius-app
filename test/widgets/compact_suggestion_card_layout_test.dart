import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/compact_suggestion_card.dart';
import 'package:bibliogenius/widgets/reason_chip.dart';
import 'package:bibliogenius/widgets/suggestion_tile.dart';

/// Regression cover for the layout defects seen on the first real render of
/// the discovery strip (2026-08-21):
///
/// 1. an external card carried BOTH a source badge and a reason chip, the
///    pair wrapped onto a second line and overflowed the strip by 27px;
/// 2. the reason chip was built in `compact` mode, which keeps only the
///    reason's raw value: fine for "same author" (the value is the author's
///    name) but meaningless for a series volume, where it rendered as a
///    bare "2".
Recommendation _seriesCard() {
  return Recommendation(
    book: Book(
      id: 'hp2',
      title: 'Harry Potter and the Chamber of Secrets',
      author: 'J. K. Rowling',
    ),
    score: 0,
    reasons: const [
      RecommendationReason(
        type: 'series_missing_volume',
        value: '2',
        params: {'ordinal': '2', 'series': 'Harry Potter'},
      ),
    ],
    source: RecommendationSource.external,
    externalKey: 'series:Q1:2',
  );
}

Recommendation _authorCard() {
  return Recommendation(
    book: Book(id: 'a1', title: 'Dans le jardin de l ogre', author: 'Leila Slimani'),
    score: 1,
    reasons: const [
      RecommendationReason(type: 'same_author', value: 'Leila Slimani'),
    ],
  );
}

void main() {
  Future<void> pumpCard(
    WidgetTester tester,
    Recommendation suggestion, {
    double width = 320,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: SizedBox(
                  width: width,
                  height: CompactSuggestionCard.stripHeight(context),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [CompactSuggestionCard(suggestion: suggestion)],
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'suggestion_badge_external': 'To discover',
        'reason_series_missing_volume': 'Volume {ordinal} of {series}',
        'reason_same_author': 'Same author: {value}',
        'reason_same_author_short': 'Same author',
      },
    });
  });

  testWidgets('an external card with a reason does not overflow', (
    tester,
  ) async {
    await pumpCard(tester, _seriesCard());

    expect(tester.takeException(), isNull);
  });

  testWidgets('it does not overflow on a narrow device either', (
    tester,
  ) async {
    await pumpCard(tester, _seriesCard(), width: 180);

    expect(tester.takeException(), isNull);
  });

  testWidgets('no reason chip rides on the card', (tester) async {
    // The strip adopted the app's cover-on-top recommendation format, which
    // has no room for a chip. The reason moves to the preview sheet a tap
    // away and stays in the announcement below; ADR-062 records the
    // deviation from the ADR-059 "always show a reason" rule.
    await pumpCard(tester, _seriesCard());

    expect(find.byType(ReasonChip), findsNothing);
  });

  testWidgets('the reason survives in the screen-reader announcement', (
    tester,
  ) async {
    await pumpCard(tester, _seriesCard());

    final semantics = tester.getSemantics(find.byType(CompactSuggestionCard));
    expect(
      semantics.label,
      contains('Volume 2'),
      reason: 'dropping it visually must not drop it for a screen reader',
    );
  });

  testWidgets('no caption under the cover', (tester) async {
    // Bare covers, exactly like the Activity segment, so the slot keeps one
    // visual language across both. The author is the clean signal here: it
    // has no fallback anywhere, unlike the title.
    await pumpCard(tester, _authorCard());

    expect(find.text('Leila Slimani'), findsNothing);
  });

  testWidgets('a coverless book falls back to its title inside the cover', (
    tester,
  ) async {
    // With no caption underneath, a placeholder icon would leave the card
    // unidentifiable. This is the Activity strip's own fallback, and it is
    // the ONLY place the title stays visible.
    await pumpCard(tester, _authorCard());

    expect(find.text('Dans le jardin de l ogre'), findsOneWidget);
  });

  testWidgets('hover and long-press bring the title and author back', (
    tester,
  ) async {
    // A cover-only display hides what identifies a book. The Tooltip idiom
    // the collection stacks already use answers both a hover and a long
    // press, so this is not a pointer-only affordance.
    await pumpCard(tester, _seriesCard());

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, contains('Harry Potter and the Chamber'));
    expect(tooltip.message, contains('J. K. Rowling'));
    expect(tooltip.message, contains('To discover'));
  });

  testWidgets('a library card gets the same tooltip, minus the source', (
    tester,
  ) async {
    await pumpCard(tester, _authorCard());

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, contains('Leila Slimani'));
    expect(tooltip.message, isNot(contains('To discover')));
  });

  testWidgets('the card announces itself exactly like the tile', (
    tester,
  ) async {
    await pumpCard(tester, _seriesCard());

    final semantics = tester.getSemantics(find.byType(CompactSuggestionCard));
    late String tileLabel;
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: Scaffold(
            body: Builder(
              builder: (context) {
                tileLabel = SuggestionTile.semanticsLabel(
                  context,
                  _seriesCard(),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    expect(semantics.label, tileLabel);
  });

  testWidgets('the source marker is absent on a library card', (tester) async {
    await pumpCard(tester, _authorCard());

    expect(find.byIcon(Icons.explore_outlined), findsNothing);
  });

  testWidgets('the source marker is present on an external card', (
    tester,
  ) async {
    await pumpCard(tester, _seriesCard());

    expect(find.byIcon(Icons.explore_outlined), findsOneWidget);
  });

  testWidgets('the badge wording stays in the single semantics label', (
    tester,
  ) async {
    await pumpCard(tester, _seriesCard());

    final semantics = tester.getSemantics(find.byType(CompactSuggestionCard));
    expect(semantics.label, contains('To discover'));
    expect(semantics.label, contains('Harry Potter'));
  });
}
