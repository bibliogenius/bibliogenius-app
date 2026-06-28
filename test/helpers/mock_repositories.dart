import 'package:bibliogenius/data/repositories/book_repository.dart';
import 'package:bibliogenius/data/repositories/tag_repository.dart';
import 'package:bibliogenius/data/repositories/contact_repository.dart';
import 'package:bibliogenius/data/repositories/collection_repository.dart';
import 'package:bibliogenius/data/repositories/copy_repository.dart';
import 'package:bibliogenius/data/repositories/loan_repository.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/models/contact.dart';
import 'package:bibliogenius/models/collection.dart';
import 'package:bibliogenius/models/collection_book.dart';
import 'package:bibliogenius/models/collection_deletion_preview.dart';
import 'package:bibliogenius/models/copy.dart';
import 'package:bibliogenius/models/loan.dart';

class MockBookRepository implements BookRepository {
  List<Book> mockBooks = [];
  Book? mockBook;
  Book? mockFindByIsbnResult;
  final List<String> calls = [];

  @override
  Future<List<Book>> getBooks({
    String? status,
    String? author,
    String? title,
    String? tag,
  }) async => mockBooks;

  @override
  Future<Book> getBook(String uuid, {int? localId}) async =>
      mockBook ?? (throw Exception('Book not found'));

  @override
  Future<Book> getBookByLocalId(int localId) async =>
      mockBook ?? (throw Exception('Book not found'));

  @override
  Future<Book> createBook(Map<String, dynamic> bookData) async {
    calls.add('createBook:${bookData['isbn']}');
    return mockBook ?? Book(localId: 1, title: bookData['title'] ?? 'Test');
  }

  @override
  Future<Book> updateBook(
    String uuid,
    Map<String, dynamic> bookData, {
    int? localId,
  }) async => mockBook ?? Book(id: uuid, title: bookData['title'] ?? 'Updated');

  @override
  Future<void> deleteBook(String uuid, {int? localId}) async {}

  @override
  Future<void> reorderBooks(List<int> bookIds) async {}

  @override
  Future<Book?> findBookByIsbn(String isbn) async {
    calls.add('findBookByIsbn:$isbn');
    return mockFindByIsbnResult;
  }

  @override
  Future<List<String>> getAllAuthors() async => mockBooks
      .where((b) => b.author != null)
      .map((b) => b.author!)
      .toSet()
      .toList();
}

class MockTagRepository implements TagRepository {
  List<Tag> mockTags = [];

  @override
  Future<List<Tag>> getTags() async => mockTags;

  @override
  Future<Tag> createTag(String name, {int? parentId}) async =>
      Tag(id: 1, name: name, parentId: parentId, count: 0);

  @override
  Future<Tag> updateTag(String uuid, String name, {int? parentId}) async =>
      Tag(id: 1, uuid: uuid, name: name, parentId: parentId, count: 0);

  @override
  Future<void> deleteTag(String uuid) async {}
}

class MockContactRepository implements ContactRepository {
  List<Contact> mockContacts = [];
  Contact? mockContact;

  @override
  Future<List<Contact>> getContacts({
    int? libraryId,
    String? type,
    String? bookIsbn,
  }) async => mockContacts;

  @override
  Future<Contact> getContact(String uuid, {int? localId}) async =>
      mockContact ?? (throw Exception('Contact not found'));

  @override
  Future<Contact> getContactByLocalId(int localId) async =>
      mockContact ?? (throw Exception('Contact not found'));

  @override
  Future<Contact> createContact(Map<String, dynamic> contactData) async =>
      mockContact ??
      Contact(
        localId: 1,
        type: contactData['type'] ?? 'borrower',
        name: contactData['name'] ?? 'Test',
        libraryOwnerId: 1,
      );

  @override
  Future<Contact> updateContact(
    int localId,
    Map<String, dynamic> contactData,
  ) async =>
      mockContact ??
      Contact(
        localId: localId,
        type: contactData['type'] ?? 'borrower',
        name: contactData['name'] ?? 'Updated',
        libraryOwnerId: 1,
      );

  @override
  Future<void> deleteContact(String uuid, {int? localId}) async {}
}

class MockCollectionRepository implements CollectionRepository {
  List<Collection> mockCollections = [];
  List<CollectionBook> mockCollectionBooks = [];

  @override
  Future<List<Collection>> getCollections() async => mockCollections;

  @override
  Future<List<Collection>> getBookCollections(int bookId) async =>
      mockCollections;

  @override
  Future<void> updateBookCollections(
    int bookId,
    List<String> collectionIds,
  ) async {}

  @override
  Future<Collection> createCollection(
    String name, {
    String? description,
  }) async => Collection(
    id: '1',
    name: name,
    description: description,
    source: 'manual',
    createdAt: DateTime.now().toIso8601String(),
    updatedAt: DateTime.now().toIso8601String(),
  );

  @override
  Future<void> deleteCollection(String id) async {}

  @override
  Future<List<int>> deleteCollectionWithBooks(String id) async => const [];

  @override
  Future<CollectionDeletionPreview> getDeletionPreview(String id) async =>
      const CollectionDeletionPreview(totalBooks: 0, toDelete: 0, toKeep: 0);

  @override
  Future<List<CollectionBook>> getCollectionBooks(String id) async =>
      mockCollectionBooks;

  @override
  Future<void> addBookToCollection(String collectionId, int bookId) async {}

  @override
  Future<void> removeBookFromCollection(
    String collectionId,
    int bookId,
  ) async {}
}

class MockCopyRepository implements CopyRepository {
  List<Copy> mockCopies = [];
  Copy? mockCopy;
  final List<Map<String, dynamic>> createdCopies = [];

  @override
  Future<List<Copy>> getBookCopies(int bookId) async => mockCopies;

  @override
  Future<Copy> getCopy(int copyId) async =>
      mockCopy ?? (throw Exception('Copy not found'));

  @override
  Future<Copy> createCopy(Map<String, dynamic> copyData) async {
    createdCopies.add(Map<String, dynamic>.from(copyData));
    return mockCopy ??
        Copy(
          id: 1,
          bookId: copyData['book_id'] as int,
          libraryId: copyData['library_id'] as int? ?? 1,
        );
  }

  @override
  Future<Copy> updateCopy(int copyId, Map<String, dynamic> data) async =>
      mockCopy ?? Copy(id: copyId, bookId: 1, libraryId: 1);

  @override
  Future<void> deleteCopy(int copyId) async {}
}

class MockLoanRepository implements LoanRepository {
  List<Loan> mockLoans = [];
  List<Copy> mockBorrowedCopies = [];

  @override
  Future<List<Loan>> getLoans({String? status, int? contactId}) async =>
      mockLoans;

  @override
  Future<Loan> createLoan(Map<String, dynamic> loanData) async => Loan(
    localId: 1,
    copyId: loanData['copy_id'] as int,
    contactId: loanData['contact_id'] as int,
    libraryId: loanData['library_id'] as int? ?? 1,
    loanDate: loanData['loan_date'] as String,
    dueDate: loanData['due_date'] as String,
    status: 'active',
    contactName: '',
    bookTitle: '',
  );

  @override
  Future<void> returnLoan(String uuid) async {}

  @override
  Future<List<Copy>> getBorrowedCopies() async => mockBorrowedCopies;
}
