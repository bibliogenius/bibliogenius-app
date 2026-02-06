import '../../models/book.dart';

abstract class BookRepository {
  Future<List<Book>> getBooks({
    String? status,
    String? author,
    String? title,
    String? tag,
  });

  Future<Book> getBook(int id);

  Future<Book> createBook(Map<String, dynamic> bookData);

  Future<Book> updateBook(int id, Map<String, dynamic> bookData);

  Future<void> deleteBook(int id);

  Future<void> reorderBooks(List<int> bookIds);

  Future<Book?> findBookByIsbn(String isbn);

  Future<List<String>> getAllAuthors();
}
