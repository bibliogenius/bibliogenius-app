import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/wish_line.dart';

Book book({String? status, bool? wanted, List<String>? wishedBy}) => Book(
  title: 'Dune',
  owned: false,
  readingStatus: status,
  wanted: wanted,
  wishedBy: wishedBy,
);

void main() {
  setUp(() {
    TranslationService.setPoTranslationsForTest({
      'en': {
        'wishlist_wished_by': 'Wished by {names}',
        'wishlist_remove_action': 'Remove from wishlist',
        'reading_status_wanting': 'Want to Read',
      },
    });
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    final themeProvider = ThemeProvider()..setLocaleSync(const Locale('en'));
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
  }

  test('the line only shows when it adds to the status pill', () {
    expect(WishLine.shows(book(status: 'read')), isFalse);
    expect(WishLine.shows(book(status: 'wanting')), isFalse);
    expect(WishLine.shows(book(status: 'read', wanted: true)), isTrue);
    expect(
      WishLine.shows(book(status: 'wanting', wishedBy: ['Alice'])),
      isTrue,
    );
  });

  testWidgets('names the wishers and offers the removal to a reader', (
    tester,
  ) async {
    var removed = 0;
    await pump(
      tester,
      WishLine(
        book: book(status: 'read', wanted: true, wishedBy: ['Alice', 'Bruno']),
        onRemove: () => removed++,
      ),
    );
    expect(find.text('Wished by Alice, Bruno'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove from wishlist'));
    expect(removed, 1);
  });

  // The wisher sees "wanting" on the pill already: the line adds the names
  // only, and the pill (status picker) is where they leave the wish.
  testWidgets('offers no removal when the pill shows the wish', (tester) async {
    await pump(
      tester,
      WishLine(
        book: book(status: 'wanting', wishedBy: ['Alice']),
        onRemove: () {},
      ),
    );
    expect(find.text('Wished by Alice'), findsOneWidget);
    expect(find.byTooltip('Remove from wishlist'), findsNothing);
  });

  testWidgets('falls back to the plain wish when nobody is named', (
    tester,
  ) async {
    await pump(tester, WishLine(book: book(status: 'read', wanted: true)));
    expect(find.text('Want to Read'), findsOneWidget);
  });
}
