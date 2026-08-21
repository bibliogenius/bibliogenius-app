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
import 'package:bibliogenius/utils/recommendation_display.dart';

/// ADR-062 R5: finishing a book is the one moment a reader naturally asks
/// "what next?", so the EXISTING completion feedback gains one action.
/// No dialog, no interruption, and only when there is something to show.
class _FakeRepository implements RecommendationRepository {
  _FakeRepository(this.personal);

  final PersonalRecommendations? personal;

  @override
  Future<List<Recommendation>> getBookRecommendations(
    String bookId, {
    int? limit,
  }) async => const [];

  @override
  Future<PersonalRecommendations?> getPersonalRecommendations({
    int? limit,
  }) async => personal;

  @override
  Future<DiscoveryLookupInputs?> getDiscoveryLookupInputs() async => null;
}

Recommendation _suggestion(String id) {
  return Recommendation(
    book: Book(id: id, title: 'Book $id'),
    score: 1,
    reasons: const [RecommendationReason(type: 'same_author', value: 'A')],
  );
}

void main() {
  late RecommendationProvider provider;
  SnackBarAction? captured;

  Future<void> pumpProbe(
    WidgetTester tester, {
    required List<Recommendation>? suggestions,
    required String newStatus,
    required String? previousStatus,
  }) async {
    provider = RecommendationProvider(
      _FakeRepository(
        suggestions == null
            ? null
            : PersonalRecommendations(
                recommendations: suggestions,
                topSubjects: const [],
                favoriteAuthors: const [],
                scoredBooksCount: 12,
              ),
      ),
      BookRefreshNotifier(),
    );
    await provider.loadPersonal();
    captured = null;

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<RecommendationProvider>.value(
              value: provider,
            ),
            ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ],
          child: Scaffold(
            body: Builder(
              builder: (context) {
                captured = readCompletionSuggestionsAction(
                  context,
                  newStatus: newStatus,
                  previousStatus: previousStatus,
                );
                return const SizedBox.shrink();
              },
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
      'en': {'help_cta_see_suggestions': 'See the suggestions'},
    });
  });

  testWidgets('offered when a book becomes read and the floors pass', (
    tester,
  ) async {
    await pumpProbe(
      tester,
      suggestions: [_suggestion('a'), _suggestion('b')],
      newStatus: 'read',
      previousStatus: 'reading',
    );

    expect(captured, isNotNull);
    expect(captured!.label, 'See the suggestions');
  });

  testWidgets('not offered when the status is not read', (tester) async {
    await pumpProbe(
      tester,
      suggestions: [_suggestion('a'), _suggestion('b')],
      newStatus: 'reading',
      previousStatus: 'to_read',
    );

    expect(captured, isNull);
  });

  testWidgets('not offered on a re-save of an already read book', (
    tester,
  ) async {
    // Only the TRANSITION is the moment; editing a finished book is not.
    await pumpProbe(
      tester,
      suggestions: [_suggestion('a'), _suggestion('b')],
      newStatus: 'read',
      previousStatus: 'read',
    );

    expect(captured, isNull);
  });

  testWidgets('not offered below the visible-suggestions floor', (
    tester,
  ) async {
    await pumpProbe(
      tester,
      suggestions: [_suggestion('a')],
      newStatus: 'read',
      previousStatus: 'reading',
    );

    expect(captured, isNull);
  });

  testWidgets('not offered below the profile floor', (tester) async {
    await pumpProbe(
      tester,
      suggestions: null,
      newStatus: 'read',
      previousStatus: 'reading',
    );

    expect(captured, isNull);
  });
}
