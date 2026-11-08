import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/widgets/book_cover_card.dart';
import 'package:bibliogenius/widgets/book_cover_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The home page cover size (Settings > Theme): the grid's maximum tile width
// follows the setting, and the setting survives a restart.
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
              maxCoverExtent: extent,
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
              maxCoverExtent: ThemeProvider.homeCoverExtentSteps.first,
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

  test('cover size is persisted', () async {
    await provider.setHomeCoverExtent(110);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('homeCoverExtent'), 110);
    expect(provider.homeCoverExtent, 110);
  });
}
