import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/book_repository.dart';
import 'package:bibliogenius/data/repositories/copy_repository.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/contact.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/borrow_book_screen.dart';
import 'package:bibliogenius/services/api_service.dart';

import '../helpers/mock_classes.dart';
import '../helpers/mock_repositories.dart';

void main() {
  group('BorrowBookScreen ISBN dedup', () {
    late MockApiService mockApi;
    late MockBookRepository mockBookRepo;
    late MockCopyRepository mockCopyRepo;
    late Contact testContact;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockApi = MockApiService();
      mockBookRepo = MockBookRepository();
      mockCopyRepo = MockCopyRepository();
      testContact = Contact(
        id: 42,
        type: 'borrower',
        name: 'Alice',
        libraryOwnerId: 1,
      );
    });

    Widget buildTestWidget() {
      return MultiProvider(
        providers: [
          Provider<ApiService>.value(value: mockApi),
          Provider<BookRepository>.value(value: mockBookRepo),
          Provider<CopyRepository>.value(value: mockCopyRepo),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(
          home: BorrowBookScreen(contact: testContact),
        ),
      );
    }

    // Helper: find the borrow button by its icon (library_add)
    Finder findBorrowButton() => find.byIcon(Icons.library_add);

    testWidgets(
      'reuses existing book when ISBN already in library',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        mockBookRepo.mockFindByIsbnResult = Book(
          id: 7,
          title: 'Existing Book',
          isbn: '9782752903570',
          author: 'Jack London',
        );

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Fill ISBN
        final isbnField = find.widgetWithText(TextFormField, 'ISBN');
        await tester.enterText(isbnField, '9782752903570');
        await tester.pumpAndSettle();

        // Trigger lookup via search icon
        await tester.tap(find.byIcon(Icons.search));
        await tester.pumpAndSettle();

        // findBookByIsbn was called
        expect(mockBookRepo.calls, contains('findBookByIsbn:9782752903570'));

        // Existing book alert is shown
        expect(find.byKey(const Key('existingBookAlert')), findsOneWidget);

        // Tap borrow button
        await tester.tap(findBorrowButton());
        await tester.pumpAndSettle();

        // createBook was NOT called
        expect(mockApi.createdBooks, isEmpty);

        // Copy was created with EXISTING book ID (7)
        expect(mockCopyRepo.createdCopies, hasLength(1));
        expect(mockCopyRepo.createdCopies.first['book_id'], 7);
        expect(mockCopyRepo.createdCopies.first['status'], 'borrowed');
        expect(mockCopyRepo.createdCopies.first['is_temporary'], true);
      },
    );

    testWidgets(
      'creates new book when ISBN not in library',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        mockBookRepo.mockFindByIsbnResult = null;
        mockApi.lookupResult = {
          'title': 'New External Book',
          'author': 'Some Author',
          'isbn': '9781234567890',
        };

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        final isbnField = find.widgetWithText(TextFormField, 'ISBN');
        await tester.enterText(isbnField, '9781234567890');
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.search));
        await tester.pumpAndSettle();

        expect(mockBookRepo.calls, contains('findBookByIsbn:9781234567890'));
        expect(find.byKey(const Key('existingBookAlert')), findsNothing);

        await tester.tap(findBorrowButton());
        await tester.pumpAndSettle();

        // createBook WAS called
        expect(mockApi.createdBooks, hasLength(1));

        // Copy created with new book ID (123 from mock)
        expect(mockCopyRepo.createdCopies, hasLength(1));
        expect(mockCopyRepo.createdCopies.first['book_id'], 123);
        expect(mockCopyRepo.createdCopies.first['status'], 'borrowed');
        expect(mockCopyRepo.createdCopies.first['is_temporary'], true);
      },
    );

    testWidgets(
      'creates new book when no ISBN provided (manual title entry)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Fill only title (no ISBN)
        final titleField = find.widgetWithText(TextFormField, 'title_label');
        await tester.enterText(titleField, 'Manual Book');
        await tester.pumpAndSettle();

        await tester.tap(findBorrowButton());
        await tester.pumpAndSettle();

        // findBookByIsbn NOT called
        expect(
          mockBookRepo.calls.where((c) => c.startsWith('findBookByIsbn')),
          isEmpty,
        );

        // createBook WAS called
        expect(mockApi.createdBooks, hasLength(1));

        // Copy created
        expect(mockCopyRepo.createdCopies, hasLength(1));
        expect(mockCopyRepo.createdCopies.first['book_id'], 123);
      },
    );
  });
}
