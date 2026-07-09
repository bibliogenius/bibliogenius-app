import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/copy.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/utils/returned_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Book book({
  bool owned = false,
  String? status,
  int? rating,
  DateTime? started,
  DateTime? finished,
}) => Book(
  title: 'Le Livre',
  owned: owned,
  readingStatus: status,
  userRating: rating,
  startedReadingAt: started,
  finishedReadingAt: finished,
);

Copy copy() => Copy(bookId: 'b1', libraryId: 1, status: 'borrowed');

void main() {
  group('canOfferToRemove', () {
    test('offers removal for a returned book with no copy left', () {
      expect(canOfferToRemove(book(), [copy()]), isTrue);
      expect(canOfferToRemove(book(), []), isTrue);
    });

    test('never offers to remove a book the user owns', () {
      expect(canOfferToRemove(book(owned: true), [copy()]), isFalse);
    });

    test('never offers removal while another copy remains', () {
      expect(canOfferToRemove(book(), [copy(), copy()]), isFalse);
    });
  });

  group('returnedBookLooksUntouched', () {
    test('a book the loan created, left at its defaults', () {
      expect(returnedBookLooksUntouched(book(status: 'to_read')), isTrue);
      expect(returnedBookLooksUntouched(book(status: null)), isTrue);
      expect(returnedBookLooksUntouched(book(status: '')), isTrue);
    });

    // Everything below is something the reader entered. Removing the book would
    // throw it away, so the offer must stay the quiet option.
    test('a rating makes it touched', () {
      expect(
        returnedBookLooksUntouched(book(status: 'to_read', rating: 8)),
        isFalse,
      );
    });

    test('reading dates make it touched', () {
      expect(
        returnedBookLooksUntouched(
          book(status: 'to_read', started: DateTime(2026, 7, 1)),
        ),
        isFalse,
      );
      expect(
        returnedBookLooksUntouched(
          book(status: 'to_read', finished: DateTime(2026, 7, 8)),
        ),
        isFalse,
      );
    });

    test('a reading status the user chose makes it touched', () {
      for (final status in ['read', 'reading', 'abandoned']) {
        expect(
          returnedBookLooksUntouched(book(status: status)),
          isFalse,
          reason: status,
        );
      }
    });
  });

  group('askToRemoveReturnedBook', () {
    late ThemeProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = ThemeProvider();
      TranslationService.setPoTranslationsForTest({
        'en': {
          'return_kept_title': 'Book returned',
          'return_kept_body': 'It stays in your library.',
          'return_keep_action': 'Keep it',
          'return_remove_action': 'Remove it',
        },
      });
    });

    tearDown(() => TranslationService.setPoTranslationsForTest({}));

    /// Opens the dialog and exposes what the call finally returned.
    Future<bool? Function()> open(WidgetTester tester, Book b) async {
      bool? result;
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    result = await askToRemoveReturnedBook(context, b);
                  },
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return () => result;
    }

    // The invariant of the whole feature: nothing is deleted unless the user says
    // so. Dismissing the dialog by tapping the barrier must keep the book.
    testWidgets('dismissing the dialog keeps the book', (tester) async {
      final result = await open(tester, book(status: 'to_read'));
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(result(), isFalse, reason: 'a dismissed dialog removes nothing');
    });

    testWidgets('choosing to keep removes nothing', (tester) async {
      final result = await open(tester, book(status: 'to_read'));
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(result(), isFalse);
    });

    testWidgets('removal happens only on an explicit tap', (tester) async {
      final result = await open(tester, book(status: 'to_read'));
      await tester.tap(find.text('Remove it'));
      await tester.pumpAndSettle();
      expect(result(), isTrue);
    });

    // A book carrying reading data must not have removal as the emphasised button.
    testWidgets('a touched book emphasises keeping', (tester) async {
      await open(tester, book(status: 'read', rating: 9));
      final filled = tester.widget<FilledButton>(find.byType(FilledButton));
      expect((filled.child! as Text).data, 'Keep it');
    });

    testWidgets('an untouched book emphasises removing', (tester) async {
      await open(tester, book(status: 'to_read'));
      final filled = tester.widget<FilledButton>(find.byType(FilledButton));
      expect((filled.child! as Text).data, 'Remove it');
    });
  });
}
