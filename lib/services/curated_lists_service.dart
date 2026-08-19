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
  });

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
  Future<CuratedList?> loadList(String listId) async {
    // Check cache first
    if (_listsCache.containsKey(listId)) {
      return _listsCache[listId];
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
      try {
        final listYaml = await rootBundle.loadString(
          'assets/curated_lists/$dir/$listId.yml',
        );
        final parsed = loadYaml(listYaml) as YamlMap;
        final list = CuratedList.fromYaml(parsed);
        _listsCache[listId] = list;
        return list;
      } catch (_) {
        // File not found in this directory, try next
        continue;
      }
    }

    return null;
  }

  /// Load all lists for a given category.
  Future<List<CuratedList>> loadListsForCategory(
    CuratedCategory category,
  ) async {
    final lists = <CuratedList>[];

    for (final listId in category.listIds) {
      final list = await loadList(listId);
      if (list != null) {
        lists.add(list);
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
