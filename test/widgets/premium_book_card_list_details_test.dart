import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/premium_book_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Book book({
  String? author = 'Une Autrice',
  String? publisher,
  int? year,
  int? pages,
  String? summary,
  String? status,
  bool? isBorrowed,
}) => Book(
  title: 'Le Livre',
  author: author,
  owned: true,
  publisher: publisher,
  publicationYear: year,
  pageCount: pages,
  summary: summary,
  readingStatus: status,
  isBorrowed: isBorrowed,
);

void main() {
  // The library list (hero layout) shows the facts the card has room for,
  // beyond title and author: publisher, year, page count and the summary.
  group('PremiumBookCard hero layout shows the book facts', () {
    late ThemeProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = ThemeProvider();
      TranslationService.setPoTranslationsForTest({
        'en': {
          'pages_suffix': 'p.',
          'publisher_label': 'Publisher',
          'year_label': 'Year',
          'page_count_label': 'Pages',
        },
      });
    });

    tearDown(() => TranslationService.setPoTranslationsForTest({}));

    Future<void> pump(WidgetTester tester, Book b, {bool isHero = true}) {
      return tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 600,
                  child: PremiumBookCard(book: b, isHero: isHero),
                ),
              ),
            ),
          ),
        ),
      );
    }

    /// The author-and-facts line of the info column (the fallback cover
    /// paints the title and author too).
    String authorLine(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const Key('premiumBookCardAuthorFacts')))
        .textSpan!
        .toPlainText();

    // A desktop reader clicks; a phone or tablet reader taps.
    for (final (platform, key) in [
      (TargetPlatform.macOS, 'click_to_view'),
      (TargetPlatform.windows, 'click_to_view'),
      (TargetPlatform.linux, 'click_to_view'),
      (TargetPlatform.iOS, 'tap_to_view'),
      (TargetPlatform.android, 'tap_to_view'),
    ]) {
      testWidgets('the hint says $key on ${platform.name}', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await pump(tester, book());
          expect(find.text(key), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets('after the author, publisher, year and pages', (tester) async {
      await pump(tester, book(publisher: 'Gallimard', year: 1998, pages: 320));
      expect(authorLine(tester), 'Une Autrice · Gallimard · 1998 · 320 p.');
    });

    testWidgets('leaving out what the record does not hold', (tester) async {
      await pump(tester, book(publisher: '  ', year: 1998, pages: 0));
      expect(authorLine(tester), 'Une Autrice · 1998');
    });

    testWidgets('the author alone when it holds none', (tester) async {
      await pump(tester, book());
      expect(authorLine(tester), 'Une Autrice');
    });

    testWidgets('the facts alone for a book without author', (tester) async {
      await pump(tester, book(author: null, year: 1998, pages: 320));
      expect(authorLine(tester), '1998 · 320 p.');
    });

    // The pills follow the title on its row, rather than sitting above it.
    testWidgets('the status and loan pills right after the title', (
      tester,
    ) async {
      TranslationService.setPoTranslationsForTest({
        'en': {
          'reading_status_read': 'Read',
          'reading_status_borrowed': 'Borrowed',
        },
      });
      await pump(tester, book(status: 'read', isBorrowed: true));

      final title = tester.getRect(
        find.byKey(const Key('premiumBookCardTitle')),
      );
      // Right after a short title, not pushed to the card's far edge.
      for (final pill in [find.text('READ'), find.text('BORROWED')]) {
        final gap = tester.getRect(pill).left - title.right;
        expect(gap, greaterThan(0));
        expect(gap, lessThan(40));
      }
      // The first pill on the title's first line; the loan pill below it.
      final status = tester.getRect(find.text('READ'));
      expect(status.top, lessThan(title.bottom));
      expect(
        tester.getRect(find.text('BORROWED')).top,
        greaterThan(status.top),
      );
    });

    testWidgets('the summary, on two lines, line breaks folded', (
      tester,
    ) async {
      await pump(tester, book(summary: 'First line.\n\n  Second   line.'));
      final summary = tester.widget<Text>(
        find.text('First line. Second line.'),
      );
      expect(summary.maxLines, 2);
      expect(summary.overflow, TextOverflow.ellipsis);
    });

    testWidgets('no summary block for a blank summary', (tester) async {
      await pump(tester, book(summary: ' \n '));
      expect(find.byKey(const Key('premiumBookCardSummary')), findsNothing);
    });

    // Rule A1: the card label replaces its texts for screen readers, so the
    // new facts must be in it, spelled out rather than abbreviated.
    testWidgets('and announces the facts, not the summary', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        book(
          publisher: 'Gallimard',
          year: 1998,
          pages: 320,
          summary: 'A long story.',
        ),
      );

      expect(
        find.bySemanticsLabel(
          'Le Livre, Une Autrice, Publisher: Gallimard, Year: 1998, '
          'Pages: 320',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('A long story')), findsNothing);

      handle.dispose();
    });

    testWidgets('while the dashboard card stays as it was', (tester) async {
      await pump(
        tester,
        book(publisher: 'Gallimard', year: 1998, summary: 'A long story.'),
        isHero: false,
      );
      expect(find.textContaining('Gallimard'), findsNothing);
      expect(find.textContaining('A long story'), findsNothing);
    });
  });
}
