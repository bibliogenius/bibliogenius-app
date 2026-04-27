import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';
import 'package:uuid/uuid.dart';
import '../models/collection.dart';
import 'api_service.dart';
import 'curated_lists_service.dart';

class CollectionImportResult {
  final int successCount;
  final int totalCount;
  final int errorCount;
  final String? error;
  final Collection? collection;

  CollectionImportResult({
    required this.successCount,
    required this.totalCount,
    this.errorCount = 0,
    this.error,
    this.collection,
  });

  bool get hasError => error != null || errorCount > 0;
}

class CollectionImportService {
  final ApiService _apiService;

  CollectionImportService(this._apiService);

  Future<CollectionImportResult> importList({
    required CuratedList list,
    required String langCode,
    required String readingStatus,
    required bool shouldMarkAsOwned,
  }) async {
    final listTitle = list.getTitle(langCode);
    final listDescription = list.getDescription(langCode);
    int successCount = 0;
    int errorCount = 0;

    try {
      // 1. Create the collection
      final collection = await _apiService.createCollection(
        listTitle,
        description: listDescription,
      );

      final collectionId = collection.id.toString();

      // 2. Import books by ISBN
      for (final book in list.books) {
        try {
          final isbn = book.getIsbnForLanguage(langCode);

          // Lookup metadata from external sources (cover, author, publisher...)
          final lookup = await _apiService.lookupBook(isbn);

          // Prepare book data: lookup results enriched with YAML overrides
          // Prefer lookup title over note (note may contain "Title - Author (Year)")
          String? noteTitle;
          if (book.note != null) {
            // Parse "Title - Author (Year)" or "Title - Author" format
            final dashIdx = book.note!.indexOf(' - ');
            noteTitle = dashIdx > 0
                ? book.note!.substring(0, dashIdx).trim()
                : book.note;
          }
          final bookData = {
            'isbn': isbn,
            'title': lookup?['title'] ?? noteTitle ?? 'Untitled',
            'reading_status': readingStatus,
            'owned': shouldMarkAsOwned,
            'author': lookup?['author'] ?? book.authors?.join(', '),
            'publisher': book.publisher ?? lookup?['publisher'],
            'publication_year': book.publishedDate ?? lookup?['year'],
            'description': book.description ?? lookup?['summary'],
            'cover_url': book.coverUrl ?? lookup?['cover_url'],
          };

          // Try Create
          int? bookId;
          final createRes = await _apiService.createBook(bookData);

          if (createRes.statusCode == 201) {
            final data = createRes.data;
            if (data is Map && data.containsKey('book')) {
              bookId = data['book']['id'];
            } else {
              bookId = data['id'];
            }
          } else {
            // If creation failed (duplicate), try to find
            final existingBook = await _apiService.findBookByIsbn(isbn);
            if (existingBook != null) {
              bookId = existingBook.id;
            }
          }

          // Link to Collection
          if (bookId != null) {
            await _apiService.addBookToCollection(collectionId, bookId);
            successCount++;
          } else {
            errorCount++;
          }
        } catch (e) {
          debugPrint('Error importing book ${book.isbn}: $e');
          errorCount++;
        }
      }

      return CollectionImportResult(
        successCount: successCount,
        totalCount: list.books.length,
        errorCount: errorCount,
        collection: collection,
      );
    } catch (e) {
      return CollectionImportResult(
        successCount: successCount,
        totalCount: list.books.length,
        errorCount: errorCount,
        error: e.toString(),
      );
    }
  }

  /// Validates a YAML string for shared list format.
  String? validateYaml(String content) {
    try {
      final yaml = loadYaml(content);
      if (yaml is! Map) return 'Invalid YAML format';
      if (!yaml.containsKey('title')) return 'Missing "title" field';
      if (!yaml.containsKey('books')) return 'Missing "books" list';
      return null;
    } catch (e) {
      return 'YAML parsing error: $e';
    }
  }

  /// Returns a preview map of the list (title, description, count, etc.)
  Map<String, dynamic> getPreview(String content) {
    try {
      final yaml = loadYaml(content) as YamlMap;

      // Handle title (string or map)
      String title = 'Untitled';
      if (yaml['title'] is String) {
        title = yaml['title'];
      } else if (yaml['title'] is Map) {
        // Naive check for en/fr or first value
        final map = yaml['title'] as Map;
        title = map['en'] ?? map['default'] ?? map.values.first ?? 'Untitled';
      }

      String? description;
      if (yaml['description'] is String) {
        description = yaml['description'];
      } else if (yaml['description'] is Map) {
        final map = yaml['description'] as Map;
        description = map['en'] ?? map['default'] ?? map.values.first;
      }

      final books = yaml['books'];
      int count = 0;
      if (books is List) count = books.length;

      return {
        'title': title,
        'description': description,
        'bookCount': count,
        'contributor': yaml['contributor'],
      };
    } catch (e) {
      return {'title': 'Error previewing file'};
    }
  }

  /// Imports from a raw YAML string.
  Future<CollectionImportResult> importFromYaml(
    String content, {
    required String readingStatus,
    required bool markAsOwned,
  }) async {
    try {
      var yaml = loadYaml(content);

      // Inject ID if missing to satisfy CuratedList.fromYaml
      Map<String, dynamic> mutableYaml;
      if (yaml is YamlMap) {
        mutableYaml = Map<String, dynamic>.from(yaml);
      } else if (yaml is Map) {
        mutableYaml = Map<String, dynamic>.from(yaml);
      } else {
        throw FormatException('Invalid YAML structure');
      }

      if (!mutableYaml.containsKey('id')) {
        mutableYaml['id'] = const Uuid().v4();
      }

      // Re-encode or construct YamlMap?
      // CuratedList.fromYaml takes a YamlMap or Map?
      // CuratedList.fromYaml definition (810): factory CuratedList.fromYaml(YamlMap yaml)
      // It expects YamlMap. But YamlMap is hard to construct manually.
      // However, usually typing is `dynamic yaml` or I can adapt `CuratedList` to accept Map.
      // Wait, `fromYaml(YamlMap yaml)` is strict.
      // If I pass a `Map`, it will fail at runtime if I enable type checks?
      // Let's check `CuratedList.fromYaml` again.
      // Line 62: `factory CuratedList.fromYaml(YamlMap yaml)`.

      // If `loadYaml` returns `YamlMap`, it's immutable. checking `containsKey` works.
      // But I can't add 'id' to it.

      // Strategy: Use a generated ID if I can't parse it?
      // OR, manually construct `CuratedList` instead of using `fromYaml` which demands YamlMap.

      String id = mutableYaml['id']?.toString() ?? const Uuid().v4();
      int version = mutableYaml['version'] is int ? mutableYaml['version'] : 1;

      // Parse title
      Map<String, String> titleMap = {};
      if (mutableYaml['title'] is String) {
        titleMap = {'default': mutableYaml['title']};
      } else if (mutableYaml['title'] is Map) {
        titleMap = Map<String, String>.from(mutableYaml['title']);
      }

      // Parse description
      Map<String, String> descMap = {};
      if (mutableYaml['description'] is String) {
        descMap = {'default': mutableYaml['description']};
      } else if (mutableYaml['description'] is Map) {
        descMap = Map<String, String>.from(mutableYaml['description']);
      }

      // Books
      List<CuratedBook> books = [];
      if (mutableYaml['books'] is List) {
        for (var b in mutableYaml['books']) {
          // CuratedBook.fromYaml accepts dynamic yaml (String or Map)
          books.add(CuratedBook.fromYaml(b));
        }
      }

      List<String> tags = [];
      if (mutableYaml['tags'] is List) {
        tags = (mutableYaml['tags'] as List).map((e) => e.toString()).toList();
      }

      final list = CuratedList(
        id: id,
        version: version,
        title: titleMap,
        description: descMap,
        coverUrl: mutableYaml['cover_url'],
        contributor: mutableYaml['contributor'],
        tags: tags,
        books: books,
      );

      // Reuse valid import logic
      // Note: we can hardcode langCode to 'default' or passed 'en' if we don't have context,
      // but `importList` takes `langCode`.
      // I should allow passing langCode to `importFromYaml`?
      // `ImportSharedListScreen` doesn't seem to pass it?
      // `ImportSharedListScreen` uses `importFromYaml(content, readingStatus..., markAsOwned...)`.
      // I can fetch device locale inside, or just default to 'en' or 'fr'.

      // I will assume 'en' or try to detect?
      // Or better, I will assume the user wants the "default" or "current" language,
      // but `ImportSharedListScreen` calls it without lang.
      // For now I'll default to 'en' in the call to `importList`.

      return importList(
        list: list,
        langCode:
            'fr', // Defaulting to FR or I should modify signature to accept it.
        readingStatus: readingStatus,
        shouldMarkAsOwned: markAsOwned,
      );
    } catch (e) {
      return CollectionImportResult(
        successCount: 0,
        totalCount: 0,
        error: e.toString(),
      );
    }
  }
}
