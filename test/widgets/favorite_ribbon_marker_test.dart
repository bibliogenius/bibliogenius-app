import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/collection.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/book_cover_card.dart';
import 'package:bibliogenius/widgets/collection_stack_widget.dart';
import 'package:bibliogenius/widgets/favorite_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The favorites marker (ADR-064): a star-bookmark ribbon on the top-right
// corner of book covers and of the Favorites collection card. The marker is
// shape-only; the state must also reach screen readers through the composed
// semantic labels, and it must coexist with the tappable reading-status
// badge without overlap even on narrow covers.
void main() {
  late ThemeProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'reading_status_wanting': 'Envie de lire',
        'favorite_marker_label': 'favori',
        'favorites_collection_name': 'Favoris',
        'collection_group_books_count': 'livres',
      },
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  Future<void> pumpCard(
    WidgetTester tester, {
    required double width,
    required bool isFavorite,
    String? readingStatus = 'wanting',
  }) {
    return tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: 130,
                child: BookCoverCard(
                  book: Book(
                    title: 'Le Livre',
                    owned: true,
                    readingStatus: readingStatus,
                  ),
                  onTap: () {},
                  isFavorite: isFavorite,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a favorite cover wears the ribbon', (tester) async {
    await pumpCard(tester, width: 200, isFavorite: true);
    expect(find.byType(FavoriteRibbon), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a non-favorite cover has no ribbon', (tester) async {
    await pumpCard(tester, width: 200, isFavorite: false);
    expect(find.byType(FavoriteRibbon), findsNothing);
  });

  testWidgets('the favorite state reaches the screen reader', (tester) async {
    await pumpCard(tester, width: 200, isFavorite: true);
    // The ribbon is shape-only; like OwnershipBadge it announces itself
    // with a translated label (Rule A1), cover or no cover.
    expect(find.bySemanticsLabel('favori'), findsOneWidget);

    await pumpCard(tester, width: 200, isFavorite: false);
    expect(find.bySemanticsLabel('favori'), findsNothing);
  });

  testWidgets('at 64px the icon-only status badge and the ribbon coexist', (
    tester,
  ) async {
    await pumpCard(tester, width: 64, isFavorite: true);

    // Icon-only pill (narrow threshold) plus the ribbon, and no layout
    // exception: the pill is inset left of the ribbon, never under it.
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.byType(FavoriteRibbon), findsOneWidget);
    expect(tester.takeException(), isNull);

    final pillCenter = tester.getCenter(find.byIcon(Icons.favorite_border));
    final ribbonRect = tester.getRect(find.byType(FavoriteRibbon));
    expect(
      pillCenter.dx < ribbonRect.left,
      isTrue,
      reason: 'the status badge must sit left of the ribbon, not under it',
    );
  });

  group('CollectionCoverCard', () {
    Collection favorites({String name = '__favorites__'}) => Collection(
      id: 'fav',
      name: name,
      source: 'favorites',
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
      totalBooks: 3,
    );

    Future<void> pumpCollection(
      WidgetTester tester,
      Collection collection,
    ) {
      return tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 160,
                  height: 260,
                  child: CollectionCoverCard(
                    collection: collection,
                    coverUrls: const [],
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('the favorites card wears the type emblem', (tester) async {
      await pumpCollection(tester, favorites());
      expect(find.byType(FavoriteRibbon), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the sentinel name never reaches the screen', (tester) async {
      await pumpCollection(tester, favorites());
      expect(find.text('__favorites__'), findsNothing);
      expect(find.text('Favoris'), findsOneWidget);
    });

    testWidgets('semantics announce the translated name and the type', (
      tester,
    ) async {
      await pumpCollection(tester, favorites());
      expect(
        find.bySemanticsLabel(RegExp(r'Favoris.*favori')),
        findsOneWidget,
      );
    });

    testWidgets('the grouped-view pile wears the emblem too', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 150,
                  height: 210,
                  child: CollectionStackWidget(
                    group: CollectionGroup(
                      collection: favorites(),
                      books: [Book(title: 'A', owned: true)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(FavoriteRibbon), findsOneWidget);
      expect(find.text('__favorites__'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a manual collection keeps its name and gets no emblem', (
      tester,
    ) async {
      final manual = Collection(
        id: 'm',
        name: 'Cycle SF',
        source: 'manual',
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:00Z',
        totalBooks: 2,
      );
      await pumpCollection(tester, manual);
      expect(find.byType(FavoriteRibbon), findsNothing);
      expect(find.text('Cycle SF'), findsOneWidget);
    });
  });
}
