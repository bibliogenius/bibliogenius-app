import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/premium_book_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Book book({required bool owned, String? status}) =>
    Book(title: 'Le Livre', owned: owned, readingStatus: status);

void main() {
  group('showsNotOwnedBadge', () {
    test('marks a book read but not owned', () {
      expect(showsNotOwnedBadge(book(owned: false, status: 'read')), isTrue);
    });

    test('marks an unclassified book that is not owned', () {
      expect(showsNotOwnedBadge(book(owned: false, status: null)), isTrue);
      expect(showsNotOwnedBadge(book(owned: false, status: 'to_read')), isTrue);
    });

    test('never marks an owned book', () {
      for (final status in ['read', 'to_read', 'reading', 'lent', null]) {
        expect(
          showsNotOwnedBadge(book(owned: true, status: status)),
          isFalse,
          reason: 'owned book with status $status',
        );
      }
    });

    // These already wear a status badge that says the same thing.
    test('does not double up on borrowed, lent or wished-for books', () {
      expect(
        showsNotOwnedBadge(book(owned: false, status: 'borrowed')),
        isFalse,
      );
      expect(showsNotOwnedBadge(book(owned: false, status: 'lent')), isFalse);
      expect(
        showsNotOwnedBadge(book(owned: false, status: 'wanting')),
        isFalse,
      );
    });
  });

  group('PremiumBookCard renders the badge', () {
    late ThemeProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = ThemeProvider();
      TranslationService.setPoTranslationsForTest({
        'en': {'not_owned': 'Not owned', 'reading_status_read': 'Read'},
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

    // The list passes isHero: true, the dashboard leaves it false. The badge must
    // reach both layouts: they are built by two different methods, and a marker
    // added to only one of them silently misses the screen it was asked for.
    testWidgets('on the hero layout used by the library list', (tester) async {
      await pump(tester, book(owned: false, status: 'read'), isHero: true);
      expect(find.text('NOT OWNED'), findsOneWidget);
    });

    testWidgets('on the standard layout used by the dashboard', (tester) async {
      await pump(tester, book(owned: false, status: 'read'), isHero: false);
      expect(find.text('NOT OWNED'), findsOneWidget);
    });

    // Rule A1: the marker must be announced once, in its natural casing. Without
    // excludeSemantics the child Text adds a second node reading "NOT OWNED",
    // which screen readers may spell out letter by letter.
    testWidgets('announces itself once, not in upper case', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, book(owned: false, status: 'read'), isHero: true);

      // The card merges the pill's label into its own node, so match on content.
      expect(find.bySemanticsLabel(RegExp('Not owned')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('NOT OWNED')), findsNothing);

      handle.dispose();
    });

    testWidgets('and stays away from an owned book', (tester) async {
      await pump(tester, book(owned: true, status: 'read'), isHero: true);
      expect(find.text('NOT OWNED'), findsNothing);
    });

    testWidgets('and away from a borrowed book, already badged', (
      tester,
    ) async {
      await pump(tester, book(owned: false, status: 'borrowed'), isHero: true);
      expect(find.text('NOT OWNED'), findsNothing);
    });
  });
}
