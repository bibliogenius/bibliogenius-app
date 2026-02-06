import '../../models/collection.dart';
import '../../models/collection_book.dart';
import '../../services/api_service.dart';
import '../repositories/collection_repository.dart';

class CollectionRepositoryImpl implements CollectionRepository {
  final ApiService _apiService;

  CollectionRepositoryImpl(this._apiService);

  @override
  Future<List<Collection>> getCollections() {
    return _apiService.getCollections();
  }

  @override
  Future<List<Collection>> getBookCollections(int bookId) {
    return _apiService.getBookCollections(bookId);
  }

  @override
  Future<void> updateBookCollections(int bookId, List<String> collectionIds) {
    return _apiService.updateBookCollections(bookId, collectionIds);
  }

  @override
  Future<Collection> createCollection(String name, {String? description}) {
    return _apiService.createCollection(name, description: description);
  }

  @override
  Future<void> deleteCollection(String id) {
    return _apiService.deleteCollection(id);
  }

  @override
  Future<List<CollectionBook>> getCollectionBooks(String id) async {
    final rawList = await _apiService.getCollectionBooks(id);
    return rawList
        .map(
          (json) => CollectionBook.fromJson(json as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<void> addBookToCollection(String collectionId, int bookId) {
    return _apiService.addBookToCollection(collectionId, bookId);
  }

  @override
  Future<void> removeBookFromCollection(String collectionId, int bookId) {
    return _apiService.removeBookFromCollection(collectionId, bookId);
  }
}
