import '../../models/collection.dart';
import '../../models/collection_book.dart';
import '../../models/collection_deletion_preview.dart';

abstract class CollectionRepository {
  Future<List<Collection>> getCollections();

  Future<List<Collection>> getBookCollections(String bookId);

  Future<void> updateBookCollections(String bookId, List<String> collectionIds);

  Future<Collection> createCollection(String name, {String? description});

  /// Delete the collection only. Books are left orphaned in the library.
  Future<void> deleteCollection(String id);

  /// Delete the collection along with eligible books (no loaned/borrowed
  /// copy, not in another collection, on no shelf). Returns the IDs of
  /// books that were actually removed.
  Future<List<String>> deleteCollectionWithBooks(String id);

  /// Counts shown in the confirmation dialog before deleting with books.
  Future<CollectionDeletionPreview> getDeletionPreview(String id);

  Future<List<CollectionBook>> getCollectionBooks(String id);

  Future<void> addBookToCollection(String collectionId, String bookId);

  Future<void> removeBookFromCollection(String collectionId, String bookId);
}
