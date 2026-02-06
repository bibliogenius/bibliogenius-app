import '../../models/collection.dart';
import '../../models/collection_book.dart';

abstract class CollectionRepository {
  Future<List<Collection>> getCollections();

  Future<List<Collection>> getBookCollections(int bookId);

  Future<void> updateBookCollections(int bookId, List<String> collectionIds);

  Future<Collection> createCollection(String name, {String? description});

  Future<void> deleteCollection(String id);

  Future<List<CollectionBook>> getCollectionBooks(String id);

  Future<void> addBookToCollection(String collectionId, int bookId);

  Future<void> removeBookFromCollection(String collectionId, int bookId);
}
