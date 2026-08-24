import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

/// The slot header is two plain text tabs, not a boxed control: on the
/// first real render the `SegmentedButton` weighed more than the covers it
/// labelled, and the app already has its own tab vocabulary (the library
/// header switches Books / Shelves / Collections the same way).
///
/// That trade was anticipated in ADR-062 section 8: dropping the Material
/// control means its selected-state announcement has to be supplied by
/// hand, so these tests pin it. Losing it would be an invisible
/// accessibility regression: the tabs would still look right.
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
    book: Book(id: id, title: 'Book $id', author: 'An Author'),
    score: 1,
    reasons: const [RecommendationReason(type: 'same_author', value: 'A')],
  );
}

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

void main() {
  late ThemeProvider theme;

  Future<void> pumpSlot(WidgetTester tester) async {
    final recommendations = RecommendationProvider(
      _FakeRepository(
        PersonalRecommendations(
          recommendations: [_suggestion('s1'), _suggestion('s2')],
          topSubjects: const [],
          favoriteAuthors: const [],
          scoredBooksCount: 12,
        ),
      ),
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
          child: Scaffold(body: BooksTopSlot(books: _activeLibrary())),
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
        'books_slot_segment_discover': 'To discover · {count}',
        'books_slot_tab_discover': 'To discover',
        'recently_added_title': 'Recent activity',
        'carousel_collapse_tooltip': 'Collapse',
        'carousel_hide_long_press_tooltip': 'Long press to hide',
        'see_all_recommendations': 'See all',
        'reason_same_author': 'Same author: {value}',
        'reason_same_author_short': 'Same author',
      },
    });
  });

  testWidgets('each tab announces itself as a selectable tab', (tester) async {
    await pumpSlot(tester);

    final activity = tester.getSemantics(find.text('Activity'));
    final discover = tester.getSemantics(find.text('To discover'));

    expect(activity.hasFlag(SemanticsFlag.hasSelectedState), isTrue);
    expect(discover.hasFlag(SemanticsFlag.hasSelectedState), isTrue);
  });

  testWidgets('the selected state is announced and follows the tap', (
    tester,
  ) async {
    await pumpSlot(tester);

    expect(
      tester.getSemantics(find.text('Activity')).hasFlag(SemanticsFlag.isSelected),
      isTrue,
    );
    expect(
      tester
          .getSemantics(find.text('To discover'))
          .hasFlag(SemanticsFlag.isSelected),
      isFalse,
    );

    await tester.tap(find.text('To discover'));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.text('Activity')).hasFlag(SemanticsFlag.isSelected),
      isFalse,
    );
    expect(
      tester
          .getSemantics(find.text('To discover'))
          .hasFlag(SemanticsFlag.isSelected),
      isTrue,
    );
  });

  testWidgets('the header carries no boxed Material control', (tester) async {
    await pumpSlot(tester);

    expect(
      find.byType(SegmentedButton<bool>),
      findsNothing,
      reason: 'it outweighed the covers it labels',
    );
  });

  testWidgets('both tabs stay reachable as tap targets', (tester) async {
    await pumpSlot(tester);

    for (final label in ['Activity', 'To discover']) {
      final size = tester.getSize(
        find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
      );
      expect(
        size.height,
        greaterThanOrEqualTo(36),
        reason: '$label is too small to hit comfortably',
      );
    }
  });

  testWidgets('the discovery tab carries no count', (tester) async {
    // Both tabs plus the collapse control share one phone-width row, so a
    // count on each ellipsized this one down to its separator ("To
    // discover ..."), which reads as a rendering fault rather than as a
    // number. The collapsed summary keeps its count: it has the whole row.
    await pumpSlot(tester);

    expect(find.text('To discover'), findsOneWidget);
    expect(find.textContaining('To discover \u00b7'), findsNothing);
  });

  testWidgets('both tabs are drawn as buttons, not one button and one word', (
    tester,
  ) async {
    // The unselected tab used to be bare text beside a tonal pill, which
    // read as a label rather than as the second half of a control.
    await pumpSlot(tester);

    final colors = <Color?>[];
    for (final label in ['Activity', 'To discover']) {
      final material = tester.widget<Material>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Material))
            .first,
      );
      expect(
        material.shape,
        isA<StadiumBorder>(),
        reason: '$label must carry a pill of its own',
      );
      colors.add(material.color);
    }

    expect(colors.first, isNotNull);
    expect(colors.last, isNotNull);
    expect(
      colors.first,
      isNot(colors.last),
      reason: 'two identical pills would hide which tab is showing',
    );
  });

  testWidgets('the tabs sit as far from the card top as from the strip', (
    tester,
  ) async {
    await pumpSlot(tester);

    final cardTop = tester.getRect(find.byType(AnimatedSize)).top;
    final tab = tester.getRect(
      find
          .ancestor(of: find.text('Activity'), matching: find.byType(Material))
          .first,
    );
    final stripTop = tester.getRect(find.byType(ListView)).top;

    expect(tab.top - cardTop, closeTo(stripTop - tab.bottom, 0.01));
  });
}
