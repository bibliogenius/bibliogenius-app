import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/collection.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/widgets/book_cover_card.dart';
import 'package:bibliogenius/widgets/book_cover_grid.dart';
import 'package:bibliogenius/widgets/collection_stack_widget.dart';
import 'package:bibliogenius/widgets/favorite_ribbon.dart';
import 'package:bibliogenius/widgets/not_owned_treatment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The home page cover size (Settings > Theme): the grid's column count
// follows the setting, the smallest size holds up on a phone, and the
// setting survives a restart.
void main() {
  late ThemeProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = ThemeProvider();
  });

  final books = [
    for (var i = 0; i < 6; i++)
      Book(id: '$i', title: 'Book $i', author: 'Author', owned: true),
  ];

  Future<double> tileWidth(WidgetTester tester, double extent) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: BookCoverGrid(
              books: books,
              onBookTap: (_) {},
              coverSize: extent,
            ),
          ),
        ),
      ),
    );
    return tester.getSize(find.byType(BookCoverCard).first).width;
  }

  testWidgets('smaller setting draws narrower covers', (tester) async {
    final steps = ThemeProvider.homeCoverExtentSteps;
    final small = await tileWidth(tester, steps.first);
    final large = await tileWidth(tester, steps.last);

    expect(small, lessThanOrEqualTo(steps.first));
    expect(large, lessThanOrEqualTo(steps.last));
    expect(small, lessThan(large));
  });

  testWidgets('on a 375 pt phone the three sizes draw three widths', (
    tester,
  ) async {
    // The width where "small" used to fall back to "medium": both fitted 3
    // columns in the 343 px grid.
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final steps = ThemeProvider.homeCoverExtentSteps;
    final widths = [for (final e in steps) await tileWidth(tester, e)];

    expect(widths[0], lessThan(widths[1]));
    expect(widths[1], lessThan(widths[2]));
  });

  testWidgets('six small covers fit a 360 dp phone row, badges and all', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // No cover image (fallback title), a reading status, a favorite and the
    // "new" band: the most crowded tile.
    final crowded = [
      for (var i = 0; i < 12; i++)
        Book(
          id: 'c$i',
          title: 'A rather long title for a tiny cover $i',
          author: 'Some Author',
          owned: true,
          readingStatus: 'reading',
          addedAt: DateTime.now(),
        ),
    ];
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: BookCoverGrid(
              books: [...crowded, ...books],
              onBookTap: (_) {},
              coverSize: ThemeProvider.homeCoverExtentSteps.first,
              favoriteIds: {for (final b in crowded) b.id!},
              showNewBadge: true,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final first = tester.getTopLeft(find.byType(BookCoverCard).at(0));
    final sixth = tester.getTopLeft(find.byType(BookCoverCard).at(5));
    final seventh = tester.getTopLeft(find.byType(BookCoverCard).at(6));
    expect(sixth.dy, first.dy, reason: 'six covers on the first row');
    expect(seventh.dy, greaterThan(first.dy));
  });

  final small = ThemeProvider.homeCoverExtentSteps.first;

  void phoneScreen(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  bool overlaps(Rect a, Rect b) =>
      a.intersect(b).width > 0.5 && a.intersect(b).height > 0.5;

  for (final width in <double>[320, 360, 393]) {
    testWidgets('small at $width dp: a not-owned book keeps both badges apart '
        'and inside the cover', (tester) async {
      phoneScreen(tester, width);
      final notOwned = [
        for (var i = 0; i < 6; i++)
          Book(
            id: 'n$i',
            title: 'Not mine $i',
            author: 'Author',
            owned: false,
            readingStatus: 'read',
          ),
      ];
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: BookCoverGrid(
                books: notOwned,
                onBookTap: (_) {},
                coverSize: small,
                favoriteIds: {'n0'},
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      for (var i = 0; i < 2; i++) {
        final card = find.byType(BookCoverCard).at(i);
        final cover = tester.getRect(card);
        final owned = tester.getRect(
          find.descendant(of: card, matching: find.byType(OwnershipBadge)),
        );
        final status = tester.getRect(
          find.descendant(of: card, matching: find.byType(Tooltip)),
        );
        expect(overlaps(owned, status), isFalse, reason: 'card $i');
        if (i == 0) {
          // The favorite ribbon keeps the right-hand corner, clear of both.
          final ribbon = tester.getRect(
            find.descendant(of: card, matching: find.byType(FavoriteRibbon)),
          );
          expect(overlaps(ribbon, owned), isFalse, reason: 'ribbon');
          expect(overlaps(ribbon, status), isFalse, reason: 'ribbon');
        }
        expect(cover.contains(status.topLeft), isTrue, reason: 'card $i');
        expect(cover.contains(status.bottomRight), isTrue, reason: 'card $i');
      }
    });

    testWidgets('small at $width dp: the collections grid does not overflow', (
      tester,
    ) async {
      phoneScreen(tester, width);
      Book book(String id) =>
          Book(id: id, title: 'Volume $id', author: 'Author', owned: true);
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: CollectionGroupGrid(
                groups: [
                  for (var c = 0; c < 6; c++)
                    CollectionGroup(
                      collection: Collection(
                        id: 'c$c',
                        name: 'Series $c',
                        source: 'series',
                        createdAt: '2026-01-01',
                        updatedAt: '2026-01-01',
                      ),
                      books: [book('${c}a'), book('${c}b'), book('${c}c')],
                    ),
                ],
                onBookTap: (_) {},
                coverSize: small,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('small rows stay far enough apart for the favorite ribbon', (
    tester,
  ) async {
    phoneScreen(tester, 375);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: BookCoverGrid(
              books: [
                for (var i = 0; i < 12; i++)
                  Book(id: 'f$i', title: 'Fav $i', author: 'A', owned: true),
              ],
              onBookTap: (_) {},
              coverSize: small,
              favoriteIds: {for (var i = 0; i < 12; i++) 'f$i'},
            ),
          ),
        ),
      ),
    );

    final above = tester.getRect(find.byType(BookCoverCard).at(0));
    final below = tester.getRect(find.byType(BookCoverCard).at(6));
    // The ribbon of the cover below overhangs its top edge.
    expect(
      below.top - above.bottom,
      greaterThanOrEqualTo(FavoriteRibbon.overhangFor(12)),
    );
  });

  test('cover size is persisted', () async {
    await provider.setHomeCoverExtent(110);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('homeCoverExtent'), 110);
    expect(provider.homeCoverExtent, 110);
  });
}
