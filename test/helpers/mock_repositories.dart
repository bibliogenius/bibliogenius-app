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
import 'package:bibliogenius/models/copy.dart';
import 'package:bibliogenius/models/loan.dart';

class MockBookRepository implements BookRepository {
  List<Book> mockBooks = [];
  Book? mockBook;

  @override
  Future<List<Book>> getBooks({
    String? status,
    String? author,
    String? title,
    String? tag,
  }) async => mockBooks;

  @override
  Future<Book> getBook(int id) async =>
      mockBook ?? (throw Exception('Book not found'));

  @override
  Future<Book> createBook(Map<String, dynamic> bookData) async =>
      mockBook ??
      Book(id: 1, title: bookData['title'] ?? 'Test');

  @override
  Future<Book> updateBook(int id, Map<String, dynamic> bookData) async =>
      mockBook ??
      Book(id: id, title: bookData['title'] ?? 'Updated');

  @override
  Future<void> deleteBook(int id) async {}

  @override
  Future<void> reorderBooks(List<int> bookIds) async {}

  @override
  Future<Book?> findBookByIsbn(String isbn) async => mockBook;

  @override
  Future<List<String>> getAllAuthors() async =>
      mockBooks
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
  Future<Tag> updateTag(int id, String name, {int? parentId}) async =>
      Tag(id: id, name: name, parentId: parentId, count: 0);

  @override
  Future<void> deleteTag(int id) async {}
}

class MockContactRepository implements ContactRepository {
  List<Contact> mockContacts = [];
  Contact? mockContact;

  @override
  Future<List<Contact>> getContacts({int? libraryId, String? type}) async =>
      mockContacts;

  @override
  Future<Contact> getContact(int id) async =>
      mockContact ?? (throw Exception('Contact not found'));

  @override
  Future<Contact> createContact(Map<String, dynamic> contactData) async =>
      mockContact ??
      Contact(
        id: 1,
        type: contactData['type'] ?? 'borrower',
        name: contactData['name'] ?? 'Test',
        libraryOwnerId: 1,
      );

  @override
  Future<Contact> updateContact(
    int id,
    Map<String, dynamic> contactData,
  ) async =>
      mockContact ??
      Contact(
        id: id,
        type: contactData['type'] ?? 'borrower',
        name: contactData['name'] ?? 'Updated',
        libraryOwnerId: 1,
      );

  @override
  Future<void> deleteContact(int id) async {}
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
  }) async =>
      Collection(
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

  @override
  Future<List<Copy>> getBookCopies(int bookId) async => mockCopies;

  @override
  Future<Copy> getCopy(int copyId) async =>
      mockCopy ?? (throw Exception('Copy not found'));

  @override
  Future<Copy> createCopy(Map<String, dynamic> copyData) async =>
      mockCopy ??
      Copy(
        id: 1,
        bookId: copyData['book_id'] as int,
        libraryId: copyData['library_id'] as int? ?? 1,
      );

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
    id: 1,
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
  Future<void> returnLoan(int loanId) async {}

  @override
  Future<List<Copy>> getBorrowedCopies() async => mockBorrowedCopies;
}
