import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/compact_suggestion_card.dart';

/// The strip is a fixed-height horizontal list, which is exactly the shape
/// that clips silently when the reader raises the system text size. These
/// pin the sizing rules so a large-text setting grows the card instead.
Recommendation _card() {
  return Recommendation(
    book: Book(
      id: 'b1',
      title: 'A rather long title that needs two full lines to render',
      author: 'Ursula K. Le Guin',
    ),
    score: 1,
    reasons: const [
      RecommendationReason(type: 'same_author', value: 'Ursula K. Le Guin'),
    ],
  );
}

Future<void> pumpAt(
  WidgetTester tester, {
  required double textScale,
  required Size size,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Builder(
            builder: (context) => Scaffold(
              body: SizedBox(
                height: CompactSuggestionCard.stripHeight(context),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [CompactSuggestionCard(suggestion: _card())],
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
      'en': {
        'reason_same_author': 'Same author: {value}',
        'reason_same_author_short': 'Same author',
      },
    });
  });

  testWidgets('the card does not clip at the system large-text setting', (
    tester,
  ) async {
    await pumpAt(tester, textScale: 2.0, size: const Size(390, 844));

    expect(tester.takeException(), isNull);
  });

  testWidgets('the strip height is the cover height, text scale aside', (
    tester,
  ) async {
    // Once the caption went away the strip stopped needing to grow: the
    // only words left are the fallback title INSIDE the cover, which
    // ellipsizes within its fixed frame. Same property as the Activity
    // strip, which is the point of aligning the two.
    late double normal;
    late double large;

    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(430, 900),
              textScaler: TextScaler.linear(scale),
            ),
            child: Builder(
              builder: (context) {
                final height = CompactSuggestionCard.stripHeight(context);
                if (scale == 1.0) {
                  normal = height;
                } else {
                  large = height;
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    }

    expect(large, normal);
    expect(normal, 120, reason: 'the Activity cover height');
  });

  testWidgets('the card matches the Activity strip footprint', (tester) async {
    // The slot has one rhythm across both segments: the discovery cards use
    // the Activity covers' own width, at its two sizes.
    late double wide;
    late double narrow;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(430, 900)),
          child: Builder(
            builder: (context) {
              wide = CompactSuggestionCard.cardWidth(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 640)),
          child: Builder(
            builder: (context) {
              narrow = CompactSuggestionCard.cardWidth(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(wide, 80);
    expect(narrow, 64, reason: 'the compact cover size on a small device');
  });
}
