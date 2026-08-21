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
import 'package:bibliogenius/widgets/suggestions_app_bar_action.dart';

/// ADR-062 R4: a direct path to the suggestions from the library screen,
/// independent of the slot and of which segment is showing.
///
/// The floors split (section 6, mirroring ADR-061 A4): gated on the PROFILE
/// floor so it never leads to an empty screen, NOT on the visible-suggestions
/// floor so it does not blink in and out as the reader dismisses cards.
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

  Future<void> pumpAction(
    WidgetTester tester, {
    required List<Recommendation>? suggestions,
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
    // No Future.delayed here: under the widget-test fake clock a real
    // timer never fires, so awaiting one hangs the test.
    await provider.loadPersonal();

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<RecommendationProvider>.value(
              value: provider,
            ),
            // TranslationService.translate resolves the active locale
            // through ThemeProvider, so the tooltip needs it in scope.
            ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ],
          child: Scaffold(
            appBar: AppBar(actions: const [SuggestionsAppBarAction()]),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {'tooltip_open_recommendations': 'Reading suggestions'},
    });
  });

  testWidgets('shows once the profile floor passed', (tester) async {
    await pumpAction(tester, suggestions: [_suggestion('a'), _suggestion('b')]);

    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
  });

  testWidgets('hidden below the profile floor', (tester) async {
    await pumpAction(tester, suggestions: null);

    expect(
      find.byIcon(Icons.auto_awesome),
      findsNothing,
      reason: 'it must never lead to a screen with nothing on it',
    );
  });

  testWidgets('stays put below the visible-suggestions floor', (tester) async {
    // One suggestion: the slot's discovery segment is gone, the action is
    // not. Gating it here would make it blink as cards are dismissed.
    await pumpAction(tester, suggestions: [_suggestion('a')]);

    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
  });

  testWidgets('does not disappear when the reader dismisses down to one', (
    tester,
  ) async {
    await pumpAction(tester, suggestions: [_suggestion('a'), _suggestion('b')]);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);

    await provider.dismiss('b');
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
  });

  testWidgets('carries a translated tooltip', (tester) async {
    await pumpAction(tester, suggestions: [_suggestion('a'), _suggestion('b')]);

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.tooltip, 'Reading suggestions');
  });
}
