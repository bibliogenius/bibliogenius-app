import '../../models/collection.dart';
import '../../models/collection_book.dart';
import '../../models/collection_deletion_preview.dart';

abstract class CollectionRepository {
  Future<List<Collection>> getCollections();

  Future<List<Collection>> getBookCollections(int bookId);

  Future<void> updateBookCollections(int bookId, List<String> collectionIds);

  Future<Collection> createCollection(String name, {String? description});

  /// Delete the collection only. Books are left orphaned in the library.
  Future<void> deleteCollection(String id);

  /// Delete the collection along with eligible books (no loaned/borrowed
  /// copy, not in another collection, on no shelf). Returns the IDs of
  /// books that were actually removed.
  Future<List<int>> deleteCollectionWithBooks(String id);

  /// Counts shown in the confirmation dialog before deleting with books.
  Future<CollectionDeletionPreview> getDeletionPreview(String id);

  Future<List<CollectionBook>> getCollectionBooks(String id);

  Future<void> addBookToCollection(String collectionId, int bookId);

  Future<void> removeBookFromCollection(String collectionId, int bookId);
}
