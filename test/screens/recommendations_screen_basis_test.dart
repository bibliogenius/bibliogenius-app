import 'dart:async';

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
import 'package:bibliogenius/services/translation_service.dart';

/// The full suggestions page carries what the dashboard digest has no room
/// for: WHY these books were picked. The taste profile behind them is
/// already fetched with the list (ADR-059 returns it in the same payload)
/// and was previously thrown away by this screen.
///
/// It also has to tell a cold cache apart from a genuinely empty list: an
/// empty-state message shown while the engine is still answering is simply
/// false.
class _FakeRepository implements RecommendationRepository {
  _FakeRepository(this.payload, {this.gate});

  final PersonalRecommendations? payload;

  /// When set, the payload is withheld until it completes, standing in for
  /// a cold cache still being computed.
  final Completer<void>? gate;

  @override
  Future<List<Recommendation>> getBookRecommendations(
    String bookId, {
    int? limit,
  }) async => const [];

  @override
  Future<PersonalRecommendations?> getPersonalRecommendations({
    int? limit,
  }) async {
    if (gate != null) await gate!.future;
    return payload;
  }

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
  List<String> authors = const [],
  List<String> subjects = const [],
  int scoredBooksCount = 12,
  Completer<void>? gate,
}) {
  final provider = RecommendationProvider(
    _FakeRepository(
      PersonalRecommendations(
        recommendations: suggestions,
        topSubjects: subjects,
        favoriteAuthors: authors,
        scoredBooksCount: scoredBooksCount,
      ),
      gate: gate,
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
        'recommendations_empty_hint':
            'Add or finish a few books and they will come back.',
        'recommendations_basis_books': 'Based on {count} books you have read',
        'recommendations_basis_authors': 'Authors you come back to',
        'recommendations_basis_subjects': 'Subjects you read',
        'recommendations_loading': 'Loading suggestions',
        'reason_same_author': 'Same author: {value}',
        'reason_same_author_short': 'Same author',
        'recommendation_not_interested': 'Not interested',
      },
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  group('the basis header', () {
    testWidgets('names how many books the profile rests on', (tester) async {
      await tester.pumpWidget(
        _harness(
          theme: theme,
          suggestions: [_suggestion('La Peste')],
          scoredBooksCount: 42,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Based on 42 books you have read'), findsOneWidget);
    });

    testWidgets('lists the authors and subjects behind the picks', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          theme: theme,
          suggestions: [_suggestion('La Peste')],
          authors: const ['Albert Camus', 'Ursula K. Le Guin'],
          subjects: const ['Philosophy'],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Albert Camus'), findsWidgets);
      expect(find.text('Ursula K. Le Guin'), findsOneWidget);
      expect(find.text('Philosophy'), findsOneWidget);
    });

    testWidgets('stays out of the way when the profile has nothing to show', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          theme: theme,
          suggestions: [_suggestion('La Peste')],
          scoredBooksCount: 0,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Based on'), findsNothing);
      expect(find.text('La Peste'), findsOneWidget);
    });

    testWidgets('is absent from the empty state', (tester) async {
      await tester.pumpWidget(_harness(theme: theme, suggestions: const []));
      await tester.pumpAndSettle();

      expect(find.textContaining('Based on'), findsNothing);
      expect(find.text('No suggestions right now'), findsOneWidget);
    });
  });

  group('loading is not emptiness', () {
    testWidgets('a cold cache shows a loading state, not "no suggestions"', (
      tester,
    ) async {
      final gate = Completer<void>();
      await tester.pumpWidget(
        _harness(
          theme: theme,
          suggestions: [_suggestion('La Peste')],
          gate: gate,
        ),
      );
      await tester.pump();

      expect(
        find.text('No suggestions right now'),
        findsNothing,
        reason: 'saying there is nothing while still computing is a lie',
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('La Peste'), findsOneWidget);
    });
  });

  group('refreshing', () {
    testWidgets('the list can be pulled to refresh', (tester) async {
      await tester.pumpWidget(
        _harness(theme: theme, suggestions: [_suggestion('La Peste')]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);
    });
  });

  group('the empty state', () {
    testWidgets('explains what brings suggestions back', (tester) async {
      await tester.pumpWidget(_harness(theme: theme, suggestions: const []));
      await tester.pumpAndSettle();

      expect(find.text('No suggestions right now'), findsOneWidget);
      expect(
        find.text('Add or finish a few books and they will come back.'),
        findsOneWidget,
      );
    });
  });
}
