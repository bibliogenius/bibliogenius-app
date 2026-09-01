import '../../models/collection.dart';
import '../../models/collection_book.dart';
import '../../models/collection_deletion_preview.dart';

abstract class CollectionRepository {
  Future<List<Collection>> getCollections();

  Future<List<Collection>> getBookCollections(String bookId);

  Future<void> updateBookCollections(String bookId, List<String> collectionIds);

  Future<Collection> createCollection(String name, {String? description});

  /// Rename a collection.
  ///
  /// Refused on the typed favorites collection, whose label comes from the
  /// translations and not from the stored name (ADR-064): call sites hide
  /// the action rather than letting it fail.
  Future<void> renameCollection(String id, String name);

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

  /// Mark a collection as a series (ordered reading list) or revert it to a
  /// plain manual collection.
  Future<void> markCollectionAsSeries(String collectionId, bool isSeries);

  /// Set (or clear, with `null`) a book's reading-order position within a
  /// collection.
  Future<void> setBookVolumeNumber(
    String collectionId,
    String bookId,
    int? volumeNumber,
  );

  // ── Favorites (ADR-064) ───────────────────────────────────────────

  /// Toggle a book's favorite state (membership in the typed favorites
  /// collection). Returns the NEW state; creates the collection lazily.
  Future<bool> toggleFavoriteBook(String bookId);

  /// All favorite book ids in one pass (cached by FavoritesProvider).
  Future<List<String>> getFavoriteBookIds();

  /// Seed the empty favorites collection at Reader-preset selection; the
  /// eligibility gate lives Rust-side. Returns whether it was created.
  Future<bool> seedFavoritesCollection();

  /// The manual collection to propose for one-shot favorites adoption, or
  /// null when none qualifies (or a typed collection already exists).
  Future<Collection?> getFavoritesAdoptionCandidate();

  /// Adopt a manual collection as THE favorites collection (source flip,
  /// name and members kept).
  Future<void> adoptFavoritesCollection(String collectionId);
}
