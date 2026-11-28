import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/book_repository.dart';
import 'package:bibliogenius/data/repositories/collection_repository.dart';
import 'package:bibliogenius/data/repositories/copy_repository.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/add_book_screen.dart';
import 'package:bibliogenius/services/api_service.dart';

import '../helpers/mock_classes.dart';
import '../helpers/mock_repositories.dart';

/// A scanned book that is already in the library shows a warning card. The
/// card offers to scan the next book, so a reader going through a pile does
/// not have to scroll down to the ISBN field's scan button.
void main() {
  const duplicateIsbn = '9782070360024';
  const nextIsbn = '9782246639718';

  late MockBookRepository books;
  late MockApiService api;
  // What the fake scanner hands back, and whether that book is new.
  late String scannedIsbn;
  late bool scannedIsNew;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dotenv.testLoad();
    books = MockBookRepository()
      ..mockFindByIsbnResult = Book(
        id: 'existing',
        title: 'L\'Étranger',
        author: 'Albert Camus',
        isbn: duplicateIsbn,
      );
    api = MockApiService();
    scannedIsbn = nextIsbn;
    scannedIsNew = true;
  });

  /// The scan route stands in for the camera: it hands back [scannedIsbn].
  Future<void> pumpAddScreen(
    WidgetTester tester, {
    String? isbn = duplicateIsbn,
  }) async {
    final router = GoRouter(
      initialLocation: '/add',
      routes: [
        GoRoute(path: '/add', builder: (_, _) => AddBookScreen(isbn: isbn)),
        GoRoute(
          path: '/scan',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () {
                if (scannedIsNew) books.mockFindByIsbnResult = null;
                context.pop(scannedIsbn);
              },
              child: const Text('fake scanner'),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<BookRefreshNotifier>(
            create: (_) => BookRefreshNotifier(),
          ),
          Provider<BookRepository>.value(value: books),
          Provider<CollectionRepository>.value(
            value: MockCollectionRepository(),
          ),
          Provider<CopyRepository>.value(value: MockCopyRepository()),
          Provider<ApiService>.value(value: api),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  final scanAnother = find.byKey(const Key('duplicateScanAnotherButton'));

  testWidgets('the duplicate card offers to scan another book', (
    tester,
  ) async {
    await pumpAddScreen(tester);

    expect(scanAnother, findsOneWidget);
  });

  testWidgets('scanning another book replaces the duplicate with the new '
      'ISBN and looks it up', (tester) async {
    await pumpAddScreen(tester);

    await tester.tap(scanAnother);
    await tester.pumpAndSettle();
    await tester.tap(find.text('fake scanner'));
    // Past the ISBN field's lookup debounce.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(books.calls, contains('findBookByIsbn:$nextIsbn'));
    expect(api.lookups, contains('lookupBook:$nextIsbn'));
    expect(scanAnother, findsNothing);
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('isbnField')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller?.text, nextIsbn);
  });

  testWidgets('scanning the same book again keeps the duplicate card, even '
      'when its ISBN was typed with dashes', (tester) async {
    await pumpAddScreen(tester, isbn: null);
    await tester.enterText(
      find.byKey(const Key('isbnField')),
      '978-2-07-036002-4',
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(scanAnother, findsOneWidget);

    scannedIsbn = duplicateIsbn;
    scannedIsNew = false;
    await tester.tap(scanAnother);
    await tester.pumpAndSettle();
    await tester.tap(find.text('fake scanner'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(scanAnother, findsOneWidget);
  });

  testWidgets('leaving the scanner without a code keeps the duplicate card', (
    tester,
  ) async {
    await pumpAddScreen(tester);

    await tester.tap(scanAnother);
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.text('fake scanner')));
    router.pop();
    await tester.pumpAndSettle();

    expect(scanAnother, findsOneWidget);
    expect(books.calls, isNot(contains('findBookByIsbn:$nextIsbn')));
  });
}
