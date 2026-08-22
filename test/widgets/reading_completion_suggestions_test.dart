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
import 'package:bibliogenius/widgets/reading_completion_suggestions.dart';

/// ADR-062 R5, third and final form: the moment PROMOTES the page's own
/// "You might also like" section to the top and reframes its heading.
///
/// Two earlier forms failed. A SnackBarAction left after three seconds and
/// its label sat at poor contrast. A second block carrying the personal
/// taste blend read as duplication: different data, but two rows of covers
/// on one page all the same.
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

Recommendation _similar(String id) {
  return Recommendation(
    book: Book(id: id, title: 'Book $id', author: 'An Author'),
    score: 1,
    reasons: const [RecommendationReason(type: 'same_author', value: 'A')],
  );
}

void main() {
  Future<void> pumpBlock(
    WidgetTester tester, {
    required List<Recommendation> similar,
    bool reduceMotion = false,
    bool settleFirstFrame = true,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<RecommendationRepository>.value(
            value: _FakeRepository(similar),
          ),
          ChangeNotifierProvider<RecommendationProvider>(
            create: (_) => RecommendationProvider(
              _FakeRepository(similar),
              BookRefreshNotifier(),
            ),
          ),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: Scaffold(
              body: SingleChildScrollView(
                child: ReadingCompletionSuggestions(
                  book: Book(id: 'current', title: 'The book just finished'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // The post-frame callback that starts the fade lands on the NEXT pump,
    // so a test watching the first frame must not take it.
    if (settleFirstFrame) await tester.pump();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'reading_completion_continue_with': 'Continue with',
        'recommendations_similar': 'You might also like',
        'reason_same_author': 'Same author: {value}',
        'reason_same_author_short': 'Same author',
        'recommendation_not_interested': 'Not interested',
      },
    });
  });

  testWidgets('reuses the similar-books section under a new heading', (
    tester,
  ) async {
    await pumpBlock(tester, similar: [_similar('a'), _similar('b')]);
    await tester.pumpAndSettle();

    expect(find.byType(BookRecommendationsSection), findsOneWidget);
    expect(find.text('Continue with'), findsOneWidget);
    expect(
      find.text('You might also like'),
      findsNothing,
      reason: 'the same content, asked a different question',
    );
  });

  testWidgets('shows the same books the section would have shown', (
    tester,
  ) async {
    await pumpBlock(tester, similar: [_similar('a'), _similar('b')]);
    await tester.pumpAndSettle();

    // findsWidgets, not findsOneWidget: a coverless book in this section
    // renders its title inside the cover frame AND as the caption below.
    expect(find.text('Book a'), findsWidgets);
    expect(find.text('Book b'), findsWidgets);
  });

  testWidgets('renders nothing below the section two-suggestion floor', (
    tester,
  ) async {
    await pumpBlock(tester, similar: [_similar('a')]);
    await tester.pumpAndSettle();

    expect(find.text('Continue with'), findsNothing);
  });

  testWidgets('fades in rather than snapping', (tester) async {
    await pumpBlock(
      tester,
      similar: [_similar('a'), _similar('b')],
      settleFirstFrame: false,
    );

    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );

    await tester.pumpAndSettle();

    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );
  });

  testWidgets('is simply there when the reader disabled animations', (
    tester,
  ) async {
    await pumpBlock(
      tester,
      similar: [_similar('a'), _similar('b')],
      reduceMotion: true,
    );

    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
      reason: 'a reduced-motion setting must not cost the reader the block',
    );
  });

  testWidgets('nothing overlays, nothing has to be dismissed', (tester) async {
    await pumpBlock(tester, similar: [_similar('a'), _similar('b')]);
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });
}
