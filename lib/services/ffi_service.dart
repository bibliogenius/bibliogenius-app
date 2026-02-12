// FFI Service - Wrapper for Rust FFI calls
// This service provides a clean interface to the Rust backend via FFI
// Used on native platforms (iOS, Android, macOS, Windows, Linux)

import 'package:flutter/foundation.dart';
import '../models/book.dart';
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

  /// Return a loan
  Future<void> returnLoan(int id) async {
    try {
      await frb.returnLoan(id: id);
    } catch (e) {
      debugPrint('FFI returnLoan error: $e');
      rethrow;
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
}
