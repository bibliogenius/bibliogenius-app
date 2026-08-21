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
import 'package:bibliogenius/services/recommendation_dismissal_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/book_recommendations_section.dart';

/// Serves a canned "similar books" list for the reference book.
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
  RecommendationReason reason = const RecommendationReason(
    type: 'same_author',
    value: 'Albert Camus',
  ),
}) {
  return Recommendation(
    book: Book(id: 'book-$title', title: title, author: author),
    score: 1,
    reasons: [reason],
  );
}

Widget _harness({
  required ThemeProvider theme,
  required List<Recommendation> similar,
}) {
  final repository = _FakeRepository(similar);
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
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
  late ThemeProvider theme;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'recommendations_similar': 'You might also like',
        'reason_same_author': 'Same author: {value}',
        'reason_same_author_short': 'Same author',
        'reason_shared_subject': 'Same shelf: {value}',
        'recommendation_not_interested': 'Not interested',
        'recommendation_dismissed': 'Suggestion hidden',
        'action_undo': 'Undo',
      },
    });
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  testWidgets('renders the section header and one card per similar book', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        theme: theme,
        similar: [
          _similar(title: 'La Peste', author: 'Albert Camus'),
          _similar(title: 'La Chute', author: 'Albert Camus'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You might also like'), findsOneWidget);
    // Twice each: the caption under the cover, plus the fallback cover which
    // paints the title when the book has no image.
    expect(find.text('La Peste'), findsWidgets);
    expect(find.text('La Chute'), findsWidgets);
  });

  testWidgets('the reason chip keeps the value and its icon, not the prefix', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        theme: theme,
        similar: [
          _similar(title: 'La Peste', author: 'Albert Camus'),
          _similar(
            title: 'Le Nom de la rose',
            author: 'Umberto Eco',
            reason: const RecommendationReason(
              type: 'shared_subject',
              value: 'Roman',
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Compact chips: the icon carries the reason type, the text the payload,
    // except for the author reason whose payload is the line right above.
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.text('Same author'), findsOneWidget);
    expect(
      find.text('Albert Camus'),
      findsNWidgets(2),
      reason:
          'the author appears in the caption and on the fallback cover only, '
          'never a third time inside the chip',
    );
    expect(find.byIcon(Icons.local_offer_outlined), findsOneWidget);
    expect(find.text('Roman'), findsOneWidget);
    expect(
      find.text('Same shelf: Roman'),
      findsNothing,
      reason: 'the full sentence lives in the tooltip, not on the card',
    );
    // ... but it stays reachable for pointer users and screen readers.
    expect(
      find.byTooltip('Same shelf: Roman'),
      findsOneWidget,
      reason: 'dropping the prefix must not drop the explanation',
    );
  });

  testWidgets('hides itself below the two-suggestion floor', (tester) async {
    await tester.pumpWidget(
      _harness(
        theme: theme,
        similar: [_similar(title: 'La Peste')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You might also like'), findsNothing);
  });

  testWidgets('"Not interested" hides the card and Undo restores it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        theme: theme,
        similar: [
          _similar(title: 'La Peste', author: 'Albert Camus'),
          _similar(title: 'La Chute', author: 'Albert Camus'),
          _similar(title: 'Caligula', author: 'Albert Camus'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Caligula'), findsWidgets);
    expect(find.byTooltip('Not interested'), findsNWidgets(3));

    // Dismiss the last card.
    await tester.tap(find.byTooltip('Not interested').last);
    await tester.pumpAndSettle();

    expect(find.text('Caligula'), findsNothing);
    expect(find.text('La Peste'), findsWidgets);
    expect(find.text('Suggestion hidden'), findsOneWidget);

    // Undo brings it straight back.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Caligula'), findsWidgets);
  });

  testWidgets('the two-card floor is evaluated after dismissal filtering', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        theme: theme,
        similar: [
          _similar(title: 'La Peste', author: 'Albert Camus'),
          _similar(title: 'La Chute', author: 'Albert Camus'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You might also like'), findsOneWidget);

    // One dismissal leaves a single visible card: the whole section folds.
    await tester.tap(find.byTooltip('Not interested').first);
    await tester.pumpAndSettle();

    expect(find.text('You might also like'), findsNothing);
  });

  testWidgets('a dismissal persisted on a previous launch stays filtered', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      RecommendationDismissalService.dismissedBookIdsKey: ['book-Caligula'],
    });

    await tester.pumpWidget(
      _harness(
        theme: theme,
        similar: [
          _similar(title: 'La Peste', author: 'Albert Camus'),
          _similar(title: 'La Chute', author: 'Albert Camus'),
          _similar(title: 'Caligula', author: 'Albert Camus'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You might also like'), findsOneWidget);
    expect(find.text('Caligula'), findsNothing);
    expect(find.text('La Peste'), findsWidgets);
  });
}
