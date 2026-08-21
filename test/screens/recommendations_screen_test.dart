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
import 'package:bibliogenius/screens/recommendations_screen.dart';
import 'package:bibliogenius/services/recommendation_dismissal_service.dart';
import 'package:bibliogenius/services/translation_service.dart';

/// Serves a canned payload; the screen only ever reads the provider cache.
class _FakeRepository implements RecommendationRepository {
  _FakeRepository(this.payload);

  final PersonalRecommendations? payload;

  @override
  Future<List<Recommendation>> getBookRecommendations(
    String bookId, {
    int? limit,
  }) async => const [];

  @override
  Future<PersonalRecommendations?> getPersonalRecommendations({
    int? limit,
  }) async => payload;

  @override
  Future<DiscoveryLookupInputs?> getDiscoveryLookupInputs() async => null;
}

Recommendation _suggestion(String title) {
  return Recommendation(
    book: Book(id: 'book-$title', title: title, author: 'Albert Camus'),
    score: 1,
    reasons: const [
      RecommendationReason(type: 'same_author', value: 'Albert Camus'),
    ],
  );
}

Widget _harness({
  required ThemeProvider theme,
  required List<Recommendation> suggestions,
}) {
  final provider = RecommendationProvider(
    _FakeRepository(
      PersonalRecommendations(
        recommendations: suggestions,
        topSubjects: const [],
        favoriteAuthors: const [],
        scoredBooksCount: 12,
      ),
    ),
    BookRefreshNotifier(),
  );

  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<RecommendationProvider>.value(value: provider),
      ],
      child: const RecommendationsScreen(),
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
        'recommendations_personal': 'Suggestions for you',
        'recommendations_empty': 'No suggestions right now',
        'reason_same_author': 'Same author: {value}',
        'reason_same_author_short': 'Same author',
        'recommendation_not_interested': 'Not interested',
        'recommendation_dismissed': 'Suggestion hidden',
        'action_undo': 'Undo',
      },
    });
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  testWidgets('renders the complete list, beyond the dashboard digest cap', (
    tester,
  ) async {
    final titles = ['A', 'B', 'C', 'D', 'E', 'F', 'G'];
    await tester.pumpWidget(
      _harness(
        theme: theme,
        suggestions: [for (final t in titles) _suggestion(t)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Suggestions for you'), findsOneWidget);
    for (final t in titles) {
      expect(
        find.text(t),
        findsOneWidget,
        reason: 'the full ranked list shows every suggestion, not a digest',
      );
    }
  });

  testWidgets('"Not interested" hides the tile and Undo restores it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        theme: theme,
        suggestions: [
          _suggestion('La Peste'),
          _suggestion('Le Mythe de Sisyphe'),
          _suggestion('Caligula'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Not interested').last);
    await tester.pumpAndSettle();

    expect(find.text('Caligula'), findsNothing);
    expect(find.text('Suggestion hidden'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Caligula'), findsOneWidget);
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
        suggestions: [_suggestion('La Peste'), _suggestion('Caligula')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Caligula'), findsNothing);
    expect(find.text('La Peste'), findsOneWidget);
  });

  testWidgets('says so instead of a blank page when everything is dismissed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        theme: theme,
        suggestions: [_suggestion('La Peste'), _suggestion('Caligula')],
      ),
    );
    await tester.pumpAndSettle();

    // Unlike the dashboard digest, the screen has no two-suggestion floor:
    // dismissing everything leaves an explicit empty state, not a blank.
    await tester.tap(find.byTooltip('Not interested').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Not interested').first);
    await tester.pumpAndSettle();

    expect(find.text('No suggestions right now'), findsOneWidget);
  });
}
