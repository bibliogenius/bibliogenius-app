import '../../models/collection.dart';
import '../../models/collection_book.dart';
import '../../models/collection_deletion_preview.dart';
import '../../services/ffi_service.dart';
import '../repositories/collection_repository.dart';

class CollectionRepositoryImpl implements CollectionRepository {
  final FfiService _ffi;

  CollectionRepositoryImpl(this._ffi);

  @override
  Future<List<Collection>> getCollections() => _ffi.getCollections();

  @override
  Future<List<Collection>> getBookCollections(int bookId) =>
      _ffi.getBookCollections(bookId);

  @override
  Future<void> updateBookCollections(
    int bookId,
    List<String> collectionIds,
  ) =>
      _ffi.updateBookCollections(bookId, collectionIds);

  @override
  Future<Collection> createCollection(
    String name, {
    String? description,
  }) =>
      _ffi.createCollection(name, description: description);

  @override
  Future<void> deleteCollection(String id) => _ffi.deleteCollection(id);

  @override
  Future<List<int>> deleteCollectionWithBooks(String id) =>
      _ffi.deleteCollectionWithBooks(id);

  @override
  Future<CollectionDeletionPreview> getDeletionPreview(String id) =>
      _ffi.getCollectionDeletionPreview(id);

  @override
  Future<List<CollectionBook>> getCollectionBooks(String id) =>
      _ffi.getCollectionBooks(id);

  @override
  Future<void> addBookToCollection(String collectionId, int bookId) =>
      _ffi.addBookToCollection(collectionId, bookId);

  @override
  Future<void> removeBookFromCollection(String collectionId, int bookId) =>
      _ffi.removeBookFromCollection(collectionId, bookId);
}
