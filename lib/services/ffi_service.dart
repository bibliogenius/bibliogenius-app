// FFI Service - Wrapper for Rust FFI calls
// This service provides a clean interface to the Rust backend via FFI
// Used on native platforms (iOS, Android, macOS, Windows, Linux)

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart' show Int64List;
import '../models/book.dart';
import '../models/collection.dart';
import '../models/collection_book.dart';
import '../models/contact.dart';
import '../models/cover_candidate.dart';
import '../models/tag.dart';
import '../src/rust/api/frb.dart' as frb;
import 'dart:convert';

/// Service that wraps the FFI calls to the Rust backend
/// This is used on native platforms instead of HTTP
class FfiService {
  static final FfiService _instance = FfiService._internal();
  factory FfiService() => _instance;
  FfiService._internal();

  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// Mark as initialized after RustLib.init() and initBackend() succeed
  void markInitialized() {
    _isInitialized = true;
  }

  /// Health check
  String healthCheck() {
    try {
      return frb.healthCheck();
    } catch (e) {
      debugPrint('FFI healthCheck error: $e');
      return 'ERROR';
    }
  }

  /// Get version
  String getVersion() {
    try {
      return frb.getVersion();
    } catch (e) {
      debugPrint('FFI getVersion error: $e');
      return 'unknown';
    }
  }

  // ============ Library Name ============

  /// Update the library name directly in the Rust DB (library_config + libraries).
  /// Only touches the name field - no other settings are overwritten.
  Future<void> updateLibraryName(String name) async {
    try {
      await frb.updateLibraryNameFfi(name: name);
    } catch (e) {
      debugPrint('FFI updateLibraryName error: $e');
      rethrow;
    }
  }

  // ============ Books ============

  /// Get all books with optional filters
  Future<List<Book>> getBooks({
    String? status,
    String? title,
    String? tag,
  }) async {
    try {
      final frbBooks = await frb.getAllBooks(
        status: status,
        title: title,
        tag: tag,
      );
      return frbBooks.map(_frbBookToBook).toList();
    } catch (e) {
      debugPrint('FFI getBooks error: $e');
      rethrow;
    }
  }

  /// Get a single book by ID
  Future<Book> getBook(int id) async {
    try {
      final frbBook = await frb.getBookById(id: id);
      return _frbBookToBook(frbBook);
    } catch (e) {
      debugPrint('FFI getBook error: $e');
      rethrow;
    }
  }

  /// Count total books
  Future<int> countBooks() async {
    try {
      final count = await frb.countBooks();
      return count.toInt();
    } catch (e) {
      debugPrint('FFI countBooks error: $e');
      return 0;
    }
  }

  /// Get all tags with counts
  Future<List<Tag>> getTags() async {
    try {
      final frbTags = await frb.getAllTags();

      // Convert FrbTag to Tag model
      // Note: FrbTag now includes parentId directly from Rust
      return frbTags
          .map(
            (t) => Tag(
              id: t.id,
              name: t.name,
              parentId: t.parentId,
              count: t.count.toInt(),
              // Children will be built by the UI tree builder or we could do it here
              // The TagTreeView expects a flat list and builds hierarchy itself via `_buildTree`
              // or assumes we pass a list of tags. The `Tag` model has `copyWithChildren`.
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('FFI getTags error: $e');
      return [];
    }
  }

  /// Create a new tag
  Future<Tag> createTag(String name, {int? parentId}) async {
    try {
      final t = await frb.createTag(name: name, parentId: parentId);
      return Tag(
        id: t.id,
        name: t.name,
        parentId: t.parentId,
        count: t.count.toInt(),
      );
    } catch (e) {
      debugPrint('FFI createTag error: $e');
      rethrow;
    }
  }

  /// Update a tag
  Future<Tag> updateTag(int id, String name, {int? parentId}) async {
    try {
      final t = await frb.updateTag(id: id, name: name, parentId: parentId);
      return Tag(
        id: t.id,
        name: t.name,
        parentId: t.parentId,
        count: t.count.toInt(),
      );
    } catch (e) {
      debugPrint('FFI updateTag error: $e');
      rethrow;
    }
  }

  /// Delete a tag
  Future<void> deleteTag(int id) async {
    try {
      await frb.deleteTag(id: id);
    } catch (e) {
      debugPrint('FFI deleteTag error: $e');
      rethrow;
    }
  }

  /// Reorder books by updating shelf positions
  Future<void> reorderBooks(List<int> bookIds) async {
    try {
      await frb.reorderBooks(bookIds: bookIds);
    } catch (e) {
      debugPrint('FFI reorderBooks error: $e');
      rethrow;
    }
  }

  // ============ Contacts ============

  /// Get all contacts with optional filters
  Future<List<Contact>> getContacts({int? libraryId, String? type}) async {
    try {
      final frbContacts = await frb.getAllContacts(
        libraryId: libraryId,
        contactType: type,
      );
      return frbContacts.map(_frbContactToContact).toList();
    } catch (e) {
      debugPrint('FFI getContacts error: $e');
      rethrow;
    }
  }

  /// Get a single contact by ID
  Future<Contact> getContact(int id) async {
    try {
      final frbContact = await frb.getContactById(id: id);
      return _frbContactToContact(frbContact);
    } catch (e) {
      debugPrint('FFI getContact error: $e');
      rethrow;
    }
  }

  /// Count total contacts
  Future<int> countContacts() async {
    try {
      final count = await frb.countContacts();
      return count.toInt();
    } catch (e) {
      debugPrint('FFI countContacts error: $e');
      return 0;
    }
  }

  /// Create a new contact
  Future<Contact> createContact(Contact contact) async {
    try {
      final frbContact = frb.FrbContact(
        id: contact.id,
        contactType: contact.type,
        name: contact.name,
        firstName: contact.firstName,
        email: contact.email,
        phone: contact.phone,
        address: contact.address,
        streetAddress: contact.streetAddress,
        postalCode: contact.postalCode,
        city: contact.city,
        country: contact.country,
        latitude: contact.latitude,
        longitude: contact.longitude,
        notes: contact.notes,
        userId: contact.userId,
        libraryOwnerId: contact.libraryOwnerId,
        isActive: contact.isActive,
      );

      final created = await frb.createContact(contact: frbContact);
      return _frbContactToContact(created);
    } catch (e) {
      debugPrint('FFI createContact error: $e');
      rethrow;
    }
  }

  /// Update an existing contact
  Future<Contact> updateContact(Contact contact) async {
    try {
      final frbContact = frb.FrbContact(
        id: contact.id,
        contactType: contact.type,
        name: contact.name,
        firstName: contact.firstName,
        email: contact.email,
        phone: contact.phone,
        address: contact.address,
        streetAddress: contact.streetAddress,
        postalCode: contact.postalCode,
        city: contact.city,
        country: contact.country,
        latitude: contact.latitude,
        longitude: contact.longitude,
        notes: contact.notes,
        userId: contact.userId,
        libraryOwnerId: contact.libraryOwnerId,
        isActive: contact.isActive,
      );

      final updated = await frb.updateContact(contact: frbContact);
      return _frbContactToContact(updated);
    } catch (e) {
      debugPrint('FFI updateContact error: $e');
      rethrow;
    }
  }

  /// Delete a contact
  Future<void> deleteContact(int id) async {
    try {
      await frb.deleteContact(id: id);
    } catch (e) {
      debugPrint('FFI deleteContact error: $e');
      rethrow;
    }
  }

  // ============ Loans ============

  /// Get all loans
  Future<List<frb.FrbLoan>> getAllLoans() async {
    try {
      return await frb.getAllLoans();
    } catch (e) {
      debugPrint('FFI getAllLoans error: $e');
      return [];
    }
  }

  /// Count active loans
  Future<int> countActiveLoans() async {
    try {
      final count = await frb.countActiveLoans();
      return count.toInt();
    } catch (e) {
      debugPrint('FFI countActiveLoans error: $e');
      return 0;
    }
  }

  /// Count returned loans (for cleanup confirmation)
  Future<int> countReturnedLoans() async {
    try {
      final count = await frb.countReturnedLoans();
      return count.toInt();
    } catch (e) {
      debugPrint('FFI countReturnedLoans error: $e');
      return 0;
    }
  }

  /// Delete all returned loans, returns the number deleted
  Future<int> deleteReturnedLoans() async {
    try {
      final count = await frb.deleteReturnedLoans();
      return count.toInt();
    } catch (e) {
      debugPrint('FFI deleteReturnedLoans error: $e');
      rethrow;
    }
  }

  // ============ P2P Request Cleanup ============

  /// Count closed incoming requests (not pending)
  Future<int> countClosedIncomingRequests() async {
    try {
      final count = await frb.countClosedIncomingRequests();
      return count.toInt();
    } catch (e) {
      debugPrint('FFI countClosedIncomingRequests error: $e');
      return 0;
    }
  }

  /// Delete all closed incoming requests, returns the number deleted
  Future<int> deleteClosedIncomingRequests() async {
    try {
      final count = await frb.deleteClosedIncomingRequests();
      return count.toInt();
    } catch (e) {
      debugPrint('FFI deleteClosedIncomingRequests error: $e');
      rethrow;
    }
  }

  /// Count closed outgoing requests (not pending)
  Future<int> countClosedOutgoingRequests() async {
    try {
      final count = await frb.countClosedOutgoingRequests();
      return count.toInt();
    } catch (e) {
      debugPrint('FFI countClosedOutgoingRequests error: $e');
      return 0;
    }
  }

  /// Delete all closed outgoing requests, returns the number deleted
  Future<int> deleteClosedOutgoingRequests() async {
    try {
      final count = await frb.deleteClosedOutgoingRequests();
      return count.toInt();
    } catch (e) {
      debugPrint('FFI deleteClosedOutgoingRequests error: $e');
      rethrow;
    }
  }

  /// Return a loan
  Future<void> returnLoan(int id) async {
    try {
      await frb.returnLoan(id: id);
    } catch (e) {
      debugPrint('FFI returnLoan error: $e');
      rethrow;
    }
  }

  // ============ E2EE Identity ============

  /// Get the node's E2EE public keys as JSON string, or null if not initialized.
  Future<String?> getPublicKeys() async {
    try {
      return await frb.getPublicKeysFfi();
    } catch (e) {
      debugPrint('FFI getPublicKeys error: $e');
      return null;
    }
  }

  // ============ Books Write Operations ============

  Future<frb.FrbBook> createBook(frb.FrbBook book) async {
    try {
      return await frb.createBook(book: book);
    } catch (e) {
      debugPrint('FFI createBook error: $e');
      rethrow;
    }
  }

  Future<frb.FrbBook> updateBook(int id, frb.FrbBook book) async {
    try {
      return await frb.updateBook(id: id, book: book);
    } catch (e) {
      debugPrint('FFI updateBook error: $e');
      rethrow;
    }
  }

  Future<void> deleteBook(int id) async {
    try {
      await frb.deleteBook(id: id);
    } catch (e) {
      debugPrint('FFI deleteBook error: $e');
      rethrow;
    }
  }

  // ============ Cover Enrichment ============

  Future<int> enrichMissingCovers() async {
    try {
      return await frb.enrichMissingCovers();
    } catch (e) {
      debugPrint('FFI enrichMissingCovers error: $e');
      return 0;
    }
  }

  Future<String?> searchCoverForBook(String isbn) async {
    try {
      return await frb.searchCoverForBook(isbn: isbn);
    } catch (e) {
      debugPrint('FFI searchCoverForBook error: $e');
      return null;
    }
  }

  Future<String?> searchCoverByTitle(String title, String? author, {bool enableGoogle = false}) async {
    try {
      debugPrint('FFI searchCoverByTitle: title="$title", author="$author", enableGoogle=$enableGoogle');
      final result = await frb.searchCoverByTitle(title: title, author: author, enableGoogle: enableGoogle);
      debugPrint('FFI searchCoverByTitle: result=$result');
      return result;
    } catch (e) {
      debugPrint('FFI searchCoverByTitle error: $e');
      return null;
    }
  }

  // ============ Multi-Cover Search ============

  /// Search ALL enabled cover sources in parallel for a given ISBN.
  /// Returns all found cover candidates for the picker carousel.
  Future<List<CoverCandidate>> searchAllCoversForBook(String isbn) async {
    try {
      final results = await frb.searchAllCoversForBook(isbn: isbn);
      return results
          .map((r) => CoverCandidate(url: r.url, source: r.source))
          .toList();
    } catch (e) {
      debugPrint('FFI searchAllCoversForBook error: $e');
      return [];
    }
  }

  /// Search ALL enabled sources by title in parallel for the cover picker.
  Future<List<CoverCandidate>> searchAllCoversByTitle(
      String title, String? author,
      {bool enableGoogle = false}) async {
    try {
      final results = await frb.searchAllCoversByTitle(
          title: title, author: author, enableGoogle: enableGoogle);
      return results
          .map((r) => CoverCandidate(url: r.url, source: r.source))
          .toList();
    } catch (e) {
      debugPrint('FFI searchAllCoversByTitle error: $e');
      return [];
    }
  }

  // ============ Metadata Lookup ============

  /// Look up book metadata from external sources by ISBN.
  /// Returns a map of field names to values, or null if not found.
  Future<Map<String, String?>?> lookupBookMetadata(String isbn, {String? lang}) async {
    try {
      final meta = await frb.lookupBookMetadata(isbn: isbn, lang: lang);
      if (meta == null) return null;
      return {
        'title': meta.title,
        'author': meta.author,
        'publisher': meta.publisher,
        'publication_year': meta.publicationYear,
        'cover_url': meta.coverUrl,
        'summary': meta.summary,
      };
    } catch (e) {
      debugPrint('FFI lookupBookMetadata error: $e');
      return null;
    }
  }

  // ============ Converters ============

  /// Convert FrbCollection to Collection model
  Collection _frbCollectionToCollection(frb.FrbCollection fc) {
    return Collection(
      id: fc.id,
      name: fc.name,
      description: fc.description,
      source: fc.source,
      createdAt: fc.createdAt,
      updatedAt: fc.updatedAt,
      totalBooks: fc.totalBooks.toInt(),
      ownedBooks: fc.ownedBooks.toInt(),
    );
  }

  /// Convert FrbCollectionBook to CollectionBook model
  CollectionBook _frbCollectionBookToCollectionBook(
    frb.FrbCollectionBook cb,
  ) {
    return CollectionBook(
      bookId: cb.bookId,
      title: cb.title,
      author: cb.author,
      coverUrl: cb.coverUrl,
      publisher: cb.publisher,
      publicationYear: cb.publicationYear,
      addedAt: DateTime.parse(cb.addedAt),
      isOwned: cb.isOwned,
    );
  }

  /// Convert FrbBook to Book model
  Book _frbBookToBook(frb.FrbBook fb) {
    return Book(
      id: fb.id,
      title: fb.title,
      author: fb.author,
      isbn: fb.isbn,
      summary: fb.summary,
      publisher: fb.publisher,
      publicationYear: fb.publicationYear,
      coverUrl: fb.coverUrl, // largeCoverUrl derived from getter
      readingStatus: fb.readingStatus ?? 'to_read',
      userRating: fb.userRating,
      subjects: fb.subjects != null ? _parseSubjects(fb.subjects!) : null,
      owned: fb.owned,
      price: fb.price,
    );
  }

  /// Convert FrbContact to Contact model
  Contact _frbContactToContact(frb.FrbContact fc) {
    return Contact(
      id: fc.id,
      type: fc.contactType,
      name: fc.name,
      firstName: fc.firstName,
      email: fc.email,
      phone: fc.phone,
      address: fc.address,
      streetAddress: fc.streetAddress,
      postalCode: fc.postalCode,
      city: fc.city,
      country: fc.country,
      latitude: fc.latitude,
      longitude: fc.longitude,
      notes: fc.notes,
      isActive: fc.isActive,
      userId: fc.userId,
      libraryOwnerId: fc.libraryOwnerId ?? 1,
    );
  }

  /// Parse subjects JSON string to list
  List<String>? _parseSubjects(String jsonStr) {
    try {
      if (jsonStr.isEmpty) return null;
      final parsed = jsonDecode(jsonStr);
      if (parsed is List) {
        return parsed.map((e) => e.toString()).toList();
      }
      return null;
    } catch (e) {
      debugPrint('Error parsing subjects JSON: $e');
      return null;
    }
  }

  // ============ Memory Game ============

  /// Get available difficulty levels based on books with covers
  Future<List<String>> getMemoryDifficulties() async {
    try {
      return await frb.memoryGameAvailableDifficulties();
    } catch (e) {
      debugPrint('FFI memoryGameAvailableDifficulties error: $e');
      return [];
    }
  }

  /// Set up a new game: returns shuffled card pairs
  Future<List<frb.FrbMemoryCard>> setupMemoryGame(String difficulty) async {
    try {
      return await frb.memoryGameSetup(difficulty: difficulty);
    } catch (e) {
      debugPrint('FFI memoryGameSetup error: $e');
      rethrow;
    }
  }

  /// Submit a completed game and get the computed score
  Future<frb.FrbMemoryScore> finishMemoryGame({
    required String difficulty,
    required double elapsedSeconds,
    required int errors,
    required int pairsCount,
  }) async {
    try {
      return await frb.memoryGameFinish(
        difficulty: difficulty,
        elapsedSeconds: elapsedSeconds,
        errors: errors,
        pairsCount: pairsCount,
      );
    } catch (e) {
      debugPrint('FFI memoryGameFinish error: $e');
      rethrow;
    }
  }

  /// Get top memory game scores
  Future<List<frb.FrbMemoryScore>> getMemoryTopScores() async {
    try {
      return await frb.memoryGameTopScores();
    } catch (e) {
      debugPrint('FFI memoryGameTopScores error: $e');
      return [];
    }
  }

  /// Get leaderboard (peer scores)
  Future<List<frb.FrbMemoryLeaderboardEntry>> getMemoryLeaderboard() async {
    try {
      return await frb.memoryGameLeaderboard();
    } catch (e) {
      debugPrint('FFI memoryGameLeaderboard error: $e');
      return [];
    }
  }

  /// Refresh network leaderboard: sync with peers then return merged leaderboard
  Future<List<frb.FrbMemoryLeaderboardEntry>>
      refreshMemoryLeaderboard() async {
    try {
      return await frb.memoryGameRefreshLeaderboard();
    } catch (e) {
      debugPrint('FFI memoryGameRefreshLeaderboard error: $e');
      return [];
    }
  }

  // ============ Sliding Puzzle ============

  /// Get available puzzle difficulty levels based on books with covers
  Future<List<String>> getPuzzleDifficulties() async {
    try {
      return await frb.puzzleAvailableDifficulties();
    } catch (e) {
      debugPrint('FFI puzzleAvailableDifficulties error: $e');
      return [];
    }
  }

  /// Set up a new puzzle: returns a board with shuffled tiles
  Future<frb.FrbPuzzleBoard> setupPuzzle(String difficulty) async {
    try {
      return await frb.puzzleSetup(difficulty: difficulty);
    } catch (e) {
      debugPrint('FFI puzzleSetup error: $e');
      rethrow;
    }
  }

  /// Submit a completed puzzle and get the computed score
  Future<frb.FrbPuzzleScore> finishPuzzle({
    required String difficulty,
    required int gridSize,
    required double elapsedSeconds,
    required int moveCount,
    required int parMoves,
  }) async {
    try {
      return await frb.puzzleFinish(
        difficulty: difficulty,
        gridSize: gridSize,
        elapsedSeconds: elapsedSeconds,
        moveCount: moveCount,
        parMoves: parMoves,
      );
    } catch (e) {
      debugPrint('FFI puzzleFinish error: $e');
      rethrow;
    }
  }

  /// Get top sliding puzzle scores
  Future<List<frb.FrbPuzzleScore>> getPuzzleTopScores() async {
    try {
      return await frb.puzzleTopScores();
    } catch (e) {
      debugPrint('FFI puzzleTopScores error: $e');
      return [];
    }
  }

  /// Get puzzle leaderboard (cached peer scores + local best)
  Future<List<frb.FrbPuzzleLeaderboardEntry>> getPuzzleLeaderboard() async {
    try {
      return await frb.puzzleGameLeaderboard();
    } catch (e) {
      debugPrint('FFI puzzleGameLeaderboard error: $e');
      return [];
    }
  }

  /// Refresh puzzle leaderboard: sync with peers then return merged leaderboard
  Future<List<frb.FrbPuzzleLeaderboardEntry>>
      refreshPuzzleLeaderboard() async {
    try {
      return await frb.puzzleGameRefreshLeaderboard();
    } catch (e) {
      debugPrint('FFI puzzleGameRefreshLeaderboard error: $e');
      return [];
    }
  }

  // ============ Gamification (FFI direct) ============

  /// Get full gamification status (tracks, streak, achievements, config)
  Future<frb.FrbGamificationStatus> getGamificationStatus() async {
    return await frb.gamificationGetStatus();
  }

  /// Get gamification leaderboard
  Future<frb.FrbLeaderboardResponse> getGamificationLeaderboard() async {
    return await frb.gamificationGetLeaderboard();
  }

  /// Refresh gamification leaderboard
  Future<frb.FrbLeaderboardResponse> refreshGamificationLeaderboard() async {
    return await frb.gamificationRefreshLeaderboard();
  }

  /// Update gamification config
  Future<void> updateGamificationConfig({
    int? readingGoalYearly,
    String? achievementsStyle,
  }) async {
    await frb.gamificationUpdateConfig(
      readingGoalYearly: readingGoalYearly,
      achievementsStyle: achievementsStyle,
    );
  }

  /// Check and unlock eligible achievements
  Future<List<String>> checkAchievements() async {
    return await frb.gamificationCheckAchievements();
  }

  /// Update daily streak
  Future<frb.FrbStreakInfo> updateStreak() async {
    return await frb.gamificationUpdateStreak();
  }

  // ============ Collections ============

  /// Get all collections with book counts.
  Future<List<Collection>> getCollections() async {
    try {
      final frbList = await frb.getAllCollections();
      return frbList.map(_frbCollectionToCollection).toList();
    } catch (e) {
      debugPrint('FFI getCollections error: $e');
      rethrow;
    }
  }

  /// Get a single collection by ID, or null if not found.
  Future<Collection?> getCollectionById(String id) async {
    try {
      final fc = await frb.getCollection(id: id);
      return fc == null ? null : _frbCollectionToCollection(fc);
    } catch (e) {
      debugPrint('FFI getCollectionById error: $e');
      rethrow;
    }
  }

  /// Create a new collection.
  Future<Collection> createCollection(
    String name, {
    String? description,
  }) async {
    try {
      final fc = await frb.createCollection(
        name: name,
        description: description,
      );
      return _frbCollectionToCollection(fc);
    } catch (e) {
      debugPrint('FFI createCollection error: $e');
      rethrow;
    }
  }

  /// Delete a collection by ID.
  Future<void> deleteCollection(String id) async {
    try {
      await frb.deleteCollection(id: id);
    } catch (e) {
      debugPrint('FFI deleteCollection error: $e');
      rethrow;
    }
  }

  /// Get all books belonging to a collection.
  Future<List<CollectionBook>> getCollectionBooks(String collectionId) async {
    try {
      final frbList = await frb.getCollectionBooks(
        collectionId: collectionId,
      );
      return frbList.map(_frbCollectionBookToCollectionBook).toList();
    } catch (e) {
      debugPrint('FFI getCollectionBooks error: $e');
      rethrow;
    }
  }

  /// Add a book to a collection (idempotent).
  Future<void> addBookToCollection(
    String collectionId,
    int bookId,
  ) async {
    try {
      await frb.addBookToCollection(
        collectionId: collectionId,
        bookId: bookId,
      );
    } catch (e) {
      debugPrint('FFI addBookToCollection error: $e');
      rethrow;
    }
  }

  /// Remove a book from a collection.
  Future<void> removeBookFromCollection(
    String collectionId,
    int bookId,
  ) async {
    try {
      await frb.removeBookFromCollection(
        collectionId: collectionId,
        bookId: bookId,
      );
    } catch (e) {
      debugPrint('FFI removeBookFromCollection error: $e');
      rethrow;
    }
  }

  /// Get all collections a book belongs to.
  Future<List<Collection>> getBookCollections(int bookId) async {
    try {
      final frbList = await frb.getBookCollections(bookId: bookId);
      return frbList.map(_frbCollectionToCollection).toList();
    } catch (e) {
      debugPrint('FFI getBookCollections error: $e');
      rethrow;
    }
  }

  /// Replace the set of collections a book belongs to.
  Future<void> updateBookCollections(
    int bookId,
    List<String> collectionIds,
  ) async {
    try {
      await frb.updateBookCollections(
        bookId: bookId,
        collectionIds: collectionIds,
      );
    } catch (e) {
      debugPrint('FFI updateBookCollections error: $e');
      rethrow;
    }
  }

  // ============ mDNS Local Discovery (Modular) ============

  /// Check if mDNS discovery service is available
  bool isMdnsAvailable() {
    try {
      return frb.isMdnsAvailable();
    } catch (e) {
      debugPrint('FFI isMdnsAvailable error: $e');
      return false;
    }
  }

  /// Get the mDNS service type
  String getMdnsServiceType() {
    try {
      return frb.getMdnsServiceType();
    } catch (e) {
      debugPrint('FFI getMdnsServiceType error: $e');
      return '_bibliogenius._tcp.local.';
    }
  }

  /// Get locally discovered peers via mDNS
  Future<List<Map<String, dynamic>>> getLocalPeers() async {
    try {
      debugPrint('🔍 mDNS: Calling getLocalPeersFfi...');
      final peers = await frb.getLocalPeersFfi();
      debugPrint('🔍 mDNS: Found ${peers.length} peers');
      for (final p in peers) {
        debugPrint(
          '  📚 Peer: ${p.name} at ${p.addresses.firstOrNull}:${p.port}',
        );
      }
      return peers
          .map(
            (p) => {
              'name': p.name,
              'host': p.host,
              'port': p.port,
              'addresses': p.addresses,
              'library_id': p.libraryId,
              'discovered_at': p.discoveredAt,
            },
          )
          .toList();
    } catch (e) {
      debugPrint('FFI getLocalPeers error: $e');
      return [];
    }
  }

  /// Initialize mDNS service for local discovery
  Future<bool> initMdns(
    String libraryName,
    int port, {
    String? libraryId,
  }) async {
    try {
      await frb.initMdnsFfi(
        libraryName: libraryName,
        port: port,
        libraryId: libraryId,
      );
      return true;
    } catch (e) {
      debugPrint('FFI initMdns error: $e');
      return false;
    }
  }

  /// Stop mDNS service
  Future<void> stopMdns() async {
    try {
      await frb.stopMdnsFfi();
    } catch (e) {
      debugPrint('FFI stopMdns error: $e');
    }
  }

  // ============ Hub Directory (FFI direct) ============

  /// Get the local hub directory config, or null if not yet registered.
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async {
    try {
      return await frb.hubDirectoryGetConfig();
    } catch (e) {
      debugPrint('FFI hubDirectoryGetConfig error: $e');
      return null;
    }
  }

  /// Register or update the library profile on the hub directory.
  Future<frb.FrbDirectoryConfig?> hubDirectoryRegister(
    frb.FrbRegisterParams params,
  ) async {
    try {
      return await frb.hubDirectoryRegister(params: params);
    } catch (e) {
      debugPrint('FFI hubDirectoryRegister error: $e');
      return null;
    }
  }

  /// Push the local ISBN catalog to the hub (call after book changes).
  Future<bool> hubDirectoryPushCatalog(List<String> isbnList) async {
    try {
      await frb.hubDirectoryPushCatalog(isbnList: isbnList);
      return true;
    } catch (e) {
      debugPrint('FFI hubDirectoryPushCatalog error: $e');
      return false;
    }
  }

  /// Read all non-null ISBNs from the local DB and push them to the hub.
  /// Returns the number of ISBNs pushed, or -1 on error.
  Future<int> hubDirectorySyncCatalog() async {
    try {
      return await frb.hubDirectorySyncCatalog();
    } catch (e) {
      debugPrint('FFI hubDirectorySyncCatalog error: $e');
      return -1;
    }
  }

  /// List libraries in the public directory (paginated, with optional search).
  Future<List<frb.FrbHubProfile>> hubDirectoryList({
    required int limit,
    required int offset,
    String? search,
  }) async {
    try {
      return await frb.hubDirectoryList(
        limit: limit,
        offset: offset,
        search: search,
      );
    } catch (e) {
      debugPrint('FFI hubDirectoryList error: $e');
      return [];
    }
  }

  /// Get a single library profile by nodeId.
  Future<frb.FrbHubProfile?> hubDirectoryGetProfile(String nodeId) async {
    try {
      return await frb.hubDirectoryGetProfile(nodeId: nodeId);
    } catch (e) {
      debugPrint('FFI hubDirectoryGetProfile error: $e');
      return null;
    }
  }

  /// Get the enriched catalog (ISBN + title + author) of a followed library.
  Future<List<frb.FrbCatalogEntry>> hubDirectoryGetCatalog(String nodeId) async {
    try {
      final entries = await frb.hubDirectoryGetCatalog(nodeId: nodeId);
      return entries;
    } catch (e) {
      debugPrint('FFI hubDirectoryGetCatalog error: $e');
      return [];
    }
  }

  /// Follow (or request to follow) a library.
  /// Throws on error so the caller can display the message.
  Future<frb.FrbHubFollow?> hubDirectoryFollow(String nodeId) async {
    try {
      return await frb.hubDirectoryFollow(nodeId: nodeId);
    } catch (e) {
      debugPrint('FFI hubDirectoryFollow error: $e');
      rethrow;
    }
  }

  /// Unfollow a library.
  Future<bool> hubDirectoryUnfollow(String nodeId) async {
    try {
      await frb.hubDirectoryUnfollow(nodeId: nodeId);
      return true;
    } catch (e) {
      debugPrint('FFI hubDirectoryUnfollow error: $e');
      return false;
    }
  }

  /// List incoming follow requests that are pending approval.
  Future<List<frb.FrbHubFollow>> hubDirectoryPendingRequests() async {
    try {
      return await frb.hubDirectoryPendingRequests();
    } catch (e) {
      debugPrint('FFI hubDirectoryPendingRequests error: $e');
      return [];
    }
  }

  /// Resolve a follow request: resolution is "approve", "reject", or "block".
  /// When approving, [encryptedContact] is an optional sealed blob.
  Future<frb.FrbHubFollow?> hubDirectoryResolveFollow(
    int followId,
    String resolution, {
    String? encryptedContact,
  }) async {
    try {
      return await frb.hubDirectoryResolveFollow(
        followId: followId,
        resolution: resolution,
        encryptedContact: encryptedContact,
      );
    } catch (e) {
      debugPrint('FFI hubDirectoryResolveFollow error: $e');
      return null;
    }
  }

  /// List libraries this library follows.
  Future<List<frb.FrbHubFollow>> hubDirectoryListFollowing() async {
    try {
      return await frb.hubDirectoryListFollowing();
    } catch (e) {
      debugPrint('FFI hubDirectoryListFollowing error: $e');
      return [];
    }
  }

  /// List libraries that follow this library.
  Future<List<frb.FrbHubFollow>> hubDirectoryListFollowers() async {
    try {
      return await frb.hubDirectoryListFollowers();
    } catch (e) {
      debugPrint('FFI hubDirectoryListFollowers error: $e');
      return [];
    }
  }

  // ============ Hub Borrow Requests (ADR-018) ============

  /// Create a hub-mediated borrow request for a book from a followed library.
  Future<frb.FrbHubBorrowRequest> hubDirectoryCreateBorrowRequest(
    String lenderNodeId,
    String isbn,
    String bookTitle,
  ) async {
    return await frb.hubDirectoryCreateBorrowRequest(
      lenderNodeId: lenderNodeId,
      isbn: isbn,
      bookTitle: bookTitle,
    );
  }

  /// Fetch incoming borrow requests (pending) for the local library as lender.
  Future<List<frb.FrbHubBorrowRequest>> hubDirectoryIncomingBorrowRequests() async {
    try {
      return await frb.hubDirectoryIncomingBorrowRequests();
    } catch (e) {
      debugPrint('FFI hubDirectoryIncomingBorrowRequests error: $e');
      return [];
    }
  }

  /// Fetch outgoing borrow requests sent by the local library as requester.
  Future<List<frb.FrbHubBorrowRequest>> hubDirectoryOutgoingBorrowRequests() async {
    try {
      return await frb.hubDirectoryOutgoingBorrowRequests();
    } catch (e) {
      debugPrint('FFI hubDirectoryOutgoingBorrowRequests error: $e');
      return [];
    }
  }

  /// Resolve a borrow request: resolution is "accept" or "reject".
  Future<frb.FrbHubBorrowRequest> hubDirectoryResolveBorrowRequest(
    int requestId,
    String resolution,
  ) async {
    return await frb.hubDirectoryResolveBorrowRequest(
      requestId: requestId,
      resolution: resolution,
    );
  }

  // ============ E2EE Sealed Blob ============

  /// Encrypt plaintext for a recipient identified by their X25519 public key (hex).
  Future<String> sealBlob(String recipientX25519Hex, String plaintext) async {
    return await frb.sealBlob(
      recipientX25519Hex: recipientX25519Hex,
      plaintext: plaintext,
    );
  }

  /// Decrypt a sealed blob using the local node identity's X25519 secret key.
  Future<String> openBlob(String sealedBase64) async {
    return await frb.openBlob(sealedBase64: sealedBase64);
  }

  /// Batch-update encrypted contact blobs for active followers.
  Future<int> hubDirectorySyncContacts(
    List<int> followIds,
    List<String> encryptedContacts,
  ) async {
    return await frb.hubDirectorySyncContacts(
      followIds: Int64List.fromList(followIds),
      encryptedContacts: encryptedContacts,
    );
  }

  /// Returns the local X25519 public key as hex string, or null if no identity.
  Future<String?> getLocalX25519PublicKey() async {
    try {
      return await frb.getLocalX25519PublicKey();
    } catch (e) {
      debugPrint('FFI getLocalX25519PublicKey error: $e');
      return null;
    }
  }

  // ============ HTTP Server ============

  /// Start the HTTP server on the specified port
  /// This is required for P2P functionality in standalone mode
  Future<int?> startServer(int port) async {
    // Zombie cleanup disabled - it was killing the app during hot restart
    // The /api/admin/shutdown endpoint is still available for manual use
    // if (kDebugMode && port == 8000) { ... }

    try {
      final actualPort = await frb.startServer(port: port);
      debugPrint('🚀 FfiService: HTTP Server started on port $actualPort');
      return actualPort;
    } catch (e) {
      debugPrint('❌ FfiService: Failed to start server: $e');
      return null;
    }
  }

  // ============ View Stats ============

  /// Get library view statistics (peer and follower views).
  /// Returns parsed JSON map with total_peer, total_follower, total, daily.
  Future<Map<String, dynamic>> getLibraryViewStats() async {
    try {
      final json = await frb.getLibraryViewStats();
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('FFI getLibraryViewStats error: $e');
      return {'total_peer': 0, 'total_follower': 0, 'total': 0, 'daily': []};
    }
  }

  // ============ Activity Feed (Notifications) ============

  Future<List<frb.FrbNotification>> notificationsList({
    String? category,
    int offset = 0,
    int limit = 50,
  }) async {
    try {
      return await frb.notificationsList(
        category: category,
        offset: BigInt.from(offset),
        limit: BigInt.from(limit),
      );
    } catch (e) {
      debugPrint('FFI notificationsList error: $e');
      return [];
    }
  }

  Future<int> notificationsUnreadCount({String? category}) async {
    try {
      return await frb.notificationsUnreadCount(category: category);
    } catch (e) {
      debugPrint('FFI notificationsUnreadCount error: $e');
      return 0;
    }
  }

  Future<bool> notificationsMarkRead(int id) async {
    try {
      return await frb.notificationsMarkRead(id: id);
    } catch (e) {
      debugPrint('FFI notificationsMarkRead error: $e');
      return false;
    }
  }

  Future<int> notificationsMarkAllRead() async {
    try {
      return await frb.notificationsMarkAllRead();
    } catch (e) {
      debugPrint('FFI notificationsMarkAllRead error: $e');
      return 0;
    }
  }

  Future<bool> notificationsDismiss(int id) async {
    try {
      return await frb.notificationsDismiss(id: id);
    } catch (e) {
      debugPrint('FFI notificationsDismiss error: $e');
      return false;
    }
  }

  Future<int> notificationsPrune() async {
    try {
      return await frb.notificationsPrune();
    } catch (e) {
      debugPrint('FFI notificationsPrune error: $e');
      return 0;
    }
  }
}
