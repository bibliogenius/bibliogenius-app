import '../../models/book.dart';

abstract class BookRepository {
  Future<List<Book>> getBooks({
    String? status,
    String? author,
    String? title,
    String? tag,
  });

  /// Fetch a book by its uuid (cross-device identity). [localId] feeds the
  /// dormant web HTTP leg only.
  Future<Book> getBook(String uuid, {int? localId});

  /// Fetch a book by its transitional integer local id. Bridges callers
  /// (loans, statistics, peers) that do not yet carry the uuid.
  Future<Book> getBookByLocalId(int localId);

  Future<Book> createBook(Map<String, dynamic> bookData);

  /// Update a book by its uuid (cross-device identity). [localId] feeds the
  /// dormant web HTTP leg only.
  Future<Book> updateBook(
    String uuid,
    Map<String, dynamic> bookData, {
    int? localId,
  });

  /// Delete a book by its uuid (cross-device identity). [localId] feeds the
  /// dormant web HTTP leg only.
  Future<void> deleteBook(String uuid, {int? localId});

  Future<void> reorderBooks(List<int> bookIds);

  Future<Book?> findBookByIsbn(String isbn);

  Future<List<String>> getAllAuthors();
}
