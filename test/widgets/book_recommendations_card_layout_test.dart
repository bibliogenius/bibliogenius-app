import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/recommendation_repository.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/recommendation_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/book_recommendations_section.dart';
import 'package:bibliogenius/widgets/reason_chip.dart';

/// Layout cover for the "You might also like" carousel, after the first real
/// render showed two defects:
///
/// 1. a title wrapping onto a second line pushed that card's author and
///    reason chip one line below its neighbours', so the row read as ragged;
/// 2. the dismiss button sat in the top-right corner of the cover, exactly
///    where the reading-status pill is anchored, and clipped its label.
class _FakeRepository implements RecommendationRepository {
  _FakeRepository(this.similar);

  final List<Recommendation> similar;

  @override
  Future<List<Recommendation>> getBookRecommendations(
    String bookId, {
    int? limit,
  }) async => similar;

  @override
  Future<PersonalRecommendations?> getPersonalRecommendations({
    int? limit,
  }) async => null;
  @override
  Future<DiscoveryLookupInputs?> getDiscoveryLookupInputs() async => null;
}

Recommendation _similar({
  required String title,
  String? author,
  String? readingStatus,
}) {
  return Recommendation(
    book: Book(
      id: 'book-$title',
      title: title,
      author: author,
      readingStatus: readingStatus,
    ),
    score: 1,
    reasons: const [
      RecommendationReason(type: 'same_author', value: 'Albert Camus'),
    ],
  );
}

Widget _harness(List<Recommendation> similar, {double textScale = 1.0}) {
  final repository = _FakeRepository(similar);
  return MaterialApp(
    builder: (context, child) => MediaQuery.withClampedTextScaling(
      minScaleFactor: textScale,
      maxScaleFactor: textScale,
      child: child!,
    ),
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        Provider<RecommendationRepository>.value(value: repository),
        ChangeNotifierProvider<RecommendationProvider>(
          create: (_) =>
              RecommendationProvider(repository, BookRefreshNotifier()),
        ),
      ],
      child: Scaffold(
        body: SingleChildScrollView(
          child: BookRecommendationsSection(
            book: Book(id: 'reference', title: 'L Etranger'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'recommendations_similar': 'You might also like',
        'reason_same_author': 'Same author: {value}',
        'reason_same_author_short': 'Same author',
        'recommendation_not_interested': 'Not interested',
        'reading_status_to_read': 'To read',
      },
    });
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  testWidgets('a two-line title does not push its chip below the others', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        _similar(title: 'Peste', author: 'Camus'),
        // Long enough to wrap onto the second line of a 128px card.
        _similar(
          title: 'La cantatrice chauve suivie de La lecon',
          author: 'Ionesco',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    final chips = find.byType(ReasonChip);
    expect(chips, findsNWidgets(2));
    expect(
      tester.getTopLeft(chips.first).dy,
      tester.getTopLeft(chips.last).dy,
      reason: 'the title block is reserved, so every chip sits on one line',
    );
  });

  testWidgets('the author line stays on the same row across cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        _similar(title: 'Peste', author: 'Camus'),
        _similar(
          title: 'La cantatrice chauve suivie de La lecon',
          author: 'Ionesco',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    // Each author is painted twice: on the coverless fallback, then in the
    // caption under it. The caption is the second one.
    expect(
      tester.getTopLeft(find.text('Camus').last).dy,
      tester.getTopLeft(find.text('Ionesco').last).dy,
    );
  });

  testWidgets('the dismiss button clears the reading-status pill', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        _similar(title: 'Peste', author: 'Camus', readingStatus: 'to_read'),
        _similar(title: 'Chute', author: 'Camus', readingStatus: 'to_read'),
      ]),
    );
    await tester.pumpAndSettle();

    final badge = tester.getRect(find.text('TO READ').first);
    final dismiss = tester.getRect(find.byTooltip('Not interested').first);

    expect(
      dismiss.overlaps(badge),
      isFalse,
      reason: 'the pill owns the top-right corner; the button sits elsewhere',
    );
  });

  testWidgets('the row lays out without overflowing', (tester) async {
    await tester.pumpWidget(
      _harness([
        _similar(title: 'Peste', author: 'Camus', readingStatus: 'to_read'),
        // No author at all: the caption slot must still be reserved.
        _similar(title: 'La cantatrice chauve suivie de La lecon'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.byType(ReasonChip).first).dy,
      tester.getTopLeft(find.byType(ReasonChip).last).dy,
      reason: 'a missing author must not raise that card\'s chip either',
    );
  });

  testWidgets('the reserved caption still fits at a large text scale', (
    tester,
  ) async {
    // The row height is computed from the same slots the card reserves, so
    // an accessibility text size must grow the row rather than clip it
    // (WCAG 1.4.4).
    await tester.pumpWidget(
      _harness(textScale: 1.6, [
        _similar(title: 'Peste', author: 'Camus', readingStatus: 'to_read'),
        _similar(
          title: 'La cantatrice chauve suivie de La lecon',
          author: 'Ionesco',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
