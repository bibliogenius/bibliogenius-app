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
import 'package:bibliogenius/widgets/books_top_slot.dart';
import 'package:bibliogenius/widgets/compact_suggestion_card.dart';

/// ADR-062 R3: one shared slot at the top of /books, with a lightweight
/// segmented header. Activity by default, nothing ever auto-switches, and
/// the slot reuses the carousel's hide/collapse state rather than growing
/// a second one.
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

Recommendation _suggestion(String id, String title) {
  return Recommendation(
    book: Book(id: id, title: title, author: 'An Author'),
    score: 1,
    reasons: const [
      RecommendationReason(type: 'same_author', value: 'An Author'),
    ],
  );
}

PersonalRecommendations _payload(List<Recommendation> recs) {
  return PersonalRecommendations(
    recommendations: recs,
    topSubjects: const [],
    favoriteAuthors: const [],
    scoredBooksCount: 12,
  );
}

/// A library with real activity: settled, plus a book being read.
List<Book> _activeLibrary() {
  return [
    Book(
      id: 'reading',
      title: 'Currently Reading',
      readingStatus: 'reading',
      startedReadingAt: DateTime.now().subtract(const Duration(days: 2)),
      addedAt: DateTime.now().subtract(const Duration(days: 300)),
    ),
    for (var i = 0; i < 20; i++)
      Book(
        id: 'old$i',
        title: 'Old $i',
        addedAt: DateTime.now().subtract(const Duration(days: 400)),
      ),
  ];
}

/// A small, untouched library: the Activity strip auto-hides here.
List<Book> _quietSmallLibrary() {
  return [
    for (var i = 0; i < 4; i++)
      Book(
        id: 'q$i',
        title: 'Quiet $i',
        addedAt: DateTime.now().subtract(const Duration(days: 400)),
      ),
  ];
}

void main() {
  late ThemeProvider theme;
  late RecommendationProvider recommendations;

  Future<void> pumpSlot(
    WidgetTester tester, {
    required List<Book> books,
    List<Recommendation> suggestions = const [],
  }) async {
    recommendations = RecommendationProvider(
      _FakeRepository(suggestions.isEmpty ? null : _payload(suggestions)),
      BookRefreshNotifier(),
    );
    await recommendations.loadPersonal();

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>.value(value: theme),
            ChangeNotifierProvider<RecommendationProvider>.value(
              value: recommendations,
            ),
          ],
          child: Scaffold(body: BooksTopSlot(books: books)),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'books_slot_segment_activity': 'Activity',
        'books_slot_segment_discover': 'To discover',
        'recently_added_title': 'Recent activity',
        'carousel_collapse_tooltip': 'Collapse',
        'carousel_hide_long_press_tooltip': 'Long press to hide',
        'see_all_recommendations': 'See all',
        'reason_same_author': 'Same author: {value}',
        'recommendation_not_interested': 'Not interested',
      },
    });
  });

  testWidgets('Activity is the default segment', (tester) async {
    await pumpSlot(
      tester,
      books: _activeLibrary(),
      suggestions: [_suggestion('s1', 'Suggested One'), _suggestion('s2', 'Suggested Two')],
    );

    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('To discover'), findsOneWidget);
    expect(
      find.byType(CompactSuggestionCard),
      findsNothing,
      reason: 'nothing auto-switches to discovery',
    );
  });

  testWidgets('tapping the discovery segment shows compact cards', (
    tester,
  ) async {
    await pumpSlot(
      tester,
      books: _activeLibrary(),
      suggestions: [_suggestion('s1', 'Suggested One'), _suggestion('s2', 'Suggested Two')],
    );

    await tester.tap(find.text('To discover'));
    await tester.pumpAndSettle();

    expect(find.byType(CompactSuggestionCard), findsWidgets);
    expect(find.text('Suggested One'), findsOneWidget);
  });

  testWidgets('the chosen segment is remembered for the session', (
    tester,
  ) async {
    await pumpSlot(
      tester,
      books: _activeLibrary(),
      suggestions: [_suggestion('s1', 'Suggested One'), _suggestion('s2', 'Suggested Two')],
    );
    await tester.tap(find.text('To discover'));
    await tester.pumpAndSettle();

    // Same session, the slot rebuilt from scratch: the segment survives
    // because it lives on the provider, not in widget state.
    await pumpSlot(
      tester,
      books: _activeLibrary(),
      suggestions: [_suggestion('s1', 'Suggested One'), _suggestion('s2', 'Suggested Two')],
    );

    expect(find.byType(CompactSuggestionCard), findsWidgets);
  });

  testWidgets('no discovery segment below the visible-suggestions floor', (
    tester,
  ) async {
    await pumpSlot(
      tester,
      books: _activeLibrary(),
      suggestions: [_suggestion('s1', 'Suggested One')],
    );

    expect(find.text('To discover'), findsNothing);
    expect(
      find.text('Recent activity'),
      findsOneWidget,
      reason: 'the Activity strip keeps its own header when it stands alone',
    );
  });

  testWidgets('no slot at all when neither segment has content', (
    tester,
  ) async {
    await pumpSlot(tester, books: _quietSmallLibrary());

    expect(find.text('Activity'), findsNothing);
    expect(find.text('To discover'), findsNothing);
    expect(find.byType(CompactSuggestionCard), findsNothing);
  });

  testWidgets('discovery stands alone when Activity auto-hides', (
    tester,
  ) async {
    await pumpSlot(
      tester,
      books: _quietSmallLibrary(),
      suggestions: [_suggestion('s1', 'Suggested One'), _suggestion('s2', 'Suggested Two')],
    );

    expect(find.byType(CompactSuggestionCard), findsWidgets);
    expect(
      find.text('Activity'),
      findsNothing,
      reason: 'a segmented control with one dead half is noise',
    );
  });

  testWidgets('hiding the slot hides both segments', (tester) async {
    await theme.setCarouselHiddenOwnLib(true);

    await pumpSlot(
      tester,
      books: _activeLibrary(),
      suggestions: [_suggestion('s1', 'Suggested One'), _suggestion('s2', 'Suggested Two')],
    );

    expect(find.text('Activity'), findsNothing);
    expect(find.text('To discover'), findsNothing);
    expect(find.byType(CompactSuggestionCard), findsNothing);
  });

  testWidgets('the slot reuses the carousel hide state, not a second one', (
    tester,
  ) async {
    await pumpSlot(
      tester,
      books: _activeLibrary(),
      suggestions: [_suggestion('s1', 'Suggested One'), _suggestion('s2', 'Suggested Two')],
    );
    expect(find.text('Activity'), findsOneWidget);

    await theme.setCarouselHiddenOwnLib(true);
    await tester.pumpAndSettle();

    expect(find.text('Activity'), findsNothing);
  });

  testWidgets('the discovery count matches the covers actually drawn', (
    tester,
  ) async {
    // The header counted every visible suggestion while the strip applies a
    // total cap AND a tighter cap on external cards, so it announced more
    // covers than the reader could find. Regression cover for that.
    await pumpSlot(
      tester,
      books: _activeLibrary(),
      suggestions: [
        for (var i = 0; i < 12; i++) _suggestion('s$i', 'Suggested $i'),
      ],
    );

    await tester.tap(find.text('To discover'));
    await tester.pumpAndSettle();

    final drawn = tester.widgetList(find.byType(CompactSuggestionCard)).length;
    expect(
      drawn,
      RecommendationProvider.slotMaxDisplayed,
      reason: 'the strip caps what it draws',
    );
    expect(
      recommendations.blendedDigest(
        maxDisplayed: RecommendationProvider.slotMaxDisplayed,
        maxExternal: RecommendationProvider.slotMaxExternal,
      ).length,
      drawn,
      reason: 'the header counts that same blend, never a wider one',
    );
  });

  testWidgets('counts are rendered as static text next to each segment', (
    tester,
  ) async {
    await pumpSlot(
      tester,
      books: _activeLibrary(),
      suggestions: [
        _suggestion('s1', 'Suggested One'),
        _suggestion('s2', 'Suggested Two'),
        _suggestion('s3', 'Suggested Three'),
      ],
    );

    // Three suggestions survive dismissal filtering, so the label carries
    // the full count even though the strip shows a digest of them.
    expect(find.textContaining('3'), findsWidgets);
  });
}
