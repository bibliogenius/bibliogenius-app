import '../../models/book.dart';
import '../../services/api_service.dart';
import '../repositories/book_repository.dart';

class BookRepositoryImpl implements BookRepository {
  final ApiService _apiService;

  BookRepositoryImpl(this._apiService);

  @override
  Future<List<Book>> getBooks({
    String? status,
    String? author,
    String? title,
    String? tag,
  }) {
    return _apiService.getBooks(
      status: status,
      author: author,
      title: title,
      tag: tag,
    );
  }

  @override
  Future<Book> getBook(String uuid) {
    return _apiService.getBook(uuid);
  }

  @override
  Future<Book> createBook(Map<String, dynamic> bookData) async {
    final response = await _apiService.createBook(bookData);
    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = response.data;
      if (data is Map<String, dynamic>) {
        // FFI returns partial data {id, uuid, title}, HTTP returns full book
        if (data.containsKey('title')) {
          return Book.fromJson(data);
        }
        // Minimal response — fetch the full book by its uuid identity
        if (data['uuid'] != null) {
          return _apiService.getBook(data['uuid'] as String);
        }
      }
    }
    throw Exception('Failed to create book (status: ${response.statusCode})');
  }

  @override
  Future<Book> updateBook(String uuid, Map<String, dynamic> bookData) async {
    final response = await _apiService.updateBook(uuid, bookData);
    if (response.statusCode == 200) {
      final data = response.data;
      if (data is Map<String, dynamic> && data.containsKey('title')) {
        return Book.fromJson(data);
      }
      // Response may not contain the full book — re-fetch
      return _apiService.getBook(uuid);
    }
    throw Exception('Failed to update book (status: ${response.statusCode})');
  }

  @override
  Future<void> deleteBook(String uuid) async {
    final response = await _apiService.deleteBook(uuid);
    if (response.statusCode != 200) {
      throw Exception('Failed to delete book (status: ${response.statusCode})');
    }
  }

  @override
  Future<void> reorderBooks(List<String> bookIds) {
    return _apiService.reorderBooks(bookIds);
  }

  @override
  Future<Book?> findBookByIsbn(String isbn) {
    return _apiService.findBookByIsbn(isbn);
  }

  @override
  Future<List<String>> getAllAuthors() {
    return _apiService.getAllAuthors();
  }
}
