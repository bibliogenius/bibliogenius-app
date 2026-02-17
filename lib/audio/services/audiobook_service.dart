import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/audio_resource.dart';

/// Service for searching and fetching audiobooks from external sources.
///
/// Searches sources in priority order:
/// 1. LibriVox (largest catalog, multi-language)
/// 2. Litteratureaudio.com (French classics, high quality)
/// 3. Internet Archive (fallback, huge but varied quality)
///
/// This service is stateless and can be used standalone or via AudioProvider.
class AudiobookService {
  final Dio _dio;

  // API endpoints
  static const String _librivoxBaseUrl = 'https://librivox.org/api/feed';
  static const String _litteratureAudioBaseUrl =
      'https://www.litteratureaudio.com/wp-json/wp/v2';
  static const String _archiveBaseUrl =
      'https://archive.org/advancedsearch.php';

  // Cache for negative results (avoid re-querying books with no audiobook)
  final Map<String, DateTime> _notFoundCache = {};
  static const Duration _notFoundCacheDuration = Duration(days: 7);

  AudiobookService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ),
          );

  /// Search for an audiobook by book title and author.
  ///
  /// Returns the first match found from any source, or null if not found.
  /// Caches negative results for 7 days to avoid repeated failed queries.
  ///
  /// [preferredLanguage] can be a language code (e.g., 'fr', 'en', 'es') or
  /// full language name (e.g., 'French', 'English'). When set, LibriVox results
  /// will be filtered to prioritize audiobooks in that language.
  Future<AudioResource?> searchByTitleAndAuthor({
    required int bookId,
    required String title,
    String? author,
    String? preferredLanguage,
  }) async {
    final cacheKey = '${title.toLowerCase()}_${author?.toLowerCase() ?? ''}_${preferredLanguage?.toLowerCase() ?? ''}';

    // Check negative result cache
    final cachedNotFound = _notFoundCache[cacheKey];
    if (cachedNotFound != null) {
      if (DateTime.now().difference(cachedNotFound) < _notFoundCacheDuration) {
        debugPrint('[AudiobookService] Cached not-found for: $title (lang: $preferredLanguage)');
        return null;
      } else {
        _notFoundCache.remove(cacheKey);
      }
    }

    // Try LibriVox first
    try {
      final librivoxResult = await _searchLibriVox(
        bookId,
        title,
        author,
        preferredLanguage: preferredLanguage,
      );
      if (librivoxResult != null) {
        debugPrint('[AudiobookService] Found on LibriVox: $title');
        return librivoxResult;
      }
    } catch (e) {
      debugPrint('[AudiobookService] LibriVox error: $e');
    }

    // Try Litteratureaudio.com (French only - skip if user prefers other language)
    final prefLangLower = preferredLanguage?.toLowerCase() ?? '';
    final skipFrench =
        prefLangLower.isNotEmpty &&
        !prefLangLower.contains('fr') &&
        prefLangLower != 'french';

    if (!skipFrench) {
      try {
        final litteratureResult = await _searchLitteratureAudio(
          bookId,
          title,
          author,
        );
        if (litteratureResult != null) {
          debugPrint('[AudiobookService] Found on Litteratureaudio: $title');
          return litteratureResult;
        }
      } catch (e) {
        debugPrint('[AudiobookService] Litteratureaudio error: $e');
      }
    }

    // Try Internet Archive as fallback (always, regardless of language filter)
    try {
      final archiveResult = await _searchInternetArchive(
        bookId,
        title,
        author,
      );
      if (archiveResult != null) {
        debugPrint('[AudiobookService] Found on Internet Archive: $title');
        return archiveResult;
      }
    } catch (e) {
      debugPrint('[AudiobookService] Internet Archive error: $e');
    }

    // Cache negative result
    _notFoundCache[cacheKey] = DateTime.now();
    debugPrint('[AudiobookService] No audiobook found for: $title');
    return null;
  }

  /// Search for audiobooks across multiple languages in parallel.
  ///
  /// For each language, searches LibriVox. Also searches Litterature Audio
  /// if any language is French, and always searches Internet Archive as fallback.
  /// Results are deduplicated by sourceId.
  Future<List<AudioResource>> searchAllLanguages({
    required int bookId,
    required String title,
    String? author,
    required List<String> languages,
  }) async {
    final results = <AudioResource>[];
    final seenSourceIds = <String>{};

    void addIfNew(AudioResource resource) {
      if (seenSourceIds.add(resource.sourceId)) {
        results.add(resource);
      }
    }

    // 1. Search LibriVox in parallel for each language
    final librivoxFutures = languages.map((lang) async {
      try {
        return await _searchLibriVox(
          bookId,
          title,
          author,
          preferredLanguage: lang,
        );
      } catch (e) {
        debugPrint('[AudiobookService] LibriVox error for lang=$lang: $e');
        return null;
      }
    }).toList();

    final librivoxResults = await Future.wait(librivoxFutures);
    for (final result in librivoxResults) {
      if (result != null) addIfNew(result);
    }

    // 2. Search Litterature Audio if any language is French
    final hasFrench = languages.any((lang) {
      final lower = lang.toLowerCase();
      return lower == 'fr' || lower == 'fre' || lower == 'fra' || lower == 'french';
    });
    if (hasFrench) {
      try {
        final result = await _searchLitteratureAudio(bookId, title, author);
        if (result != null) addIfNew(result);
      } catch (e) {
        debugPrint('[AudiobookService] Litteratureaudio error: $e');
      }
    }

    // 3. Always search Internet Archive as fallback (filtered by user languages)
    try {
      final result = await _searchInternetArchive(
        bookId, title, author,
        languages: languages,
      );
      if (result != null) addIfNew(result);
    } catch (e) {
      debugPrint('[AudiobookService] Internet Archive error: $e');
    }

    debugPrint(
      '[AudiobookService] searchAllLanguages: found ${results.length} result(s) for "$title" in languages $languages',
    );
    return results;
  }

  /// Search LibriVox API
  Future<AudioResource?> _searchLibriVox(
    int bookId,
    String title,
    String? author, {
    String? preferredLanguage,
  }) async {
    // Build search query - LibriVox uses separate title and author params
    final normalizedTitle = _normalizeTitle(title);
    final queryParams = <String, dynamic>{
      'title': '^$normalizedTitle',
      'format': 'json',
      'extended': '1',
    };
    if (author != null && author.isNotEmpty) {
      // LibriVox uses last name for author search
      final lastName = _extractLastName(author);
      if (lastName.isNotEmpty) {
        queryParams['author'] = lastName;
      }
    }

    debugPrint('[AudiobookService] LibriVox query: title="^$normalizedTitle"');

    // 1. Try LibriVox with exact match (Title + Author)
    try {
      debugPrint('[AudiobookService] LibriVox try 1: exact match');
      final response = await _dio.get(
        '$_librivoxBaseUrl/audiobooks',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200) {
        final result = await _parseLibriVoxResponse(
          response.data,
          bookId,
          title,
          preferredLanguage: preferredLanguage,
        );
        if (result != null) return result;
      }
    } catch (e) {
      debugPrint('[AudiobookService] LibriVox try 1 error: $e');
    }

    // 2. Try with simplified title (no accents)
    if (_removeDiacritics(normalizedTitle) != normalizedTitle) {
      try {
        debugPrint('[AudiobookService] LibriVox try 2: simplified title');
        queryParams['title'] = _removeDiacritics(normalizedTitle);

        final response = await _dio.get(
          '$_librivoxBaseUrl/audiobooks',
          queryParameters: queryParams,
        );
        if (response.statusCode == 200) {
          final result = await _parseLibriVoxResponse(
            response.data,
            bookId,
            title,
            preferredLanguage: preferredLanguage,
          );
          if (result != null) return result;
        }
      } catch (e) {
        debugPrint('[AudiobookService] LibriVox try 2 error: $e');
      }
    }

    // 3. Try WITHOUT author (sometimes author names differ)
    if (queryParams.containsKey('author')) {
      try {
        debugPrint('[AudiobookService] LibriVox try 3: no author');
        queryParams.remove('author');
        // Reset title to simplified (from step 2) or normalized
        queryParams['title'] = _removeDiacritics(normalizedTitle);

        final response = await _dio.get(
          '$_librivoxBaseUrl/audiobooks',
          queryParameters: queryParams,
        );
        if (response.statusCode == 200) {
          final result = await _parseLibriVoxResponse(
            response.data,
            bookId,
            title,
            preferredLanguage: preferredLanguage,
          );
          if (result != null) return result;
        }
      } catch (e) {
        debugPrint('[AudiobookService] LibriVox try 3 error: $e');
      }
    }

    // 4. Try broad search (first word of title only)
    try {
      final firstWord = normalizedTitle.split(' ').first;
      if (firstWord.length > 3 && firstWord != normalizedTitle) {
        // Only try if first word is substantial and different from full title
        debugPrint(
          '[AudiobookService] LibriVox try 4: broad search "^$firstWord"',
        );
        queryParams.remove('author'); // Ensure author is gone
        queryParams['title'] = '^$firstWord';

        final response = await _dio.get(
          '$_librivoxBaseUrl/audiobooks',
          queryParameters: queryParams,
        );
        if (response.statusCode == 200) {
          final result = await _parseLibriVoxResponse(
            response.data,
            bookId,
            title,
            preferredLanguage: preferredLanguage,
          );
          if (result != null) return result;
        }
      }
    } catch (e) {
      debugPrint('[AudiobookService] LibriVox try 4 error: $e');
    }

    return null;
  }

  Future<AudioResource?> _parseLibriVoxResponse(
    dynamic data,
    int bookId,
    String title, {
    String? preferredLanguage,
  }) async {
    if (data == null) return null;

    // LibriVox returns { books: [...] } or empty string if no results
    Map<String, dynamic>? jsonData;
    if (data is String) {
      if (data.isEmpty) return null;
      try {
        jsonData = jsonDecode(data) as Map<String, dynamic>?;
      } catch (e) {
        return null;
      }
    } else if (data is Map<String, dynamic>) {
      jsonData = data;
    }

    if (jsonData == null) return null;

    final books = jsonData['books'] as List?;
    if (books == null || books.isEmpty) return null;

    // Normalize the search title for comparison
    final normalizedSearchTitle = _normalizeForComparison(title);
    debugPrint('[AudiobookService] Searching for: "$normalizedSearchTitle"');

    // Filter/sort books by preferred language AND title similarity
    Map<String, dynamic>? book;
    if (preferredLanguage != null && preferredLanguage.isNotEmpty) {
      final prefLangLower = preferredLanguage.toLowerCase();

      // Map common language codes to LibriVox language names
      final langMap = {
        'fr': 'french',
        'en': 'english',
        'es': 'spanish',
        'de': 'german',
        'it': 'italian',
        'pt': 'portuguese',
        'nl': 'dutch',
        'ru': 'russian',
        'zh': 'chinese',
        'ja': 'japanese',
      };

      final targetLang = langMap[prefLangLower] ?? prefLangLower;

      // Find book in preferred language that ALSO matches the title
      for (final b in books) {
        if (b is! Map<String, dynamic>) continue;
        final bookLang = (b['language'] as String?)?.toLowerCase() ?? '';
        final bookTitle = b['title'] as String? ?? '';
        final normalizedBookTitle = _normalizeForComparison(bookTitle);

        // Check language match
        final langMatches =
            bookLang.contains(targetLang) || targetLang.contains(bookLang);
        if (!langMatches) continue;

        // Check title similarity - must be a good match, not just partial
        if (_isTitleMatch(normalizedSearchTitle, normalizedBookTitle)) {
          book = b;
          debugPrint(
            '[AudiobookService] Found matching book: "$bookTitle" (lang: $bookLang)',
          );
          break;
        } else {
          debugPrint(
            '[AudiobookService] Skipping non-matching title: "$bookTitle"',
          );
        }
      }

      // If no match in preferred language, don't fallback - return null
      if (book == null) {
        final availableTitles = books
            .whereType<Map<String, dynamic>>()
            .map((b) => b['title'] as String?)
            .where((t) => t != null)
            .toList();
        debugPrint(
          '[AudiobookService] No matching book found. Available titles: $availableTitles',
        );
        return null; // Don't show audiobooks that don't match
      }
    } else {
      // No preferred language specified - find first title match
      for (final b in books) {
        if (b is! Map<String, dynamic>) continue;
        final bookTitle = b['title'] as String? ?? '';
        final normalizedBookTitle = _normalizeForComparison(bookTitle);

        if (_isTitleMatch(normalizedSearchTitle, normalizedBookTitle)) {
          book = b;
          break;
        }
      }
      if (book == null) {
        debugPrint('[AudiobookService] No title match found in results');
        return null;
      }
    }

    // Fetch chapters from RSS if available
    List<AudioChapter>? chapters;
    final rssUrl = book['url_rss'] as String?;
    String? streamUrl;

    if (rssUrl != null && rssUrl.isNotEmpty) {
      debugPrint('[AudiobookService] Fetching RSS for chapters: $rssUrl');
      try {
        chapters = await _fetchLibriVoxChapters(rssUrl);
        // Use first chapter URL as streamUrl if available
        if (chapters.isNotEmpty) {
          streamUrl = chapters.first.url;
          debugPrint(
            '[AudiobookService] Got ${chapters.length} chapters. Stream URL: $streamUrl',
          );
        }
      } catch (e) {
        debugPrint('[AudiobookService] Failed to fetch RSS: $e');
      }
    }

    return AudioResource(
      bookId: bookId,
      source: AudioSource.librivox,
      sourceId: book['id']?.toString() ?? '',
      title: book['title'] as String? ?? title,
      language: book['language'] as String?,
      durationSeconds: _parseLibriVoxDuration(book['totaltimesecs']),
      rssUrl: rssUrl,
      streamUrl: streamUrl,
      narrator: null, // Would need to fetch from RSS
      chapters: chapters,
    );
  }

  Future<List<AudioChapter>> _fetchLibriVoxChapters(String rssUrl) async {
    try {
      final response = await _dio.get(rssUrl);
      if (response.statusCode != 200) return [];

      final xml = response.data.toString();
      final chapters = <AudioChapter>[];

      // Simple regex parsing to avoid adding XML dependency
      // Look for <item> blocks
      final itemRegex = RegExp(r'<item>(.*?)</item>', dotAll: true);
      final titleRegex = RegExp(r'<title>(.*?)</title>', dotAll: true);
      final enclosureRegex = RegExp(r'<enclosure url="(.*?)"', dotAll: true);
      final durationRegex = RegExp(
        r'<itunes:duration>(.*?)</itunes:duration>',
        dotAll: true,
      );

      final matches = itemRegex.allMatches(xml);
      int index = 0;

      for (final match in matches) {
        final itemContent = match.group(1) ?? '';

        final titleMatch = titleRegex.firstMatch(itemContent);
        final urlMatch = enclosureRegex.firstMatch(itemContent);
        final durationMatch = durationRegex.firstMatch(itemContent);

        if (urlMatch != null) {
          String title = titleMatch?.group(1) ?? 'Chapter ${index + 1}';
          // Clean title (remove CDATA if present)
          title = title
              .replaceAll('<![CDATA[', '')
              .replaceAll(']]>', '')
              .trim();

          final url = urlMatch.group(1) ?? '';

          // Parse duration (MM:SS or HH:MM:SS)
          int duration = 0;
          final durationStr = durationMatch?.group(1);
          if (durationStr != null) {
            final parts = durationStr
                .split(':')
                .map((s) => int.tryParse(s) ?? 0)
                .toList();
            if (parts.length == 3) {
              duration = parts[0] * 3600 + parts[1] * 60 + parts[2];
            } else if (parts.length == 2) {
              duration = parts[0] * 60 + parts[1];
            }
          }

          chapters.add(
            AudioChapter(
              id: 'ch_$index',
              title: title,
              url: url,
              durationSeconds: duration,
              index: index,
            ),
          );
          index++;
        }
      }

      return chapters;
    } catch (e) {
      debugPrint('[AudiobookService] RSS parsing error: $e');
      return [];
    }
  }

  /// Search Litteratureaudio.com WordPress API
  Future<AudioResource?> _searchLitteratureAudio(
    int bookId,
    String title,
    String? author,
  ) async {
    final searchQuery = author != null ? '$title $author' : title;

    final response = await _dio.get(
      '$_litteratureAudioBaseUrl/posts',
      queryParameters: {'search': searchQuery, 'per_page': 5},
    );

    if (response.statusCode != 200) return null;

    final data = response.data;
    if (data == null || data is! List || data.isEmpty) return null;

    // Find best match
    final post = _findBestLitteratureMatch(data, title, author);
    if (post == null) return null;

    final meta = post['meta'] as Map<String, dynamic>? ?? {};
    final titleRendered = post['title'] as Map<String, dynamic>?;

    // Debug: print meta contents
    debugPrint('[AudiobookService] post id: ${post['id']}');
    debugPrint(
      '[AudiobookService] stream raw: "${meta['stream']}" (${meta['stream'].runtimeType})',
    );
    debugPrint(
      '[AudiobookService] download_url raw: "${meta['download_url']}" (${meta['download_url'].runtimeType})',
    );

    // Get stream URL (try multiple fields)
    String? streamUrl = meta['stream'] as String?;
    if (streamUrl == null || streamUrl.isEmpty) {
      streamUrl = meta['download_url'] as String?;
    }
    if (streamUrl == null || streamUrl.isEmpty) {
      streamUrl = meta['stream_url'] as String?;
    }

    debugPrint('[AudiobookService] Final streamUrl: $streamUrl');

    // Parse chapters from meta.items
    List<AudioChapter>? chapters;
    final items = meta['items'] as List?;
    if (items != null && items.isNotEmpty) {
      chapters = items.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value.toString();
        // Format: "postId:ChapterTitle"
        final parts = item.split(':');
        final chapterId = parts.isNotEmpty ? parts[0] : item;
        final chapterTitle = parts.length > 1
            ? parts.sublist(1).join(':')
            : 'Chapitre ${idx + 1}';
        return AudioChapter(
          id: chapterId,
          title: chapterTitle,
          url: '', // Need to fetch from individual posts
          index: idx,
        );
      }).toList();
    }

    return AudioResource(
      bookId: bookId,
      source: AudioSource.litteratureaudio,
      sourceId: post['id']?.toString() ?? '',
      title: titleRendered?['rendered'] as String? ?? title,
      language: 'French',
      durationSeconds: _parseDurationMs(meta['duration']),
      streamUrl: streamUrl,
      rssUrl: null,
      narrator: null, // Would need to fetch from voix taxonomy
      chapters: chapters,
    );
  }

  /// Search Internet Archive
  ///
  /// [languages] optional list of ISO 639-1 codes to filter results.
  /// When provided, builds a language filter (e.g. `language:(English OR French)`).
  Future<AudioResource?> _searchInternetArchive(
    int bookId,
    String title,
    String? author, {
    List<String>? languages,
  }) async {
    // Map ISO 639-1 codes to language names used by Internet Archive
    const langNames = {
      'fr': 'French', 'en': 'English', 'es': 'Spanish',
      'de': 'German', 'it': 'Italian', 'pt': 'Portuguese',
      'nl': 'Dutch', 'ru': 'Russian', 'zh': 'Chinese',
      'ja': 'Japanese',
    };

    // Build search query for audio items
    final searchTerms = <String>['title:($title)', 'mediatype:audio'];
    if (author != null && author.isNotEmpty) {
      searchTerms.add('creator:($author)');
    }
    if (languages != null && languages.isNotEmpty) {
      final langFilter = languages
          .map((l) => langNames[l.toLowerCase()] ?? l)
          .join(' OR ');
      searchTerms.add('language:($langFilter)');
    }

    final response = await _dio.get(
      _archiveBaseUrl,
      queryParameters: {
        'q': searchTerms.join(' AND '),
        'output': 'json',
        'rows': 5,
        'fl[]': 'identifier,title,creator,runtime,language',
      },
    );

    if (response.statusCode != 200) return null;

    final data = response.data;
    if (data == null) return null;

    Map<String, dynamic>? jsonData;
    if (data is String) {
      jsonData = jsonDecode(data) as Map<String, dynamic>?;
    } else if (data is Map<String, dynamic>) {
      jsonData = data;
    }

    if (jsonData == null) return null;

    final responseObj = jsonData['response'] as Map<String, dynamic>?;
    final docs = responseObj?['docs'] as List?;
    if (docs == null || docs.isEmpty) return null;

    final doc = docs.first as Map<String, dynamic>;
    final identifier = doc['identifier'] as String?;
    if (identifier == null) return null;

    // Extract language from response
    final docLang = doc['language'] is List
        ? (doc['language'] as List).firstOrNull?.toString()
        : doc['language']?.toString();

    return AudioResource(
      bookId: bookId,
      source: AudioSource.archive,
      sourceId: identifier,
      title: doc['title'] as String? ?? title,
      language: docLang,
      durationSeconds: _parseArchiveRuntime(doc['runtime']),
      streamUrl: 'https://archive.org/details/$identifier',
      rssUrl: null,
      narrator: doc['creator'] as String?,
    );
  }

  /// Fetch chapters for a LibriVox audiobook from its RSS feed
  Future<List<AudioChapter>> fetchLibriVoxChapters(String rssUrl) async {
    try {
      final response = await _dio.get(rssUrl);
      if (response.statusCode != 200) return [];

      // Parse RSS XML - simplified parsing
      final xmlContent = response.data.toString();
      final chapters = <AudioChapter>[];

      // Extract items from RSS
      final itemRegex = RegExp(r'<item>(.*?)</item>', dotAll: true);
      final titleRegex = RegExp(
        r'<title>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</title>',
      );
      final enclosureRegex = RegExp(r'<enclosure[^>]*url="([^"]*)"[^>]*/>');
      final durationRegex = RegExp(
        r'<itunes:duration>(\d+):?(\d+)?:?(\d+)?</itunes:duration>',
      );

      int index = 0;
      for (final match in itemRegex.allMatches(xmlContent)) {
        final itemContent = match.group(1) ?? '';

        final titleMatch = titleRegex.firstMatch(itemContent);
        final enclosureMatch = enclosureRegex.firstMatch(itemContent);
        final durationMatch = durationRegex.firstMatch(itemContent);

        if (enclosureMatch != null) {
          final url = enclosureMatch.group(1) ?? '';
          final title = titleMatch?.group(1)?.trim() ?? 'Chapter ${index + 1}';

          int? durationSeconds;
          if (durationMatch != null) {
            final parts = [
              durationMatch.group(1),
              durationMatch.group(2),
              durationMatch.group(3),
            ].whereType<String>().map(int.parse).toList();

            if (parts.length == 3) {
              durationSeconds = parts[0] * 3600 + parts[1] * 60 + parts[2];
            } else if (parts.length == 2) {
              durationSeconds = parts[0] * 60 + parts[1];
            } else if (parts.length == 1) {
              durationSeconds = parts[0];
            }
          }

          chapters.add(
            AudioChapter(
              id: 'ch_$index',
              title: title,
              url: url,
              durationSeconds: durationSeconds,
              index: index,
            ),
          );
          index++;
        }
      }

      return chapters;
    } catch (e) {
      debugPrint('[AudiobookService] Error fetching chapters: $e');
      return [];
    }
  }

  // Helper methods

  String _removeDiacritics(String str) {
    const withDia =
        'ÀÁÂÃÄÅàáâãäåÒÓÔÕÕÖØòóôõöøÈÉÊËèéêëðÇçÐÌÍÎÏìíîïÙÚÛÜùúûüÑñŠšŸÿýŽž';
    const withoutDia =
        'AAAAAAaaaaaaOOOOOOOooooooEEEEeeeeeCcDIIIIiiiiUUUUuuuuNnSsYyyZz';

    for (int i = 0; i < withDia.length; i++) {
      str = str.replaceAll(withDia[i], withoutDia[i]);
    }
    return str;
  }

  String _normalizeTitle(String title) {
    // Remove common articles for better matching
    return title
        .replaceAll(
          RegExp(r'^(the|a|an|le|la|les|un|une|des)\s+', caseSensitive: false),
          '',
        )
        .trim();
  }

  String _extractLastName(String author) {
    final parts = author.split(' ');
    return parts.isNotEmpty ? parts.last : author;
  }

  int? _parseLibriVoxDuration(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  int? _parseDurationMs(dynamic value) {
    if (value == null) return null;
    if (value is int) return value ~/ 1000;
    if (value is String) {
      final ms = int.tryParse(value);
      return ms != null ? ms ~/ 1000 : null;
    }
    return null;
  }

  int? _parseArchiveRuntime(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      // Format: "HH:MM:SS" or "MM:SS"
      final parts = value.split(':').map((p) => int.tryParse(p) ?? 0).toList();
      if (parts.length == 3) {
        return parts[0] * 3600 + parts[1] * 60 + parts[2];
      } else if (parts.length == 2) {
        return parts[0] * 60 + parts[1];
      }
    }
    return null;
  }

  Map<String, dynamic>? _findBestLitteratureMatch(
    List<dynamic> posts,
    String title,
    String? author,
  ) {
    final normalizedSearchTitle = _normalizeForComparison(title);

    // Helper to check if a post has audio
    bool hasAudio(Map<String, dynamic> post) {
      final meta = post['meta'] as Map<String, dynamic>? ?? {};
      final stream = meta['stream']?.toString() ?? '';
      final downloadUrl = meta['download_url']?.toString() ?? '';
      return stream.isNotEmpty || downloadUrl.isNotEmpty;
    }

    // First pass: find posts with audio that match the title using strict matching
    for (final post in posts) {
      if (post is! Map<String, dynamic>) continue;
      if (!hasAudio(post)) continue;

      final titleRendered = post['title'] as Map<String, dynamic>?;
      final postTitleRaw = titleRendered?['rendered'] as String? ?? '';
      final normalizedPostTitle = _normalizeForComparison(postTitleRaw);

      if (_isTitleMatch(normalizedSearchTitle, normalizedPostTitle)) {
        debugPrint(
          '[AudiobookService] Found match with audio: id=${post['id']}, title=$postTitleRaw',
        );
        return post;
      }
    }

    // Second pass: find title match even without audio (user can open in browser)
    for (final post in posts) {
      if (post is! Map<String, dynamic>) continue;

      final titleRendered = post['title'] as Map<String, dynamic>?;
      final postTitleRaw = titleRendered?['rendered'] as String? ?? '';
      final normalizedPostTitle = _normalizeForComparison(postTitleRaw);

      if (_isTitleMatch(normalizedSearchTitle, normalizedPostTitle)) {
        debugPrint(
          '[AudiobookService] Title match but no stream URL: id=${post['id']}',
        );
        return post;
      }
    }

    // No matching posts found
    debugPrint('[AudiobookService] No matching posts found');
    return null;
  }

  /// Clear the not-found cache (useful for testing or manual refresh)
  void clearCache() {
    _notFoundCache.clear();
  }

  /// Normalize a title for comparison: lowercase, remove diacritics, remove punctuation
  String _normalizeForComparison(String title) {
    var normalized = title.toLowerCase();
    normalized = _removeDiacritics(normalized);
    // Remove common articles (including French l')
    normalized = normalized.replaceAll(
      RegExp(r"^(the|a|an|le|la|les|un|une|des|l')\s*", caseSensitive: false),
      '',
    );
    // Remove punctuation and extra spaces
    normalized = normalized.replaceAll(RegExp(r'[^\w\s]'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  /// Check if two titles match sufficiently
  /// Returns true if:
  /// - One title contains the other completely, OR
  /// - They share significant words (>= 60% overlap)
  bool _isTitleMatch(String searchTitle, String bookTitle) {
    // Exact match
    if (searchTitle == bookTitle) return true;

    // One contains the other (but must be substantial - at least 70% of the shorter one)
    if (searchTitle.contains(bookTitle)) {
      if (bookTitle.length >= searchTitle.length * 0.7) return true;
      // Fall through to word-based matching
    }
    if (bookTitle.contains(searchTitle)) {
      if (searchTitle.length >= bookTitle.length * 0.7) return true;
      // Fall through to word-based matching
    }

    // Word-based matching for cases like "Lettres à un jeune poète" vs "Lettres de mon moulin"
    final searchWords = searchTitle
        .split(' ')
        .where((w) => w.length > 2)
        .toSet();
    final bookWords = bookTitle.split(' ').where((w) => w.length > 2).toSet();

    if (searchWords.isEmpty || bookWords.isEmpty) return false;

    // Count matching words
    final matchingWords = searchWords.intersection(bookWords);
    final totalUniqueWords = searchWords.union(bookWords);

    // Jaccard similarity: matching / total unique words
    final similarity = matchingWords.length / totalUniqueWords.length;

    // For short titles (1-2 significant words), require exact match
    if (searchWords.length <= 2) {
      // All search words must be in the book title
      return matchingWords.length == searchWords.length;
    }

    // For longer titles, require at least 50% word overlap
    final matchRatio = matchingWords.length / searchWords.length;
    debugPrint(
      '[AudiobookService] Title comparison: "$searchTitle" vs "$bookTitle" '
      '- matching: ${matchingWords.length}/${searchWords.length} (${(matchRatio * 100).toInt()}%), '
      'similarity: ${(similarity * 100).toInt()}%',
    );

    return matchRatio >= 0.5 && similarity >= 0.4;
  }
}
