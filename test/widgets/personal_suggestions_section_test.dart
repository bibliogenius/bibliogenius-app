import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/recommendation_repository.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/recommendation_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/personal_suggestions_section.dart';

/// Serves a canned payload; the section only ever reads the provider cache.
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
}

Recommendation _suggestion({
  required String title,
  String? author,
  List<RecommendationReason> reasons = const [
    RecommendationReason(type: 'same_author', value: 'Albert Camus'),
  ],
}) {
  return Recommendation(
    book: Book(id: 'book-$title', title: title, author: author),
    score: 1,
    reasons: reasons,
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
      child: const Scaffold(
        body: SingleChildScrollView(child: PersonalSuggestionsSection()),
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
        'recommendations_personal': 'Suggestions for you',
        'reason_same_author': 'Same author: {value}',
        'reason_same_author_short': 'Same author',
        'reason_shared_subject': 'Same shelf: {value}',
        'reason_highly_rated': 'Highly rated: {value}',
      },
    });
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  testWidgets('renders the section header and one tile per suggestion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        theme: theme,
        suggestions: [
          _suggestion(title: 'La Peste', author: 'Albert Camus'),
          _suggestion(title: 'Le Mythe de Sisyphe', author: 'Albert Camus'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Suggestions for you'), findsOneWidget);
    // Title and author sit on their own lines (no "title - author" run-on).
    expect(find.text('La Peste'), findsOneWidget);
    expect(find.text('Le Mythe de Sisyphe'), findsOneWidget);
    expect(find.text('Albert Camus'), findsNWidgets(2));
  });

  testWidgets('shows at most two reason chips, each with its icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        theme: theme,
        suggestions: [
          _suggestion(
            title: 'La Peste',
            author: 'Albert Camus',
            reasons: const [
              RecommendationReason(type: 'same_author', value: 'Albert Camus'),
              RecommendationReason(type: 'shared_subject', value: 'Roman'),
              RecommendationReason(type: 'highly_rated', value: '5/5'),
            ],
          ),
          _suggestion(title: 'Le Mythe de Sisyphe'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Same author'),
      findsNWidgets(2),
      reason: 'the chip drops the author name already printed above it',
    );
    expect(find.text('Same author: Albert Camus'), findsNothing);
    expect(
      find.text('Roman'),
      findsOneWidget,
      reason: 'a shelf tag stands on its own next to the tag icon',
    );
    expect(find.text('Same shelf: Roman'), findsNothing);
    expect(
      find.byTooltip('Same shelf: Roman'),
      findsOneWidget,
      reason: 'trimming the prefix must not lose the explanation',
    );
    expect(
      find.text('Highly rated: 5/5'),
      findsNothing,
      reason: 'the third reason must stay out of the digest',
    );
    expect(find.byIcon(Icons.person_outline), findsNWidgets(2));
    expect(find.byIcon(Icons.local_offer_outlined), findsOneWidget);
  });

  testWidgets('a long reason never overflows a narrow phone row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        theme: theme,
        suggestions: [
          _suggestion(
            title: 'Voyage au bout de la nuit et autres textes',
            author: 'Louis-Ferdinand Celine',
            reasons: const [
              RecommendationReason(
                type: 'same_author',
                value: 'Louis-Ferdinand Celine',
              ),
              RecommendationReason(
                type: 'shared_subject',
                value: 'Litterature francaise du XXe siecle',
              ),
            ],
          ),
          _suggestion(title: 'Le Mythe de Sisyphe'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'chips flex and ellipsize instead of pushing the row over',
    );
  });

  testWidgets('hides itself below the two-suggestion floor', (tester) async {
    await tester.pumpWidget(
      _harness(
        theme: theme,
        suggestions: [_suggestion(title: 'La Peste')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Suggestions for you'), findsNothing);
  });

  testWidgets('each tile is one accessible button carrying its reasons', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _harness(
        theme: theme,
        suggestions: [
          _suggestion(title: 'La Peste', author: 'Albert Camus'),
          _suggestion(title: 'Le Mythe de Sisyphe', author: 'Albert Camus'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('La Peste. Albert Camus. Same author'),
      findsOneWidget,
      reason: 'the tile must be announced once, not echoed line by line',
    );
    semantics.dispose();
  });
}
