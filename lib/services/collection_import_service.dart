import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';
import 'package:uuid/uuid.dart';
import '../models/collection.dart';
import 'api_service.dart';
import 'curated_lists_service.dart';
import 'ffi_service.dart';

class CollectionImportResult {
  final int successCount;
  final int totalCount;
  final int errorCount;
  final String? error;
  final Collection? collection;

  /// Cleaned ISBNs (digits and X only, backend storage form) of the books
  /// actually created or linked during the import.
  final List<String> importedIsbns;

  CollectionImportResult({
    required this.successCount,
    required this.totalCount,
    this.errorCount = 0,
    this.error,
    this.collection,
    this.importedIsbns = const [],
  });

  bool get hasError => error != null || errorCount > 0;
}

class CollectionImportService {
  final ApiService _apiService;

  CollectionImportService(this._apiService);

  /// Normalize an ISBN the way the backend stores it (digits and X only).
  static String cleanIsbn(String isbn) =>
      isbn.replaceAll(RegExp(r'[^0-9X]'), '');

  /// True when the curated entry already carries everything [createBook] needs,
  /// so the network lookup would add nothing.
  ///
  /// Of the six fields the import writes, four already read the YAML first;
  /// only `title` and `author` prefer the lookup. When `note` and `authors`
  /// are both present those two are covered as well, by curated values that
  /// were chosen and reviewed rather than pulled from a catalogue. Skipping
  /// the call then costs no quality at all.
  ///
  /// What it buys: the import used to await one lookup per book, in sequence,
  /// and a single lookup can take 15+ seconds when the backend walks its whole
  /// BnF/Inventaire/OpenLibrary/Google chain. A fully described list now makes
  /// no network call at all and imports offline.
  ///
  /// Deliberately strict, `cover_url` included: without it the lookup is the
  /// only thing that can supply a cover, and it earns its cost. Lists written
  /// before this guard carry only `isbn` and `note`, so it never fires for
  /// them and their behaviour is unchanged.
  static bool isSelfSufficient(CuratedBook book) =>
      (book.note?.isNotEmpty ?? false) &&
      (book.authors?.isNotEmpty ?? false) &&
      (book.publisher?.isNotEmpty ?? false) &&
      (book.publishedDate?.isNotEmpty ?? false) &&
      (book.description?.isNotEmpty ?? false) &&
      (book.coverUrl?.isNotEmpty ?? false);

  /// Import [list] as a new collection.
  ///
  /// [readerLanguages] picks each book's edition in the reader's own order
  /// of preference (the ADR-061 recette A4 lesson) rather than the order of
  /// the file. [langCode] still names the collection and its description.
  /// When [readerLanguages] is empty the single-language behaviour is kept
  /// exactly as it was.
  ///
  /// [subjects] are shelf labels applied to every imported book through the
  /// existing `createBook` field (ADR-066 section 6): one write, no second
  /// pass over the catalogue.
  /// [onProgress] is called with `(done, total)` before the first book and
  /// after each one, so a caller can show where the import is. The loop is
  /// one network lookup per book, in sequence, each with its own timeout:
  /// without this the reader gets a silent screen for as long as that takes
  /// and no way to tell a slow import from a dead one.
  ///
  /// [isCancelled] is polled before each book. Returning true stops the loop
  /// and returns what has been created so far, which is a normal outcome
  /// rather than an error: the books already imported are the reader's.
  Future<CollectionImportResult> importList({
    required CuratedList list,
    required String langCode,
    required String readingStatus,
    required bool shouldMarkAsOwned,
    List<String> readerLanguages = const [],
    List<String> subjects = const [],
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
    Iterable<String> existingCollectionNames = const [],
    String? nameCollisionFormat,
  }) async {
    final listTitle = resolveImportedCollectionName(
      title: list.getTitle(langCode),
      existingNames: existingCollectionNames,
      contributor: list.contributor,
      withContributorFormat: nameCollisionFormat,
    );
    final listDescription = list.getDescription(langCode);
    int successCount = 0;
    int errorCount = 0;
    final importedIsbns = <String>[];

    try {
      // 1. Create the collection
      final collection = await _apiService.createCollection(
        listTitle,
        description: listDescription,
        // Records which list this came from, so deleting the collection can
        // undo the dismissal the import wrote (ADR-066 section 7).
        source: '${Collection.curatedSourcePrefix}${list.id}',
      );

      final collectionId = collection.id.toString();

      // 2. Import books by ISBN
      onProgress?.call(0, list.books.length);
      for (final book in list.books) {
        if (isCancelled?.call() ?? false) break;
        try {
          final isbn = readerLanguages.isEmpty
              ? book.getIsbnForLanguage(langCode)
              : book.getIsbnForLanguages(readerLanguages);

          // Lookup metadata from external sources (cover, author, publisher...),
          // unless the curated entry already has all of it: see
          // [isSelfSufficient]. Kept sequential on purpose. Running these
          // concurrently would turn one import into a burst against the same
          // external catalogues, which is what rate limiters look for, and the
          // Rust side already settled this question the other way by sleeping
          // 500ms between books in its cover enrichment loop.
          final lookup = isSelfSufficient(book)
              ? null
              : await _apiService.lookupBook(isbn);

          // Prepare book data: lookup results enriched with YAML overrides
          // Prefer lookup title over note (note may contain "Title - Author (Year)")
          // The entry's OWN name, the one the preview showed the reader.
          // The metadata source is the last resort, not the first: a reader
          // who validated "Les androides revent-ils de moutons electriques ?"
          // used to find "Blade runner" in their library, because the source
          // titles that edition after the film.
          final entryTitle = book.displayTitle;
          final bookData = {
            'isbn': isbn,
            'title': entryTitle ?? lookup?['title'] ?? 'Untitled',
            'reading_status': readingStatus,
            'owned': shouldMarkAsOwned,
            'author': lookup?['author'] ?? book.authors?.join(', '),
            'publisher': book.publisher ?? lookup?['publisher'],
            'publication_year': book.publishedDate ?? lookup?['year'],
            'description': book.description ?? lookup?['summary'],
            'cover_url': book.coverUrl ?? lookup?['cover_url'],
            // Omitted entirely when empty rather than sent as []: an empty
            // list is a value, and createBook would write it over whatever
            // an existing book already carries.
            if (subjects.isNotEmpty) 'subjects': subjects,
          };

          // Try Create
          String? bookId;
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
            final clean = cleanIsbn(isbn);
            if (clean.isNotEmpty) importedIsbns.add(clean);
          } else {
            errorCount++;
          }
        } catch (e) {
          debugPrint('Error importing book ${book.isbn}: $e');
          errorCount++;
        }
        onProgress?.call(successCount + errorCount, list.books.length);
      }

      // A wishlist import fired one wishlist_match notification per matched
      // book (backend create-book trigger); collapse them into one
      // aggregated notification for the batch. Living here covers every
      // entry point (curated lists AND shared YAML imports). Errors are
      // swallowed by the FFI wrapper.
      if (readingStatus == 'wanting' && importedIsbns.isNotEmpty) {
        await FfiService().aggregateWishlistImportNotification(
          batchRef: collectionId,
          listTitle: listTitle,
          isbns: importedIsbns,
        );
      }

      return CollectionImportResult(
        successCount: successCount,
        totalCount: list.books.length,
        errorCount: errorCount,
        collection: collection,
        importedIsbns: importedIsbns,
      );
    } catch (e) {
      return CollectionImportResult(
        successCount: successCount,
        totalCount: list.books.length,
        errorCount: errorCount,
        error: e.toString(),
        importedIsbns: importedIsbns,
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

  /// Parses a shared list's YAML into a [CuratedList], without touching the
  /// library.
  ///
  /// Exposed and pure so the round trip has a contract: one reader exports a
  /// collection, another imports the file, and nothing but this agreement
  /// holds the two formats together. Guarded by
  /// `test/services/shared_list_round_trip_test.dart`.
  ///
  /// Accepts both shapes the corpus uses for `title` and `description`, a
  /// bare string as the exporter writes and a per-language map as the bundled
  /// lists carry.
  ///
  /// **`curation_status` is deliberately NOT read.** Promotion is an
  /// editorial act of THIS install (ADR-066): a file that could declare
  /// itself audited would let a stranger's list into the suggestion tier.
  static CuratedList parseSharedList(String content) {
    final yaml = loadYaml(content);
    if (yaml is! Map) {
      throw const FormatException('Invalid YAML structure');
    }
    final map = Map<String, dynamic>.from(yaml);

    // An id can be missing OR blank: the exporter builds it by stripping
    // everything non-alphanumeric from the collection name, so a name like
    // "***" yields an empty string rather than no key at all.
    final rawId = map['id']?.toString().trim() ?? '';
    final id = rawId.isEmpty ? const Uuid().v4() : rawId;

    Map<String, String> localized(dynamic value) {
      if (value is String) return {'default': value};
      if (value is Map) {
        return value.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
      return {};
    }

    return CuratedList(
      id: id,
      version: map['version'] is int ? map['version'] as int : 1,
      title: localized(map['title']),
      description: localized(map['description']),
      coverUrl: _safeCoverUrl(map['cover_url']),
      contributor: map['contributor']?.toString(),
      tags: map['tags'] is List
          ? (map['tags'] as List).map((e) => e.toString()).toList()
          : const [],
      books: map['books'] is List
          ? (map['books'] as List)
                .map(CuratedBook.fromYaml)
                .map(_withSafeCover)
                .toList()
          : const [],
      contentLanguages: map['content_languages'] is List
          ? (map['content_languages'] as List).map((e) => e.toString()).toList()
          : const [],
    );
  }

  /// Size past which a shared list is refused before being parsed.
  ///
  /// Refused, not warned about, unlike an over-long list: the entry-count
  /// warning can only be shown AFTER parsing, so it does nothing about the
  /// cost of the parse itself. Reading and parsing an arbitrary file handed
  /// over by someone else is the part that has to be bounded first.
  ///
  /// Generous on purpose. Measured 2026-08-24: the entire bundled corpus, 83
  /// lists and 906 entries, weighs 396 KB, and its longest single list weighs
  /// 12 KB. A megabyte is therefore some twenty times the whole catalogue and
  /// cannot be reached by a real list.
  static const int maxSharedListBytes = 1024 * 1024;

  static bool isTooLargeToParse(int byteCount) =>
      byteCount > maxSharedListBytes;

  /// The name an imported list takes, given what the library already holds.
  ///
  /// A shared list is never MERGED into a collection of the same name, and the
  /// favourites case is why the rule has no exception: there, membership IS
  /// the star (ADR-064), and a liked book weighs double in the ADR-066
  /// ranking. Merging someone else's favourites would therefore bend the
  /// reader's own recommendations toward another person's taste, silently and
  /// with no obvious way back.
  ///
  /// So a collision is answered by NAMING: "Favoris de Nohemi". Only on a
  /// collision, because decorating a name nothing clashes with is noise. And
  /// only when the file names its sender: without a contributor the bare
  /// title is kept and the duplicate is accepted, which is honest rather than
  /// inventing an origin.
  ///
  /// [existingNames] must be the names as DISPLAYED, not as stored: a
  /// favourites collection holds the technical `__favorites__` sentinel and
  /// shows a translated label, so comparing stored names would miss exactly
  /// the collision this exists for. [withContributorFormat] is the translated
  /// template carrying `{title}` and `{contributor}`, passed in because the
  /// connector is a word and words have a language.
  static String resolveImportedCollectionName({
    required String title,
    required Iterable<String> existingNames,
    String? contributor,
    String? withContributorFormat,
  }) {
    final key = title.trim().toLowerCase();
    final collides = existingNames.any((n) => n.trim().toLowerCase() == key);
    if (!collides) return title;

    final sender = contributor?.trim() ?? '';
    if (sender.isEmpty || withContributorFormat == null) return title;

    return withContributorFormat
        .replaceAll('{title}', title)
        .replaceAll('{contributor}', sender);
  }

  /// Entry count above which an imported list is worth a word of warning.
  ///
  /// A warning, never a refusal: a long list is unusual, not hostile, and
  /// refusing one would block a legitimate case. Someone sharing a full manga
  /// run has every right to.
  ///
  /// Deliberately far above anything real. Measured 2026-08-24: the longest
  /// list in the bundled corpus is `naruto` at 72 entries, the whole corpus of
  /// 83 lists holds 906, and the reference library is 492 books. So a shared
  /// list past this mark is not a reading list, it is someone's entire library
  /// or a file built to be heavy.
  ///
  /// What the warning is about is cost, not danger: the import calls the
  /// metadata lookup ONCE PER BOOK and each call waits out its own timeout, so
  /// a very long list means a very long spinner, and offline it means a very
  /// long one for nothing.
  static const int largeListWarningThreshold = 500;

  /// Whether [bookCount] deserves the warning above. The boundary is
  /// inclusive: exactly [largeListWarningThreshold] books stays quiet.
  static bool isLargeSharedList(int bookCount) =>
      bookCount > largeListWarningThreshold;

  /// Keeps a cover URL only when it is https.
  ///
  /// This file arrives from someone else and the app FETCHES what it points
  /// at, so an attacker-chosen URL turns the reader's device into a beacon:
  /// their IP and the moment they opened the list, over cleartext, without a
  /// gesture on their part. The bundled corpus is held to the same rule,
  /// where `audit_curated_lists.dart` reports a non-https cover as BLOCKING;
  /// a shared list has no audit at all, so the check has to live at the door.
  ///
  /// Dropped rather than rejected: losing an illustration is not a reason to
  /// refuse a list the reader asked for. The ISBN lookup finds a cover anyway.
  static String? _safeCoverUrl(dynamic value) {
    final url = value?.toString().trim() ?? '';
    return url.toLowerCase().startsWith('https://') ? url : null;
  }

  static CuratedBook _withSafeCover(CuratedBook book) {
    final safe = _safeCoverUrl(book.coverUrl);
    return safe == book.coverUrl ? book : book.withCoverUrl(safe);
  }

  /// Imports from a raw YAML string, as handed over by the file picker or the
  /// clipboard.
  ///
  /// [langCode] picks which language the list's own title and description are
  /// read in; the caller passes the reader's locale, since a shared list is
  /// as likely to arrive in one language as in another.
  Future<CollectionImportResult> importFromYaml(
    String content, {
    required String readingStatus,
    required bool markAsOwned,
    String langCode = 'fr',
    Iterable<String> existingCollectionNames = const [],
    String? nameCollisionFormat,
  }) async {
    try {
      return importList(
        list: parseSharedList(content),
        langCode: langCode,
        readingStatus: readingStatus,
        shouldMarkAsOwned: markAsOwned,
        existingCollectionNames: existingCollectionNames,
        nameCollisionFormat: nameCollisionFormat,
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
