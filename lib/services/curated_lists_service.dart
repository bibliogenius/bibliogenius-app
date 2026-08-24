import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

/// Represents a book within a curated list.
/// Uses ISBN as primary identifier, with optional fallback metadata.
class CuratedBook {
  final String isbn;
  final String? note;
  final Map<String, String>? altEditions;
  final String? publisher;
  final String? publishedDate;
  final String? description;
  final List<String>? authors;
  final int? pageCount;
  final String? coverUrl;

  /// Clean work title, when the entry carries one. The richer lists (the
  /// jeunesse and tech series) do, and theirs is the only reliable title:
  /// their `note` is a volume caption like "Tome 1 : ...". Read for identity
  /// matching (ADR-066), where a wrong title costs an overlap.
  final String? title;

  const CuratedBook({
    required this.isbn,
    this.note,
    this.altEditions,
    this.publisher,
    this.publishedDate,
    this.description,
    this.authors,
    this.pageCount,
    this.coverUrl,
    this.title,
  });

  factory CuratedBook.fromYaml(dynamic yaml) {
    if (yaml is String) {
      // Simple format: just ISBN
      return CuratedBook(isbn: yaml);
    } else if (yaml is Map) {
      // Extended format with metadata
      return CuratedBook(
        isbn: yaml['isbn'] as String,
        note: yaml['note'] as String?,
        altEditions: yaml['alt_editions'] != null
            ? Map<String, String>.from(yaml['alt_editions'] as Map)
            : null,
        publisher: yaml['publisher'] as String?,
        publishedDate: yaml['published_date'] as String?,
        description: yaml['description'] as String?,
        authors: yaml['authors'] != null
            ? (yaml['authors'] as List).map((e) => e.toString()).toList()
            : null,
        pageCount: yaml['page_count'] as int?,
        coverUrl: yaml['cover_url'] as String?,
        title: yaml['title'] as String?,
      );
    }
    throw FormatException('Invalid book format: $yaml');
  }

  /// Get the best ISBN for a given language.
  /// Falls back to default ISBN if no alternative exists.
  String getIsbnForLanguage(String langCode) {
    if (altEditions != null && altEditions!.containsKey(langCode)) {
      return altEditions![langCode]!;
    }
    return isbn;
  }

  /// The edition to import for a reader, honouring the ORDER of their
  /// languages rather than the order of the file (the ADR-061 recette A4
  /// lesson): a trilingual reader whose first language is French gets the
  /// French edition even when the entry lists a Spanish one first.
  ///
  /// Falls back to the contributor's own ISBN when no alternative matches,
  /// which is what the single-language form has always done.
  String getIsbnForLanguages(List<String> langCodes) {
    final alternatives = altEditions;
    if (alternatives != null) {
      for (final code in langCodes) {
        final match = alternatives[code];
        if (match != null && match.isNotEmpty) return match;
      }
    }
    return isbn;
  }

  /// Every ISBN this entry can be recognised by: the contributor's own plus
  /// every alternate edition. Used by the identity membrane, which must
  /// count a reader who owns ANY edition as owning the book, whichever one
  /// the import would have picked for them.
  List<String> get allIsbns => [
    isbn,
    ...?altEditions?.values,
  ].where((value) => value.trim().isNotEmpty).toList();

  /// Best work title for identity matching, or null when the entry carries
  /// none usable.
  ///
  /// Prefers the explicit `title` field, then the `"Title - Author"` note
  /// form that every note-only entry of the corpus uses. A note with no
  /// dash is a volume caption, not a title, and yields nothing rather than
  /// a wrong match.
  String? get identityTitle {
    final explicit = title?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final raw = note;
    if (raw == null) return null;
    final dash = raw.indexOf(' - ');
    if (dash <= 0) return null;
    return raw.substring(0, dash).trim();
  }

  /// What this entry is CALLED, for any surface that shows it to a reader.
  ///
  /// One definition, so the preview and the import cannot promise different
  /// books: whatever the reader validated is what lands in their library.
  ///
  /// The explicit `title` wins because it exists precisely for the entries
  /// whose note is unreliable (ADR-066 amendment A3). The 72 volumes of the
  /// Naruto list note "Naruto - Tome N", and a split on the first dash calls
  /// every one of them "Naruto".
  ///
  /// Null when the entry offers no name at all. The caller supplies its own
  /// last resort: the catalogue shows the ISBN, the import asks the metadata
  /// source, and neither belongs in here.
  String? get displayTitle {
    final explicit = title?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final raw = note?.trim();
    if (raw == null || raw.isEmpty) return null;
    final dash = raw.indexOf(' - ');
    return dash > 0 ? raw.substring(0, dash).trim() : raw;
  }

  /// Author names for identity matching: the explicit `authors` field, else
  /// the half of the `"Title - Author"` note that follows the dash, with a
  /// trailing "(1999)" dropped.
  List<String> get identityAuthors {
    final explicit = authors;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final raw = note;
    if (raw == null) return const [];
    final dash = raw.indexOf(' - ');
    if (dash <= 0) return const [];
    final tail = raw
        .substring(dash + 3)
        .replaceAll(RegExp(r'\(\s*\d{3,4}\s*\)'), '')
        .trim();
    return tail.isEmpty ? const [] : [tail];
  }
}

/// Represents a curated list of books.
class CuratedList {
  final String id;
  final int version;
  final Map<String, String> title;
  final Map<String, String> description;
  final String? coverUrl;
  final String? contributor;
  final List<String> tags;
  final List<CuratedBook> books;

  /// Editorial quality gate (ADR-066): `reviewed` or `draft`.
  ///
  /// Only a `reviewed` list may reach the AFFINITY surfaces, where the tier
  /// pushes a selection at a reader who asked for nothing. The full import
  /// catalogue keeps showing every list whatever its status: opening it is
  /// a deliberate act, and the reader who does is browsing, not being
  /// served.
  ///
  /// Absent means `draft`, deliberately fail-closed. The corpus has a
  /// measured history of entries pointing at the wrong book behind a valid
  /// ISBN, and nine lists are already withdrawn from the index for failed
  /// audits; a gate that defaults open would gate nothing on exactly the
  /// lists nobody has looked at yet.
  final String curationStatus;

  /// Languages in which the books of this list are primarily available.
  /// Empty when the list was authored before the field was introduced;
  /// the partitioning helper treats that as "unknown" and routes the list
  /// to the "other languages" section to avoid hiding it entirely.
  final List<String> contentLanguages;

  const CuratedList({
    required this.id,
    required this.version,
    required this.title,
    required this.description,
    this.coverUrl,
    this.contributor,
    required this.tags,
    required this.books,
    this.contentLanguages = const [],
    this.curationStatus = curationDraft,
  });

  /// Reviewed by a curator: eligible for the affinity surfaces.
  static const String curationReviewed = 'reviewed';

  /// Not reviewed yet: importable, never suggested.
  static const String curationDraft = 'draft';

  /// Whether this list may be PUSHED at a reader (ADR-066 quality gate).
  bool get isReviewed => curationStatus == curationReviewed;

  factory CuratedList.fromYaml(YamlMap yaml) {
    // Parse title (can be string or map)
    Map<String, String> titleMap;
    if (yaml['title'] is String) {
      titleMap = {'default': yaml['title'] as String};
    } else {
      titleMap = Map<String, String>.from(yaml['title'] as Map);
    }

    // Parse description (can be string or map)
    Map<String, String> descriptionMap;
    if (yaml['description'] is String) {
      descriptionMap = {'default': yaml['description'] as String};
    } else {
      descriptionMap = Map<String, String>.from(yaml['description'] as Map);
    }

    // Parse books
    final booksList = (yaml['books'] as YamlList)
        .map((b) => CuratedBook.fromYaml(b))
        .toList();

    // Parse tags
    final tagsList = yaml['tags'] != null
        ? (yaml['tags'] as YamlList).map((t) => t.toString()).toList()
        : <String>[];

    final contentLangs = yaml['content_languages'] != null
        ? (yaml['content_languages'] as YamlList)
              .map((l) => l.toString())
              .toList()
        : <String>[];

    return CuratedList(
      id: yaml['id'] as String,
      version: yaml['version'] as int? ?? 1,
      title: titleMap,
      description: descriptionMap,
      coverUrl: yaml['cover_url'] as String?,
      contributor: yaml['contributor'] as String?,
      tags: tagsList,
      books: booksList,
      contentLanguages: contentLangs,
      // Any value other than the exact `reviewed` marker reads as draft: a
      // typo must fail closed, not promote a list nobody reviewed.
      curationStatus:
          yaml['curation_status']?.toString().trim() == curationReviewed
          ? curationReviewed
          : curationDraft,
    );
  }

  /// Get localized title for the given language code.
  /// Falls back to 'en', then 'default', then first available.
  String getTitle(String langCode) {
    return title[langCode] ??
        title['en'] ??
        title['default'] ??
        title.values.first;
  }

  /// Get localized description for the given language code.
  String getDescription(String langCode) {
    return description[langCode] ??
        description['en'] ??
        description['default'] ??
        description.values.first;
  }
}

/// Result of splitting curated lists by language relevance to the user.
class CuratedListPartition {
  final List<CuratedList> inYourLanguages;
  final List<CuratedList> otherLanguages;

  const CuratedListPartition({
    required this.inYourLanguages,
    required this.otherLanguages,
  });

  bool get isEmpty => inYourLanguages.isEmpty && otherLanguages.isEmpty;
}

/// Split [lists] into the ones matching [userLanguages] and the rest.
///
/// Matching rule: a list belongs to `inYourLanguages` when at least one of
/// its `content_languages` entries is present in `userLanguages`. Lists with
/// an empty `content_languages` field fall back to `otherLanguages` so they
/// remain discoverable but never shadow language-tagged lists.
CuratedListPartition partitionCuratedListsByLanguage(
  List<CuratedList> lists,
  Set<String> userLanguages,
) {
  final inYours = <CuratedList>[];
  final other = <CuratedList>[];
  for (final list in lists) {
    if (list.contentLanguages.isNotEmpty &&
        list.contentLanguages.any(userLanguages.contains)) {
      inYours.add(list);
    } else {
      other.add(list);
    }
  }
  return CuratedListPartition(inYourLanguages: inYours, otherLanguages: other);
}

/// Represents a category of curated lists.
class CuratedCategory {
  final String id;
  final Map<String, String> title;
  final String icon;
  final List<String> listIds;

  const CuratedCategory({
    required this.id,
    required this.title,
    required this.icon,
    required this.listIds,
  });

  factory CuratedCategory.fromYaml(YamlMap yaml) {
    return CuratedCategory(
      id: yaml['id'] as String,
      title: Map<String, String>.from(yaml['title'] as Map),
      icon: yaml['icon'] as String? ?? 'list',
      listIds: (yaml['lists'] as YamlList).map((l) => l.toString()).toList(),
    );
  }

  String getTitle(String langCode) {
    return title[langCode] ?? title['en'] ?? title.values.first;
  }
}

/// Service for loading and managing curated lists.
class CuratedListsService {
  static CuratedListsService? _instance;

  List<CuratedCategory>? _categories;
  final Map<String, CuratedList> _listsCache = {};

  CuratedListsService._();

  static CuratedListsService get instance {
    _instance ??= CuratedListsService._();
    return _instance!;
  }

  /// Load the index of all available curated lists.
  Future<List<CuratedCategory>> loadCategories() async {
    if (_categories != null) return _categories!;

    final indexYaml = await rootBundle.loadString(
      'assets/curated_lists/index.yml',
    );
    final parsed = loadYaml(indexYaml) as YamlMap;

    _categories = (parsed['categories'] as YamlList)
        .map((c) => CuratedCategory.fromYaml(c as YamlMap))
        .toList();

    return _categories!;
  }

  /// Load a specific curated list by its ID.
  /// Searches in all category directories.
  ///
  /// [directoryHint] short-circuits that search. Every category id in
  /// `index.yml` IS its directory name, so a caller walking the index knows
  /// where the file is and should say so: without the hint each list costs
  /// up to nine failing asset reads, and a full-corpus pass (the editorial
  /// affinity sweep, ADR-066) would issue several hundred of them. The blind
  /// probe stays as the fallback so nothing depends on the hint being right.
  Future<CuratedList?> loadList(String listId, {String? directoryHint}) async {
    // Check cache first
    if (_listsCache.containsKey(listId)) {
      return _listsCache[listId];
    }

    if (directoryHint != null) {
      final hinted = await _tryLoad(directoryHint, listId);
      if (hinted != null) return hinted;
    }

    // Try to find the list in known directories.
    // This list is NOT derived from the category ids in index.yml: a new
    // category directory must be added here as well, or its lists silently
    // resolve to null and the category renders as empty.
    final directories = [
      'awards',
      'genres',
      'classics',
      'themes',
      'institutions',
      'manga',
      'tech',
      'jeunesse',
      'rentree',
    ];

    for (final dir in directories) {
      if (dir == directoryHint) continue;
      final list = await _tryLoad(dir, listId);
      if (list != null) return list;
    }

    return null;
  }

  Future<CuratedList?> _tryLoad(String directory, String listId) async {
    try {
      final listYaml = await rootBundle.loadString(
        'assets/curated_lists/$directory/$listId.yml',
      );
      final parsed = loadYaml(listYaml) as YamlMap;
      final list = CuratedList.fromYaml(parsed);
      _listsCache[listId] = list;
      return list;
    } catch (_) {
      // File not found in this directory, or unparseable: try the next.
      return null;
    }
  }

  /// Load all lists for a given category.
  Future<List<CuratedList>> loadListsForCategory(
    CuratedCategory category,
  ) async {
    final lists = <CuratedList>[];

    for (final listId in category.listIds) {
      final list = await loadList(listId, directoryHint: category.id);
      if (list != null) {
        lists.add(list);
      }
    }

    return lists;
  }

  /// Every list reachable through the index, deduplicated, in index order.
  ///
  /// Reachable is the operative word and it is a safety property, not a
  /// detail: list files whose ISBNs failed audit are commented out of
  /// `index.yml` while their file stays on disk, so a consumer reading the
  /// assets directly would resurrect exactly the lists that were withdrawn.
  /// Everything that consumes the corpus goes through here.
  Future<List<CuratedList>> loadAllLists() async {
    final categories = await loadCategories();
    final seen = <String>{};
    final lists = <CuratedList>[];
    for (final category in categories) {
      for (final list in await loadListsForCategory(category)) {
        if (seen.add(list.id)) lists.add(list);
      }
    }
    return lists;
  }

  /// Clear the cache (useful for hot reload during development).
  void clearCache() {
    _categories = null;
    _listsCache.clear();
  }
}
