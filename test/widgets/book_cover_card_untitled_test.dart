import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/book_cover_card.dart';
import 'package:bibliogenius/widgets/book_spine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A book with no title is a real case on the peer screen: manually entered
/// books reach the hub catalog with `title: ""`, and the tile used to render
/// as a blank coloured rectangle with nothing to read or announce.
void main() {
  late ThemeProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {'book_untitled': 'Untitled book'},
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(body: SizedBox(width: 150, height: 220, child: child)),
        ),
      ),
    );
  }

  group('BookCoverCard', () {
    testWidgets('a title-less book falls back to its ISBN', (tester) async {
      await pump(
        tester,
        BookCoverCard(
          book: Book(title: '', isbn: '9782070322886'),
          onTap: () {},
        ),
      );

      expect(find.text('9782070322886'), findsOneWidget);
    });

    testWidgets('a book with neither title nor ISBN shows the placeholder', (
      tester,
    ) async {
      await pump(
        tester,
        BookCoverCard(
          book: Book(title: ''),
          onTap: () {},
        ),
      );

      expect(find.text('Untitled book'), findsOneWidget);
    });

    testWidgets('a normal book still shows its own title', (tester) async {
      await pump(
        tester,
        BookCoverCard(
          book: Book(title: 'Nadja', isbn: '9782070322886'),
          onTap: () {},
        ),
      );

      expect(find.text('Nadja'), findsOneWidget);
      expect(find.text('9782070322886'), findsNothing);
    });
  });

  group('BookSpine', () {
    testWidgets('a title-less spine falls back to its ISBN', (tester) async {
      await pump(
        tester,
        BookSpine.fromBook(
          book: Book(title: '', isbn: '9782070322886'),
        ),
      );

      expect(find.text('9782070322886'), findsOneWidget);
    });
  });
}
