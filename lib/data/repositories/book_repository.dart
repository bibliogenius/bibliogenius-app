import '../../models/book.dart';

abstract class BookRepository {
  Future<List<Book>> getBooks({
    String? status,
    String? author,
    String? title,
    String? tag,
  });

  /// Fetch a book by its uuid (cross-device identity).
  Future<Book> getBook(String uuid);

  Future<Book> createBook(Map<String, dynamic> bookData);

  /// Update a book by its uuid (cross-device identity).
  Future<Book> updateBook(String uuid, Map<String, dynamic> bookData);

  /// Delete a book by its uuid (cross-device identity).
  Future<void> deleteBook(String uuid);

  Future<void> reorderBooks(List<String> bookIds);

  Future<Book?> findBookByIsbn(String isbn);

  Future<List<String>> getAllAuthors();
}
