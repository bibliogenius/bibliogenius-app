import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/not_owned_treatment.dart';
import 'package:bibliogenius/widgets/premium_book_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Book book({
  required bool owned,
  String? status,
  bool? isBorrowed,
  bool? isLent,
}) => Book(
  title: 'Le Livre',
  owned: owned,
  readingStatus: status,
  isBorrowed: isBorrowed,
  isLent: isLent,
);

void main() {
  group('showsLoanStateBadge', () {
    test('an unknown possession flag shows no loan pill', () {
      expect(showsLoanStateBadge(book(owned: true, status: 'read')), isFalse);
    });

    // Lent and borrowed at once: the copy in hand is the borrowed one.
    test('a book both lent and borrowed wears the borrowed label', () {
      final both = book(owned: true, isBorrowed: true, isLent: true);
      expect(showsLoanStateBadge(both), isTrue);
      expect(both.isBorrowed, isTrue);
    });

    // The point of the split: possession no longer masks the reading status.
    test(
      'a borrowed book keeps its reading status and wears the loan pill',
      () {
        final borrowedAndRead = book(
          owned: false,
          status: 'read',
          isBorrowed: true,
        );
        expect(borrowedAndRead.readingStatus, 'read');
        expect(showsLoanStateBadge(borrowedAndRead), isTrue);
      },
    );
  });

  // The card renders the SHARED not-owned vocabulary (ADR-063): partial
  // desaturation of the cover plus the OwnershipBadge, on both layouts.
  group('PremiumBookCard marks a not-owned book', () {
    late ThemeProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = ThemeProvider();
      TranslationService.setPoTranslationsForTest({
        'en': {
          'not_owned': 'Not owned',
          'reading_status_read': 'Read',
          'reading_status_borrowed': 'Borrowed',
          'reading_status_wanting': 'Want to read',
        },
      });
    });

    tearDown(() => TranslationService.setPoTranslationsForTest({}));

    Future<void> pump(WidgetTester tester, Book b, {required bool isHero}) {
      return tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600,
                height: 400,
                child: PremiumBookCard(book: b, isHero: isHero),
              ),
            ),
          ),
        ),
      );
    }

    /// The desaturation layer the shared treatment applies when marked.
    Finder desaturation() => find.descendant(
      of: find.byType(OwnershipCoverTreatment),
      matching: find.byType(ColorFiltered),
    );

    // The list passes isHero: true, the dashboard leaves it false. The marker
    // must reach both layouts: they are built by two different methods, and a
    // treatment added to only one silently misses the screen it was asked for.
    testWidgets('on the hero layout used by the library list', (tester) async {
      await pump(tester, book(owned: false, status: 'read'), isHero: true);
      expect(find.byType(OwnershipBadge), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
      expect(desaturation(), findsOneWidget);
    });

    testWidgets('on the standard layout used by the dashboard', (tester) async {
      await pump(tester, book(owned: false, status: 'read'), isHero: false);
      expect(find.byType(OwnershipBadge), findsOneWidget);
      expect(desaturation(), findsOneWidget);
    });

    // ADR-063: a wished book IS a not-owned book and wears the treatment.
    // Its heart is told ONCE, by the wanting status badge; the ownership
    // badge stands down there instead of repeating the same fact.
    testWidgets('a wished book desaturates but shows a single heart story', (
      tester,
    ) async {
      await pump(tester, book(owned: false, status: 'wanting'), isHero: false);
      expect(desaturation(), findsOneWidget);
      expect(find.byType(OwnershipBadge), findsNothing);
      expect(find.text('WANT TO READ'), findsOneWidget);
    });

    // Rule A1: the state must reach the screen reader, in natural casing.
    testWidgets('announces the state to the screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, book(owned: false, status: 'read'), isHero: true);

      expect(find.bySemanticsLabel(RegExp('Not owned')), findsOneWidget);

      handle.dispose();
    });

    // A reader who cleared the reading status carries an empty string, not
    // null. Both layouts used to guard the status pill on a null check, so
    // the empty value rendered `READING_STATUS_` in a gradient pill.
    testWidgets('a book left without a status wears no status pill', (
      tester,
    ) async {
      await pump(tester, book(owned: true, status: ''), isHero: true);
      expect(find.text('READING_STATUS_'), findsNothing);

      await pump(tester, book(owned: true, status: ''), isHero: false);
      expect(find.text('READING_STATUS_'), findsNothing);
    });

    testWidgets('and stays away from an owned book', (tester) async {
      await pump(tester, book(owned: true, status: 'read'), isHero: true);
      expect(find.byType(OwnershipBadge), findsNothing);
      expect(desaturation(), findsNothing);
    });

    testWidgets('and away from a borrowed book, already badged', (
      tester,
    ) async {
      await pump(
        tester,
        book(owned: false, status: 'read', isBorrowed: true),
        isHero: true,
      );
      expect(find.byType(OwnershipBadge), findsNothing);
      expect(desaturation(), findsNothing);
      expect(find.text('BORROWED'), findsOneWidget);
    });
  });
}
