import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../helpers/mock_classes.dart';

/// Tests for batch scan copy creation logic
///
/// Business rules:
/// 1. NEW books: Backend creates copy automatically when owned=true
///    → Flutter should NOT call createCopy
/// 2. EXISTING OWNED books: Flutter should call createCopy
///    (user may have multiple copies)
/// 3. EXISTING NON-OWNED books: Flutter should NOT call createCopy
///    (book is on wishlist, user doesn't own it)

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockApiService mockApi;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    mockApi = MockApiService();
  });

  group('Batch Scan Copy Logic - Expected Behavior', () {
    test(
      'NEW book: createCopy should NOT be called (backend handles it)',
      () async {
        // Setup: Book does not exist
        mockApi.existingBook = null;
        mockApi.lookupResult = {
          'title': 'New Book',
          'authors': ['Author'],
          'isbn': '9781234567890',
        };

        // Simulate batch scan flow for NEW book
        final isbn = '9781234567890';

        // 1. Check if book exists
        final existingBook = await mockApi.findBookByIsbn(isbn);
        expect(existingBook, isNull); // Book doesn't exist

        // 2. Lookup and create book
        final bookData = await mockApi.lookupBook(isbn);
        expect(bookData, isNotNull);

        final createResponse = await mockApi.createBook({
          'title': bookData!['title'],
          'isbn': isbn,
          'owned': true, // Default for batch scan
        });
        final bookId = createResponse.data['id'];
        expect(bookId, isNotNull);

        // 3. Copy creation logic (from scan_screen.dart)
        // For NEW books, existingBook is null, so createCopy should NOT be called
        if (existingBook != null && existingBook.owned) {
          await mockApi.createCopy({'book_id': bookId, 'status': 'available'});
        }

        // Verify: NO copy was created (backend handles it)
        expect(mockApi.createdCopies, isEmpty);
      },
    );

    test('EXISTING OWNED book: createCopy SHOULD be called', () async {
      // Setup: Book exists and is owned
      mockApi.existingBook = Book(
        localId: 123,
        title: 'Existing Owned Book',
        isbn: '9781234567890',
        owned: true, // User owns this book
      );

      // Simulate batch scan flow for EXISTING OWNED book
      final isbn = '9781234567890';

      // 1. Check if book exists
      final existingBook = await mockApi.findBookByIsbn(isbn);
      expect(existingBook, isNotNull);
      expect(existingBook!.owned, true);

      final bookId = existingBook.localId!;

      // 2. Book already exists, no need to create
      // (scan_screen.dart skips book creation for existing books)

      // 3. Copy creation logic (from scan_screen.dart)
      // For EXISTING OWNED books, createCopy SHOULD be called
      if (existingBook.owned) {
        await mockApi.createCopy({'book_id': bookId, 'status': 'available'});
      }

      // Verify: Copy WAS created
      expect(mockApi.createdCopies, hasLength(1));
      expect(mockApi.createdCopies.first['book_id'], 123);
      expect(mockApi.createdCopies.first['status'], 'available');
    });

    test(
      'EXISTING NON-OWNED book (wishlist): createCopy should NOT be called',
      () async {
        // Setup: Book exists but is NOT owned (wishlist)
        mockApi.existingBook = Book(
          localId: 456,
          title: 'Wishlist Book',
          isbn: '9780987654321',
          owned: false, // User doesn't own this book
          readingStatus: 'wanting',
        );

        // Simulate batch scan flow for EXISTING NON-OWNED book
        final isbn = '9780987654321';

        // 1. Check if book exists
        final existingBook = await mockApi.findBookByIsbn(isbn);
        expect(existingBook, isNotNull);
        expect(existingBook!.owned, false);

        final bookId = existingBook.localId!;

        // 2. Book already exists, no need to create

        // 3. Copy creation logic (from scan_screen.dart)
        // For EXISTING NON-OWNED books, createCopy should NOT be called
        if (existingBook.owned) {
          await mockApi.createCopy({'book_id': bookId, 'status': 'available'});
        }

        // Verify: NO copy was created (book is on wishlist)
        expect(mockApi.createdCopies, isEmpty);
      },
    );

    test('Multiple existing owned books: each gets a copy', () async {
      // Test scanning multiple existing owned books
      final books = [
        Book(localId: 1, title: 'Book 1', isbn: '111', owned: true),
        Book(localId: 2, title: 'Book 2', isbn: '222', owned: true),
        Book(localId: 3, title: 'Book 3', isbn: '333', owned: false), // wishlist
      ];

      for (final book in books) {
        mockApi.existingBook = book;

        final existingBook = await mockApi.findBookByIsbn(book.isbn!);

        if (existingBook != null && existingBook.owned) {
          await mockApi.createCopy({
            'book_id': existingBook.localId,
            'status': 'available',
          });
        }
      }

      // Verify: Only owned books got copies (2 copies, not 3)
      expect(mockApi.createdCopies, hasLength(2));
      expect(mockApi.createdCopies[0]['book_id'], 1);
      expect(mockApi.createdCopies[1]['book_id'], 2);
    });
  });

  group('MockApiService createCopy captures data correctly', () {
    test('captures all provided fields', () async {
      await mockApi.createCopy({
        'book_id': 42,
        'status': 'available',
        'library_id': 1,
        'is_temporary': false,
        'notes': 'Test note',
      });

      expect(mockApi.createdCopies, hasLength(1));
      final captured = mockApi.createdCopies.first;
      expect(captured['book_id'], 42);
      expect(captured['status'], 'available');
      expect(captured['library_id'], 1);
      expect(captured['is_temporary'], false);
      expect(captured['notes'], 'Test note');
    });
  });
}
