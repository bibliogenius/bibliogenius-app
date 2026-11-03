import 'dart:async';

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
  Future<Book> getBook(String uuid) async =>
      mockBook ?? (throw Exception('Book not found'));

  /// The payload of the last `createBook` call.
  Map<String, dynamic>? lastCreate;

  @override
  Future<Book> createBook(Map<String, dynamic> bookData) async {
    calls.add('createBook:${bookData['isbn']}');
    lastCreate = bookData;
    return mockBook ?? Book(id: '1', title: bookData['title'] ?? 'Test');
  }

  /// The payload of the last `updateBook` call, so a test can assert on what
  /// a screen actually sends (and not only that it saved).
  Map<String, dynamic>? lastUpdate;

  @override
  Future<Book> updateBook(String uuid, Map<String, dynamic> bookData) async {
    lastUpdate = bookData;
    return mockBook ?? Book(id: uuid, title: bookData['title'] ?? 'Updated');
  }

  @override
  Future<void> deleteBook(String uuid) async {}

  /// The ids of the last `reorderBooks` call, in the order sent.
  List<String>? lastReorder;

  @override
  Future<void> reorderBooks(List<String> bookIds) async {
    lastReorder = bookIds;
  }

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
  int mockUnshelvedCount = 0;

  /// When set, the next listing waits on it instead of answering at once:
  /// a slow listing that lands after a later one.
  Completer<List<Tag>>? holdNextGetTags;

  @override
  Future<List<Tag>> getTags() async {
    final held = holdNextGetTags;
    if (held == null) return mockTags;
    holdNextGetTags = null;
    return held.future;
  }

  @override
  Future<int> countUnshelvedBooks() async => mockUnshelvedCount;

  /// Every shelf created, as `name` or `name < parentId`, in order. The
  /// created shelf is not added to [mockTags], which tests often share.
  final List<String> created = [];

  /// Thrown by [createTag] when set, as the core does for a name taken.
  Object? mockCreateError;

  @override
  Future<Tag> createTag(String name, {String? parentId}) async {
    if (mockCreateError != null) throw mockCreateError!;
    created.add(parentId == null ? name : '$name < $parentId');
    return Tag(id: '1', name: name, parentId: parentId, count: 0);
  }

  /// Every shelf update, as `uuid: name` (first level) or
  /// `uuid: name < parentId`, in order. [mockTags] is left as it was.
  final List<String> updated = [];

  @override
  Future<Tag> updateTag(String uuid, String name, {String? parentId}) async {
    updated.add(parentId == null ? '$uuid: $name' : '$uuid: $name < $parentId');
    return Tag(id: uuid, name: name, parentId: parentId, count: 0);
  }

  @override
  Future<void> deleteTag(String uuid) async {}

  /// Every shelf deleted, by name, in order. The shelf also leaves
  /// [mockTags], replaced rather than changed in place.
  final List<String> deleted = [];

  /// The name of a shelf whose deletion the core refuses, after
  /// [mockDeleteDelay].
  String? mockDeleteFailsFor;
  Duration mockDeleteDelay = Duration.zero;

  @override
  Future<void> deleteShelf(Tag tag) async {
    if (tag.name == mockDeleteFailsFor) {
      await Future<void>.delayed(mockDeleteDelay);
      throw Exception('core refused');
    }
    deleted.add(tag.name);
    mockTags = [
      for (final t in mockTags)
        if (t.id != tag.id) t,
    ];
  }
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
  Future<Contact> getContact(String uuid) async =>
      mockContact ?? (throw Exception('Contact not found'));

  @override
  Future<Contact> createContact(Map<String, dynamic> contactData) async =>
      mockContact ??
      Contact(
        id: '1',
        type: contactData['type'] ?? 'borrower',
        name: contactData['name'] ?? 'Test',
        libraryOwnerId: 1,
      );

  @override
  Future<Contact> updateContact(
    String uuid,
    Map<String, dynamic> contactData,
  ) async =>
      mockContact ??
      Contact(
        id: uuid,
        type: contactData['type'] ?? 'borrower',
        name: contactData['name'] ?? 'Updated',
        libraryOwnerId: 1,
      );

  @override
  Future<void> deleteContact(String uuid) async {}
}

class MockCollectionRepository implements CollectionRepository {
  List<Collection> mockCollections = [];
  List<CollectionBook> mockCollectionBooks = [];

  @override
  Future<List<Collection>> getCollections() async => mockCollections;

  @override
  Future<List<Collection>> getBookCollections(String bookId) async =>
      mockCollections;

  @override
  Future<void> updateBookCollections(
    String bookId,
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
  Future<void> renameCollection(String id, String name) async {}

  @override
  Future<void> deleteCollection(String id) async {}

  @override
  Future<List<String>> deleteCollectionWithBooks(String id) async => const [];

  @override
  Future<CollectionDeletionPreview> getDeletionPreview(String id) async =>
      const CollectionDeletionPreview(totalBooks: 0, toDelete: 0, toKeep: 0);

  @override
  Future<List<CollectionBook>> getCollectionBooks(String id) async =>
      mockCollectionBooks;

  @override
  Future<void> addBookToCollection(String collectionId, String bookId) async {}

  @override
  Future<void> removeBookFromCollection(
    String collectionId,
    String bookId,
  ) async {}

  /// The arguments of the last `assignBooks` call, so a test can assert on
  /// what a bulk-filing flow actually sends.
  Map<String, List<String>>? lastAssignment;

  /// What `assignBooks` reports as changed; null means "every book".
  int? mockAssignedCount;

  /// When set, `assignBooks` throws it.
  Object? assignError;

  @override
  Future<int> assignBooks({
    required List<String> bookIds,
    List<String> addShelves = const [],
    List<String> addCollectionIds = const [],
    List<String> removeShelves = const [],
    List<String> removeCollectionIds = const [],
  }) async {
    if (assignError != null) throw assignError!;
    lastAssignment = {
      'bookIds': bookIds,
      'addShelves': addShelves,
      'addCollectionIds': addCollectionIds,
      'removeShelves': removeShelves,
      'removeCollectionIds': removeCollectionIds,
    };
    return mockAssignedCount ?? bookIds.length;
  }

  @override
  Future<void> markCollectionAsSeries(
    String collectionId,
    bool isSeries,
  ) async {}

  @override
  Future<void> setBookVolumeNumber(
    String collectionId,
    String bookId,
    int? volumeNumber,
  ) async {}

  // ── Favorites (ADR-064) ───────────────────────────────────────────

  Set<String> mockFavoriteIds = {};

  @override
  Future<bool> toggleFavoriteBook(String bookId) async {
    if (mockFavoriteIds.contains(bookId)) {
      mockFavoriteIds.remove(bookId);
      return false;
    }
    mockFavoriteIds.add(bookId);
    return true;
  }

  @override
  Future<List<String>> getFavoriteBookIds() async => mockFavoriteIds.toList();

  @override
  Future<bool> seedFavoritesCollection() async => false;

  @override
  Future<Collection?> getFavoritesAdoptionCandidate() async => null;

  @override
  Future<void> adoptFavoritesCollection(String collectionId) async {}
}

class MockCopyRepository implements CopyRepository {
  List<Copy> mockCopies = [];
  Copy? mockCopy;
  final List<Map<String, dynamic>> createdCopies = [];
  final List<String> deletedCopyIds = [];

  @override
  Future<List<Copy>> getBookCopies(String bookId) async => mockCopies;

  @override
  Future<Copy> getCopy(String copyId) async =>
      mockCopy ?? (throw Exception('Copy not found'));

  @override
  Future<Copy> createCopy(Map<String, dynamic> copyData) async {
    createdCopies.add(Map<String, dynamic>.from(copyData));
    return mockCopy ??
        Copy(
          id: '1',
          bookId: copyData['book_id'].toString(),
          libraryId: copyData['library_id'] as int? ?? 1,
        );
  }

  @override
  Future<Copy> updateCopy(String copyId, Map<String, dynamic> data) async =>
      mockCopy ?? Copy(id: copyId, bookId: '1', libraryId: 1);

  @override
  Future<void> deleteCopy(String copyId) async => deletedCopyIds.add(copyId);
}

class MockLoanRepository implements LoanRepository {
  List<Loan> mockLoans = [];
  List<Copy> mockBorrowedCopies = [];

  @override
  Future<List<Loan>> getLoans({String? status, int? contactId}) async =>
      mockLoans;

  @override
  Future<Loan> createLoan(Map<String, dynamic> loanData) async => Loan(
    id: '1',
    copyId: loanData['copy_id'].toString(),
    contactId: loanData['contact_id'].toString(),
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
