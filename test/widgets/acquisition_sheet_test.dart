import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/acquisition_sheet.dart';

/// The acquisition sheet, which replaces three stacked cards on a wished
/// book's page.
///
/// The property worth pinning is the one the cards did not have: a reader
/// whose network does not hold the book must be TOLD so. Each card rendered
/// nothing when it had nothing to say, so an empty network and a missing
/// feature looked exactly alike, which is how a real borrow offer went
/// unnoticed for a fortnight.
///
/// The provider rows themselves are not re-tested here: they are the shared
/// [BorrowProviderList], covered through the external suggestion sheet.
const _catalogue = {
  'en': {
    'acquire_book_title': 'Get hold of this book',
    'acquire_nobody_has_it': 'Nobody in your network has it right now.',
    'acquire_once_obtained': 'Once you have it',
    'acquire_i_borrowed_it': 'I borrowed it',
    'acquire_i_bought_it': 'I bought it',
    'acquire_add_to_wishlist': 'Add to my wishlist',
    'wishlist_available_from': 'Available from',
    'local_library_card_title': 'At my library',
    'bookshop_finder_title': 'At my bookshop',
    'bookshop_finder_hint': 'See availability in bookshops near you.',
    'bookshop_finder_configure': 'Configure',
    'settings_libraries_add': 'Add a library',
  },
};

Book _book({String? readingStatus, String? isbn = '9781617294556'}) => Book(
  id: 'b1',
  title: 'Rust in Action',
  isbn: isbn,
  readingStatus: readingStatus,
  owned: false,
);

void main() {
  late ThemeProvider theme;

  setUp(() {
    SharedPreferences.setMockInitialValues({'languageCode': 'en'});
    theme = ThemeProvider()..setLocaleSync(const Locale('en'));
    TranslationService.setPoTranslationsForTest(_catalogue);
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  /// Opens the sheet the way the page does, with the availability probe
  /// stubbed: the FFI is never initialized under test.
  Future<void> open(
    WidgetTester tester, {
    required Book book,
    VoidCallback? onBorrowed,
    VoidCallback? onBought,
    VoidCallback? onAddToWishlist,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: theme,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => AcquisitionSheet.show(
                  context,
                  book: book,
                  availabilityLoader: (_) async => const [],
                  onBorrowed: () async => onBorrowed?.call(),
                  onBought: () async => onBought?.call(),
                  onAddToWishlist: onAddToWishlist == null
                      ? null
                      : () async => onAddToWishlist(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('an empty network is stated, not left blank', (tester) async {
    await open(tester, book: _book(readingStatus: 'wanting'));

    // Section captions are uppercased in the widget, as everywhere else on
    // the book page (`bookMetadataCaptionStyle`).
    expect(find.text('AVAILABLE FROM'), findsOneWidget);
    expect(
      find.text('Nobody in your network has it right now.'),
      findsOneWidget,
      reason: 'the card this replaces simply disappeared instead',
    );
  });

  testWidgets('a book with no ISBN still gets a sheet that answers', (
    tester,
  ) async {
    await open(tester, book: _book(readingStatus: 'wanting', isbn: null));

    expect(find.text('Nobody in your network has it right now.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the wishlist door is offered only when the book is not wished', (
    tester,
  ) async {
    await open(
      tester,
      book: _book(readingStatus: 'to_read'),
      onAddToWishlist: () {},
    );
    expect(find.text('Add to my wishlist'), findsOneWidget);

    await open(tester, book: _book(readingStatus: 'wanting'));
    expect(find.text('Add to my wishlist'), findsNothing);
  });

  testWidgets('closing the loop reports back and dismisses the sheet', (
    tester,
  ) async {
    var borrowed = 0;
    var bought = 0;
    await open(
      tester,
      book: _book(readingStatus: 'wanting'),
      onBorrowed: () => borrowed++,
      onBought: () => bought++,
    );

    await tester.tap(find.byKey(const Key('acquireBoughtButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(bought, 1);
    expect(borrowed, 0);
    expect(
      find.text('Get hold of this book'),
      findsNothing,
      reason: 'the sheet closes on the action it just handed over',
    );
  });

  /// Pumps the sheet body at a chosen width, without the modal route: the
  /// branch under test is a LayoutBuilder, and driving the real window adds
  /// nothing but flakiness.
  Future<void> pumpAtWidth(WidgetTester tester, double width) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: AcquisitionSheet(
                  book: _book(readingStatus: 'wanting'),
                  availabilityLoader: (_) async => const [],
                  onBorrowed: () async {},
                  onBought: () async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the outcome pair sits on one line only when there is room', (
    tester,
  ) async {
    // A desktop sheet is 640 wide; a phone's is around 350, and half of that
    // truncates labels that are sentences, worse in German or Bulgarian.
    await pumpAtWidth(tester, 640);
    expect(
      tester.getRect(find.byKey(const Key('acquireBorrowedButton'))).top,
      closeTo(
        tester.getRect(find.byKey(const Key('acquireBoughtButton'))).top,
        0.5,
      ),
      reason: 'a wide sheet keeps the pair on one line',
    );

    await pumpAtWidth(tester, 390);
    expect(
      tester.getRect(find.byKey(const Key('acquireBoughtButton'))).top,
      greaterThanOrEqualTo(
        tester.getRect(find.byKey(const Key('acquireBorrowedButton'))).bottom,
      ),
      reason: 'a phone stacks them instead of halving the labels',
    );
  });

  testWidgets('the outcome controls clear the 44px tap target floor', (
    tester,
  ) async {
    await open(
      tester,
      book: _book(readingStatus: 'to_read'),
      onAddToWishlist: () {},
    );

    for (final key in [
      'acquireBorrowedButton',
      'acquireBoughtButton',
      'acquireAddToWishlistButton',
    ]) {
      final button = find.byKey(Key(key));
      expect(button, findsOneWidget, reason: '$key is missing');
      expect(
        tester.getSize(button).height,
        greaterThanOrEqualTo(44),
        reason: '$key is under the tap target floor',
      );
    }
  });
}
