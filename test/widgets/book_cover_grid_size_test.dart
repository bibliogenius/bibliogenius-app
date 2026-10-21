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

  test('cover size is persisted', () async {
    await provider.setHomeCoverExtent(110);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('homeCoverExtent'), 110);
    expect(provider.homeCoverExtent, 110);
  });
}
