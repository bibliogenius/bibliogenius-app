import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/utils/book_status.dart';
import 'package:bibliogenius/widgets/book_cover_card.dart';
import 'package:bibliogenius/widgets/premium_book_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The library grid, the library list and the dashboard each draw a reading
// status pill, from three different build methods. They used to disagree: the
// list wore the theme gradient whatever the status, and the two others a
// translucent Material colour too light for their white text. All three now
// take their colours from `statusBadgeColors`, which these tests hold them to,
// and the two drawn over a cover add the white `statusPillCoverBorder`.
void main() {
  late ThemeProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'reading_status_to_read': 'To read',
        'reading_status_reading': 'Reading',
      },
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  Future<void> pump(WidgetTester tester, Widget card) {
    return tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(body: Center(child: card)),
        ),
      ),
    );
  }

  /// The fill and outline of the pill around [label], and its text colour.
  ({Color? background, Color? foreground, BoxBorder? border}) pillColors(
    WidgetTester tester,
    String label,
  ) {
    final text = tester.widget<Text>(find.text(label));
    final box = tester.widget<Container>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Container))
          .first,
    );
    final decoration = box.decoration as BoxDecoration?;
    return (
      background: decoration?.gradient == null ? decoration?.color : null,
      foreground: text.style?.color,
      border: decoration?.border,
    );
  }

  for (final (status, label) in [
    ('to_read', 'TO READ'),
    ('reading', 'READING'),
  ]) {
    final expected = statusBadgeColors(
      individualStatuses.firstWhere((s) => s.value == status),
    );
    final book = Book(title: 'Le Livre', owned: true, readingStatus: status);

    group('the $status pill', () {
      testWidgets('on the library list', (tester) async {
        await pump(
          tester,
          SizedBox(
            width: 600,
            height: 400,
            child: PremiumBookCard(book: book, isHero: true),
          ),
        );
        // On the card surface, beside the title: no cover to stand out on.
        expect(pillColors(tester, label), (
          background: expected.background,
          foreground: expected.foreground,
          border: null,
        ));
      });

      testWidgets('on the dashboard', (tester) async {
        await pump(
          tester,
          SizedBox(width: 160, height: 240, child: PremiumBookCard(book: book)),
        );
        expect(pillColors(tester, label), (
          background: expected.background,
          foreground: expected.foreground,
          border: statusPillCoverBorder,
        ));
      });

      testWidgets('on the library grid', (tester) async {
        await pump(
          tester,
          SizedBox(
            width: 160,
            height: 240,
            child: BookCoverCard(book: book, onTap: () {}),
          ),
        );
        expect(pillColors(tester, label), (
          background: expected.background,
          foreground: expected.foreground,
          border: statusPillCoverBorder,
        ));
      });
    });
  }

  // Below 120 px the grid pill folds to the status icon alone, on the same
  // fill: the icon takes the text colour so it stays readable too.
  testWidgets('the folded grid pill draws its icon in the text colour', (
    tester,
  ) async {
    final expected = statusBadgeColors(
      individualStatuses.firstWhere((s) => s.value == 'to_read'),
    );
    await pump(
      tester,
      SizedBox(
        width: 80,
        height: 130,
        child: BookCoverCard(
          book: Book(title: 'Le Livre', owned: true, readingStatus: 'to_read'),
          onTap: () {},
        ),
      ),
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.bookmark_border));
    expect(icon.color, expected.foreground);
    final box = tester.widget<Container>(
      find
          .ancestor(
            of: find.byIcon(Icons.bookmark_border),
            matching: find.byType(Container),
          )
          .first,
    );
    expect((box.decoration as BoxDecoration).color, expected.background);
    expect((box.decoration as BoxDecoration).border, statusPillCoverBorder);
  });
}
