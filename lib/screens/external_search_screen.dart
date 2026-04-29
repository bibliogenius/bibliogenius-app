import 'package:flutter/material.dart';
import '../widgets/genie_app_bar.dart';

import '../widgets/plus_one_animation.dart';
import '../widgets/work_edition_card.dart';
import '../widgets/search_result_card.dart';
import '../widgets/shimmer_loading.dart';
import 'package:provider/provider.dart';
import '../data/repositories/copy_repository.dart';
import '../services/api_service.dart';
import '../services/ffi_service.dart';
import '../services/translation_service.dart';
import '../providers/theme_provider.dart';
import '../providers/book_refresh_notifier.dart';
import '../providers/flash_message_provider.dart';
import '../providers/hub_directory_provider.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_design.dart';

import '../utils/book_url_helper.dart';
import '../utils/language_constants.dart';
import 'web_view_screen.dart';

class ExternalSearchScreen extends StatefulWidget {
  const ExternalSearchScreen({super.key});

  @override
  State<ExternalSearchScreen> createState() => _ExternalSearchScreenState();
}

class _ExternalSearchScreenState extends State<ExternalSearchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _subjectController = TextEditingController();

  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _groupedWorks = [];
  bool _isSearching = false;
  String? _error;
  bool _booksAdded = false;
  bool _showAdvancedFilters = false; // Collapsed by default on mobile
  bool _useCarouselView = true; // Carousel view by default

  // Source filter (upstream - before search)
  String?
  _upstreamSource; // null = all sources, "inventaire", "bnf", "openlibrary"

  // Dynamic source options based on enabled sources in profile
  List<Map<String, dynamic>> _sourceOptions = [];
  bool _sourcesLoaded = false;
  bool _initialSearchDone = false;
  // Whether the user has a Google Books API key set. When false the chip
  // shows a "no API key" badge and a SnackBar warns on selection (Google's
  // anonymous quota saturates within a few requests).
  bool _googleBooksHasApiKey = false;

  // Language filter (defaults to user's reading languages)
  // _selectedLanguage: null = "my languages" (all userLanguages sent as comma-separated)
  // _selectedLanguage: '*' = "all languages" (no lang param, no prioritization)
  // _selectedLanguage: 'fr' etc. = specific single language
  String? _selectedLanguage;

  Set<String> _availableSources =
      {}; // Populated from search results for post-filtering

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_sourcesLoaded) {
      // Default: null = "My languages" (all userLanguages)
      _loadEnabledSources();
    }

    if (!_initialSearchDone) {
      final state = GoRouterState.of(context);
      if (state.uri.queryParameters.containsKey('q')) {
        final q = state.uri.queryParameters['q'];
        if (q != null && q.isNotEmpty) {
          _initialSearchDone = true;
          // Heuristic: If q contains ' - ', split into Author/Title?
          // For now, put it all in Author if it looks like an Author search from dashboard
          // The dashboard sends "$author $source" or "$author".
          // Let's put it in the most generic field. Title controller acts as general keyword often?
          // Actually, let's put it in Title controller as "Keywords"
          _titleController.text = q;
          // Trigger search after build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _search();
          });
        }
      }
    }
  }

  Future<void> _loadEnabledSources() async {
    final api = Provider.of<ApiService>(context, listen: false);

    // Defaults — only overridden by entries the user explicitly toggled.
    bool inventaireEnabled = true;
    bool openLibraryEnabled = true;
    // BNF: enabled by default only for French users.
    final deviceLang = Localizations.localeOf(context).languageCode;
    bool bnfEnabled = deviceLang == 'fr';
    // Google Books: opt-in.
    bool googleBooksEnabled = false;

    bool googleBooksHasApiKey = false;

    if (api.useFfi) {
      // FFI mode: getUserStatus is mapped from gamification_get_status and
      // does NOT carry fallback_preferences. Read the toggles from the
      // dedicated FFI accessor — same source of truth as the settings screen.
      try {
        final settings = await FfiService().getSearchSettings();
        final prefs = settings.fallbackPreferences;
        if (prefs.containsKey('inventaire')) {
          inventaireEnabled = prefs['inventaire']!;
        }
        if (prefs.containsKey('openlibrary')) {
          openLibraryEnabled = prefs['openlibrary']!;
        }
        if (prefs.containsKey('bnf')) {
          bnfEnabled = prefs['bnf']!;
        }
        if (prefs.containsKey('google_books')) {
          googleBooksEnabled = prefs['google_books']!;
        }
        googleBooksHasApiKey =
            (settings.apiKeys['google_books'] ?? '').isNotEmpty;
      } catch (e) {
        debugPrint('FFI getSearchSettings failed (using defaults): $e');
      }
    } else {
      // HTTP mode (web): /api/user/status carries the full config including
      // fallback_preferences and (legacy) enabled_modules.
      try {
        final statusRes = await api.getUserStatus();
        if (statusRes.statusCode == 200 && statusRes.data != null) {
          final config = statusRes.data['config'] ?? {};
          final prefs = config['fallback_preferences'] ?? {};

          if (prefs.containsKey('inventaire')) {
            inventaireEnabled = prefs['inventaire'] == true;
          }
          if (prefs.containsKey('openlibrary')) {
            openLibraryEnabled = prefs['openlibrary'] == true;
          }
          if (prefs.containsKey('bnf')) {
            bnfEnabled = prefs['bnf'] == true;
          }

          if (prefs.containsKey('google_books')) {
            googleBooksEnabled = prefs['google_books'] == true;
          } else {
            // Legacy fallback: pre-`fallback_preferences` installs only had
            // `enable_google_books` in the modules list.
            final modules = config['enabled_modules'];
            if (modules is List) {
              googleBooksEnabled = modules.contains('enable_google_books');
            } else if (modules is String) {
              googleBooksEnabled = modules.contains('enable_google_books');
            }
          }

          final apiKeys = config['api_keys'];
          if (apiKeys is Map) {
            final gbKey = apiKeys['google_books']?.toString() ?? '';
            googleBooksHasApiKey = gbKey.isNotEmpty;
          }
        }
      } catch (e) {
        debugPrint('HTTP getUserStatus failed (using defaults): $e');
      }
    }

    // Build source options list based on enabled sources
    final options = <Map<String, dynamic>>[
      {
        'value': null,
        'label': TranslationService.translate(context, 'source_filter_all'),
      },
    ];

    if (inventaireEnabled) {
      options.add({'value': 'inventaire', 'label': 'Inventaire.io'});
    }
    if (openLibraryEnabled) {
      options.add({'value': 'openlibrary', 'label': 'Open Library'});
    }
    if (bnfEnabled) {
      options.add({'value': 'bnf', 'label': 'BNF'});
    }
    if (googleBooksEnabled) {
      options.add({'value': 'google_books', 'label': 'Google Books'});
    }

    if (mounted) {
      setState(() {
        _sourceOptions = options;
        _sourcesLoaded = true;
        _googleBooksHasApiKey = googleBooksHasApiKey;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  /// Normalize a title for grouping purposes
  String _normalizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '') // Remove punctuation
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();
  }

  /// Check if a book's language matches the user's preferred language
  /// Handles various language code formats (2-letter, 3-letter, full names)
  bool _langMatches(String bookLang, String userLang) {
    if (bookLang.isEmpty || userLang.isEmpty) return false;

    // Strip country/region codes (e.g. "pt-BR" → "pt") before matching
    final b = bookLang.split(RegExp(r'[-_]')).first.toLowerCase();
    final u = userLang.split(RegExp(r'[-_]')).first.toLowerCase();

    if (b == u) return true;

    // Common language code mappings
    const langMap = {
      'fr': ['fre', 'fra', 'french', 'français'],
      'en': ['eng', 'english'],
      'es': ['spa', 'spanish', 'español'],
      'de': ['ger', 'deu', 'german', 'deutsch'],
      'it': ['ita', 'italian', 'italiano'],
      'pt': ['por', 'portuguese', 'português'],
      'nl': ['dut', 'nld', 'dutch', 'nederlands'],
      'ru': ['rus', 'russian'],
      'ja': ['jpn', 'japanese'],
      'zh': ['chi', 'zho', 'chinese'],
    };

    // Check if both codes map to the same language
    for (final entry in langMap.entries) {
      final codes = [entry.key, ...entry.value];
      if (codes.contains(b) && codes.contains(u)) {
        return true;
      }
    }

    return false;
  }

  /// Group search results by work (title + author combination)
  List<Map<String, dynamic>> _groupResultsByWork(
    List<Map<String, dynamic>> results,
  ) {
    final Map<String, Map<String, dynamic>> workMap = {};

    // Normalize author for grouping: extract last name to handle format
    // differences across sources ("Jean-Paul Sartre" vs "Sartre, Jean-Paul")
    String normalizeAuthorForGrouping(String author) {
      final a = author.toLowerCase().trim();
      if (a.isEmpty) return '';
      // If "Last, First" format, take part before comma
      if (a.contains(',')) return a.split(',').first.trim();
      // Otherwise take last word (surname)
      final parts = a.split(RegExp(r'\s+'));
      return parts.last;
    }

    for (final book in results) {
      final title = book['title'] as String? ?? '';
      final author = book['author'] as String? ?? '';
      final normalizedTitle = _normalizeTitle(title);
      final normalizedAuthor = normalizeAuthorForGrouping(author);

      // Create a key from normalized title and author surname
      final workKey = '$normalizedTitle|$normalizedAuthor';

      if (workMap.containsKey(workKey)) {
        // Add to existing work's editions
        (workMap[workKey]!['editions'] as List).add(book);
      } else {
        // Create new work entry
        workMap[workKey] = {
          'work_id': workKey,
          'title': title,
          'author': author.isNotEmpty ? author : null,
          'editions': [book],
        };
      }
    }

    // Cross-language work merging: merge works by the same author whose titles
    // are translations of each other (e.g. "El túnel" and "Le tunnel" by Sabato).
    // Compare significant words with fuzzy matching.
    {
      final keys = workMap.keys.toList();
      final mergedInto = <String, String>{}; // key -> target key
      for (int i = 0; i < keys.length; i++) {
        if (mergedInto.containsKey(keys[i])) continue;
        final partsI = keys[i].split('|');
        final authorI = partsI.length > 1 ? partsI[1] : '';
        if (authorI.isEmpty) continue;
        for (int j = i + 1; j < keys.length; j++) {
          if (mergedInto.containsKey(keys[j])) continue;
          final partsJ = keys[j].split('|');
          final authorJ = partsJ.length > 1 ? partsJ[1] : '';
          // Same author surname
          if (authorI != authorJ) continue;
          // Fuzzy title match on significant words
          final titleI = partsI[0];
          final titleJ = partsJ[0];
          final wordsI = titleI
              .split(RegExp(r'\s+'))
              .where((w) => w.length > 2)
              .toList();
          final wordsJ = titleJ
              .split(RegExp(r'\s+'))
              .where((w) => w.length > 2)
              .toList();
          if (wordsI.isEmpty || wordsJ.isEmpty) continue;
          // Check if the shorter set of words fuzzy-matches the longer
          final shorter = wordsI.length <= wordsJ.length ? wordsI : wordsJ;
          final longer = wordsI.length <= wordsJ.length ? wordsJ : wordsI;
          final allMatch = shorter.every(
            (sw) => longer.any((lw) {
              if (sw == lw) return true;
              // Simple char-level similarity for cross-language title words
              int common = 0;
              for (int c = 0; c < sw.length && c < lw.length; c++) {
                if (sw[c] == lw[c]) common++;
              }
              return common / (sw.length > lw.length ? sw.length : lw.length) >
                  0.7;
            }),
          );
          if (allMatch) {
            // Merge j into i: pick the work with best relevance as target
            final editionsI = (workMap[keys[i]]!['editions'] as List)
                .cast<Map<String, dynamic>>();
            final editionsJ = (workMap[keys[j]]!['editions'] as List)
                .cast<Map<String, dynamic>>();
            final bestI = editionsI.fold<int>(0, (best, e) {
              final s = (e['relevance_score'] as num?)?.toInt() ?? 0;
              return s > best ? s : best;
            });
            final bestJ = editionsJ.fold<int>(0, (best, e) {
              final s = (e['relevance_score'] as num?)?.toInt() ?? 0;
              return s > best ? s : best;
            });
            final targetKey = bestI >= bestJ ? keys[i] : keys[j];
            final sourceKey = targetKey == keys[i] ? keys[j] : keys[i];
            (workMap[targetKey]!['editions'] as List).addAll(
              workMap[sourceKey]!['editions'] as List,
            );
            mergedInto[sourceKey] = targetKey;
          }
        }
      }
      for (final key in mergedInto.keys) {
        workMap.remove(key);
      }
    }

    // Sort editions within each work using a quality score
    // Score: language match (100) + cover (80) + publisher (20) + ISBN (10)
    // Language priority: use selected language if set, otherwise all user reading languages
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final List<String> langsForSorting;
    if (_selectedLanguage == null) {
      // "My languages": match any user reading language
      langsForSorting = themeProvider.userLanguages;
    } else if (_selectedLanguage == '*') {
      // "All languages": no language prioritization
      langsForSorting = [];
    } else {
      // Specific language
      langsForSorting = [_selectedLanguage!];
    }

    int editionScore(Map<String, dynamic> edition) {
      int score = 0;

      // Language match is top priority
      if (langsForSorting.isNotEmpty) {
        final lang = (edition['language'] as String?)?.toLowerCase() ?? '';
        if (lang.isNotEmpty &&
            langsForSorting.any((ul) => _langMatches(lang, ul))) {
          score += 100;
        } else if (lang.isNotEmpty) {
          score -= 50; // Penalty for explicit non-matching language
        }
      }

      // Metadata completeness - cover is important for visual display
      if ((edition['cover_url'] as String?)?.isNotEmpty == true) score += 80;
      if ((edition['isbn'] as String?)?.isNotEmpty == true) score += 10;

      // Publisher scoring: reward good publishers, penalize self-publishing
      final publisher =
          (edition['publisher'] as String?)?.toLowerCase().trim() ?? '';
      if (publisher.isNotEmpty) {
        // Heavy penalty for self-publishing platforms (low metadata quality)
        if (publisher.contains('createspace') ||
            publisher.contains('independently published') ||
            publisher.contains('autopublié') ||
            publisher.contains('auto-édition') ||
            publisher.contains('lulu.com') ||
            publisher.contains('kindle direct')) {
          score -= 150; // Strong penalty to push after real publishers
        } else {
          score += 20; // Bonus for having a legitimate publisher
        }
      }

      // De-prioritize Google Books (tie-breaker for same quality)
      if ((edition['source'] as String?) == 'Google') score -= 25;

      return score;
    }

    // Normalize ISBN: strip dashes, reduce ISBN-13 to ISBN-10 core for matching
    // ISBN-13 "978-2-07-036024-8" and ISBN-10 "2-07-036024-X" share digits 4..12
    String normalizeIsbn(String raw) {
      final digits = raw.replaceAll(RegExp(r'[^0-9Xx]'), '');
      if (digits.length == 13 && digits.startsWith('978')) {
        return digits.substring(3, 12); // 9 shared digits (drop prefix + check)
      }
      if (digits.length == 10) {
        return digits.substring(0, 9); // 9 digits (drop check digit)
      }
      return digits;
    }

    // Helper to create unique keys for deduplication.
    // Returns a list: ISBN key + cover key (both checked independently)
    List<String> editionKeys(Map<String, dynamic> edition) {
      final keys = <String>[];
      final isbn = (edition['isbn'] as String?)?.trim() ?? '';
      if (isbn.isNotEmpty && isbn.length >= 10) {
        keys.add('isbn:${normalizeIsbn(isbn)}');
      }
      // Cover URL as secondary dedup key (same visual = same edition in carousel)
      final cover = (edition['cover_url'] as String?)?.trim() ?? '';
      if (cover.isNotEmpty) {
        keys.add('cover:$cover');
      }
      // Fallback: visual attributes for editions without ISBN or cover
      if (keys.isEmpty) {
        final title = (edition['title'] as String?)?.toLowerCase().trim() ?? '';
        final publisher =
            (edition['publisher'] as String?)?.toLowerCase().trim() ?? '';
        final year = edition['publication_year']?.toString() ?? '';
        keys.add('visual:$title|$publisher|$year');
      }
      return keys;
    }

    for (final work in workMap.values) {
      final editions = (work['editions'] as List).cast<Map<String, dynamic>>();

      // Sort first
      editions.sort((a, b) {
        final scoreA = editionScore(a);
        final scoreB = editionScore(b);

        // Higher score comes first
        if (scoreA != scoreB) return scoreB.compareTo(scoreA);

        // Tie-breaker: publication year (newest first)
        final yearA = a['publication_year'] as int?;
        final yearB = b['publication_year'] as int?;
        if (yearA == null && yearB == null) return 0;
        if (yearA == null) return 1;
        if (yearB == null) return -1;
        return yearB.compareTo(yearA);
      });

      // Then deduplicate: keep first occurrence (best quality) of each unique edition.
      // An edition is duplicate if ANY of its keys (ISBN, cover URL) was already seen.
      final seenKeys = <String>{};
      editions.removeWhere((edition) {
        final keys = editionKeys(edition);
        final isDuplicate = keys.any((k) => seenKeys.contains(k));
        if (isDuplicate) {
          return true; // Remove duplicate
        }
        seenKeys.addAll(keys);
        return false; // Keep first occurrence
      });
    }

    // Sort works by combining:
    // - Backend relevance_score (includes fuzzy matching, notoriety, stop-words,
    //   accent folding, language - computed once in Rust, no duplication here)
    // - Flutter-side language check (for post-search UI filter changes)
    // - Edition quality (cover, publisher - UI concerns)
    final worksList = workMap.values.toList();

    /// Best relevance_score among a work's editions (from Rust backend).
    int bestRelevanceScore(List<Map<String, dynamic>> editions) {
      int best = 0;
      for (final ed in editions) {
        final s = (ed['relevance_score'] as num?)?.toInt() ?? 0;
        if (s > best) best = s;
      }
      return best;
    }

    // Debug: log scores before sorting
    debugPrint('🔄 SORTING WORKS v2 (langs=$langsForSorting):');
    for (final work in worksList.take(5)) {
      final editions = (work['editions'] as List).cast<Map<String, dynamic>>();
      if (editions.isNotEmpty) {
        final bestEd = editions.first;
        final lang = bestEd['language'] ?? 'NULL';
        final rs = bestRelevanceScore(editions);
        debugPrint('  📖 "${work['title']}" → lang=$lang, relevance=$rs');
      }
    }

    worksList.sort((a, b) {
      final editionsA = (a['editions'] as List).cast<Map<String, dynamic>>();
      final editionsB = (b['editions'] as List).cast<Map<String, dynamic>>();

      // Backend relevance score is the primary signal (includes notoriety,
      // title match, language as a soft signal - all computed in Rust)
      final rsA = bestRelevanceScore(editionsA);
      final rsB = bestRelevanceScore(editionsB);

      // Language match adds a soft bonus (not a hard partition), so a famous
      // book in another language can still rank above an obscure local match
      int effectiveA = rsA;
      int effectiveB = rsB;
      if (langsForSorting.isNotEmpty) {
        int qualityA = 0;
        int qualityB = 0;
        if (editionsA.isNotEmpty) qualityA = editionScore(editionsA.first);
        if (editionsB.isNotEmpty) qualityB = editionScore(editionsB.first);
        if (qualityA >= 100) effectiveA += 80;
        if (qualityB >= 100) effectiveB += 80;
      }

      if (effectiveA != effectiveB) return effectiveB.compareTo(effectiveA);

      // Tie-breaker: edition quality (cover, publisher)
      int qualityA = 0;
      int qualityB = 0;
      if (editionsA.isNotEmpty) qualityA = editionScore(editionsA.first);
      if (editionsB.isNotEmpty) qualityB = editionScore(editionsB.first);
      return qualityB.compareTo(qualityA);
    });

    return worksList;
  }

  Future<void> _search() async {
    // Guard: prevent concurrent searches (a 2nd call would overwrite the 1st
    // results with partial data from a slower/filtered response).
    if (_isSearching) {
      debugPrint(
        '⚠️ _search() blocked: already searching (source=$_upstreamSource)',
      );
      return;
    }

    if (_titleController.text.isEmpty &&
        _authorController.text.isEmpty &&
        _subjectController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.translate(context, 'enter_search_term'),
          ),
        ),
      );
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
      _searchResults = [];
      _groupedWorks = [];
    });

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      // Language handling:
      // - null ("My languages") → send all userLanguages comma-separated
      // - '*' ("All languages") → don't send lang param (no prioritization)
      // - specific code ("fr") → send that single language
      // Backend uses lang param for relevance scoring, not strict filtering
      String? langForApi;
      if (_selectedLanguage == null) {
        // "My languages": send all reading languages
        langForApi = themeProvider.userLanguages.join(',');
      } else if (_selectedLanguage == '*') {
        // "All languages": no language prioritization
        langForApi = null;
      } else {
        // Specific language selected
        langForApi = _selectedLanguage;
      }

      // Use unified search (Inventaire + OpenLibrary + BNF)
      final results = await api.searchBooks(
        title: _titleController.text,
        author: _authorController.text,
        subject: _subjectController.text,
        lang:
            langForApi, // Used for relevance boosting (user's preferred language)
        source: _upstreamSource, // Filter to specific source(s)
      );

      // Extract available sources from results
      final sources = results
          .map((r) => r['source'] as String?)
          .where((s) => s != null && s.isNotEmpty)
          .cast<String>()
          .toSet();

      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _groupedWorks = _groupResultsByWork(results);
        _availableSources = sources;
        // Debug: Print grouping info
        debugPrint('🔍 Search returned ${results.length} results');
        debugPrint('📚 Grouped into ${_groupedWorks.length} works');
        debugPrint(
          '🌐 Lang filter: $_selectedLanguage | User langs: ${themeProvider.userLanguages}',
        );
        debugPrint('🗂️ Sources: $sources');
        for (final work in _groupedWorks.take(5)) {
          final editions = work['editions'] as List;
          debugPrint('  - "${work['title']}": ${editions.length} edition(s)');
          for (final ed in editions.take(2)) {
            debugPrint(
              '    > Lang: ${ed['language'] ?? 'NULL'} | Pub: ${ed['publisher']}',
            );
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            '${TranslationService.translate(context, 'search_failed')}: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _addBook(Map<String, dynamic> doc) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      debugPrint('🔍 _addBook called with doc: $doc');
      final isbn = doc['isbn'] as String?;

      if (isbn == null || isbn.isEmpty) {
        debugPrint('⚠️ WARNING: Adding book with NULL or EMPTY ISBN!');
      } else {
        debugPrint('✅ ISBN found in doc: "$isbn"');
      }

      // Check if ISBN already exists in library
      if (isbn != null && isbn.isNotEmpty) {
        final existingBook = await api.findBookByIsbn(isbn);
        if (existingBook != null && mounted) {
          // Show duplicate dialog
          final action = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      TranslationService.translate(
                        context,
                        'isbn_already_exists',
                      ),
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${existingBook.title}${existingBook.author != null ? '\n${existingBook.author}' : ''}',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: Text(TranslationService.translate(context, 'cancel')),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'view'),
                  icon: const Icon(Icons.visibility),
                  label: Text(
                    TranslationService.translate(context, 'view_existing'),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'copy'),
                  icon: const Icon(Icons.add),
                  label: Text(
                    TranslationService.translate(context, 'add_copy'),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );

          if (action == 'view' && mounted) {
            context.push('/books/${existingBook.id}');
          } else if (action == 'copy' && mounted) {
            final copyRepo = Provider.of<CopyRepository>(
              context,
              listen: false,
            );
            await copyRepo.createCopy({
              'book_id': existingBook.id,
              'status': 'available',
            });
            _booksAdded = true;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  TranslationService.translate(context, 'copy_added'),
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
          return; // Don't create duplicate
        }
      }

      // Map unified search result (Book DTO) to create payload
      final bookData = {
        'title': doc['title'],
        'author': doc['author'], // Already a string in DTO
        // publication_year is int in DTO
        'publication_year': doc['publication_year'],
        'publisher': doc['publisher'],
        'isbn': doc['isbn'],
        'summary': doc['summary'],
        'reading_status': 'to_read',
        'cover_url': doc['cover_url'],
      };

      debugPrint(
        '📚 Creating book with ISBN: ${doc['isbn']} | Title: ${doc['title']}',
      );
      await api.createBook(bookData);

      // Mark as modified so we can refresh the list on return
      _booksAdded = true;

      // Trigger global book list refresh
      if (mounted) {
        context.read<BookRefreshNotifier>().refresh();
        context.read<FlashMessageProvider>().markHasBooks();
        context.read<HubDirectoryProvider>().markCatalogDirty();
      }

      if (mounted) {
        // Mario Bros-style +1 animation! 🎮
        PlusOneAnimation.show(context);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '"${doc['title']}" ${TranslationService.translate(context, 'added_to_library')}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'failed_add_book')}: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _openUrl(Map<String, dynamic> bookData) async {
    final url = BookUrlHelper.getUrl(bookData);
    if (url == null) return;

    final isOnline = await BookUrlHelper.isOnline();
    if (!isOnline && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.translate(context, 'no_internet_connection'),
          ),
        ),
      );
      return;
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WebViewScreen(
            url: url,
            title: bookData['title'] ?? 'Book Details',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        context.pop(_booksAdded);
      },
      child: Scaffold(
        appBar: GenieAppBar(
          title: TranslationService.translate(context, 'external_search_title'),
          leading: IconButton(
            icon: Icon(Icons.adaptive.arrow_back, color: Colors.white),
            tooltip: TranslationService.translate(context, 'back'),
            onPressed: () => context.pop(_booksAdded),
          ),
        ),
        extendBodyBehindAppBar: true,
        body: Container(
          decoration: BoxDecoration(
            gradient: AppDesign.pageGradientForTheme(theme.themeStyle),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Compact search bar - always visible
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Form(
                    key: _formKey,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _titleController,
                            decoration: InputDecoration(
                              hintText: TranslationService.translate(
                                context,
                                'search_placeholder',
                              ),
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              isDense: true,
                            ),
                            textInputAction: TextInputAction.search,
                            onFieldSubmitted: (_) => _search(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Filter toggle button
                        IconButton(
                          icon: Icon(
                            _showAdvancedFilters
                                ? Icons.filter_list_off
                                : Icons.filter_list,
                            color: _showAdvancedFilters
                                ? Theme.of(context).primaryColor
                                : null,
                          ),
                          tooltip: TranslationService.translate(
                            context,
                            'advanced_filters',
                          ),
                          onPressed: () {
                            setState(() {
                              _showAdvancedFilters = !_showAdvancedFilters;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        // Search button
                        FilledButton(
                          onPressed: _isSearching ? null : _search,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          child: _isSearching
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.search),
                        ),
                      ],
                    ),
                  ),
                ),
                // Source filter - only visible when at least 2 sources are enabled
                // (length > 2 because "Toutes les sources" is always included)
                if (_sourcesLoaded && _sourceOptions.length > 2)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _sourceOptions.map((option) {
                          final isSelected = _upstreamSource == option['value'];
                          // Google Books without an API key: visually flag
                          // the chip and warn on selection — anonymous quota
                          // saturates within a few requests.
                          final isGoogleBooksKeyless =
                              option['value'] == 'google_books' &&
                              !_googleBooksHasApiKey;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              avatar: isGoogleBooksKeyless
                                  ? Icon(
                                      Icons.warning_amber_rounded,
                                      size: 16,
                                      color: isSelected
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.onPrimary
                                          : Theme.of(
                                              context,
                                            ).colorScheme.error,
                                    )
                                  : null,
                              tooltip: isGoogleBooksKeyless
                                  ? TranslationService.translate(
                                      context,
                                      'google_books_no_api_key_badge',
                                    )
                                  : null,
                              label: Text(
                                option['label'] as String,
                                style: TextStyle(
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.onPrimary
                                      : Theme.of(context).colorScheme.onSurface,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  fontSize: 13,
                                ),
                              ),
                              selected: isSelected,
                              showCheckmark: false,
                              onSelected: (_) {
                                final newSource =
                                    option['value'] as String?;
                                setState(() => _upstreamSource = newSource);
                                if (newSource == 'google_books' &&
                                    !_googleBooksHasApiKey) {
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        TranslationService.translate(
                                          context,
                                          'google_books_no_api_key_snackbar',
                                        ),
                                      ),
                                      duration: const Duration(seconds: 5),
                                    ),
                                  );
                                }
                                if (_titleController.text.isNotEmpty ||
                                    _authorController.text.isNotEmpty ||
                                    _subjectController.text.isNotEmpty) {
                                  _search();
                                }
                              },
                              selectedColor: Theme.of(context).primaryColor,
                              backgroundColor: Theme.of(context).cardColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                  color: isSelected
                                      ? Colors.transparent
                                      : Theme.of(context).dividerColor,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                // Collapsible advanced filters
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _authorController,
                          decoration: InputDecoration(
                            labelText: TranslationService.translate(
                              context,
                              'author_label',
                            ),
                            prefixIcon: const Icon(Icons.person, size: 20),
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            isDense: true,
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _subjectController,
                          decoration: InputDecoration(
                            labelText: TranslationService.translate(
                              context,
                              'subject_label',
                            ),
                            prefixIcon: const Icon(Icons.category, size: 20),
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            isDense: true,
                          ),
                          onFieldSubmitted: (_) => _search(),
                        ),
                        const SizedBox(height: 8),
                        // Language filter dropdown (dynamic from userLanguages)
                        Builder(
                          builder: (context) {
                            final userLangs = Provider.of<ThemeProvider>(
                              context,
                            ).userLanguages;
                            // Build dynamic language options:
                            // 1. null = "My languages" (default, all reading languages)
                            // 2. Each individual reading language
                            // 3. '*' = "All languages" (no prioritization)
                            final langOptions = <Map<String, dynamic>>[
                              {
                                'value': null,
                                'label':
                                    TranslationService.translate(
                                      context,
                                      'lang_filter_my_languages',
                                    ) ??
                                    'My languages',
                              },
                              for (final code in userLangs)
                                {
                                  'value': code,
                                  'label': kLanguageNativeNames[code] ?? code,
                                },
                              {
                                'value': '*',
                                'label':
                                    TranslationService.translate(
                                      context,
                                      'lang_filter_all',
                                    ) ??
                                    'All languages',
                              },
                            ];
                            // Ensure current selection is valid
                            final validValues = langOptions
                                .map((o) => o['value'] as String?)
                                .toSet();
                            if (!validValues.contains(_selectedLanguage)) {
                              // Reset to default if user removed the selected language from settings
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted)
                                  setState(() => _selectedLanguage = null);
                              });
                            }
                            return DropdownButtonFormField<String?>(
                              value: validValues.contains(_selectedLanguage)
                                  ? _selectedLanguage
                                  : null,
                              decoration: InputDecoration(
                                labelText: TranslationService.translate(
                                  context,
                                  'language_filter',
                                ),
                                prefixIcon: const Icon(
                                  Icons.language,
                                  size: 20,
                                ),
                                border: const OutlineInputBorder(),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                isDense: true,
                              ),
                              items: langOptions.map((option) {
                                return DropdownMenuItem<String?>(
                                  value: option['value'] as String?,
                                  child: Text(option['label'] as String),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() => _selectedLanguage = value);
                                // Auto-trigger search when language is changed
                                if (_titleController.text.isNotEmpty ||
                                    _authorController.text.isNotEmpty ||
                                    _subjectController.text.isNotEmpty) {
                                  _search();
                                }
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  crossFadeState: _showAdvancedFilters
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 200),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                // View mode toggle (only show when results exist)
                if (_searchResults.isNotEmpty && !_isSearching)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${_groupedWorks.length} ${TranslationService.translate(context, 'works') ?? 'œuvres'}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        // View mode toggle
                        Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildViewToggleButton(
                                icon: Icons.view_carousel,
                                isActive: _useCarouselView,
                                onTap: () =>
                                    setState(() => _useCarouselView = true),
                                tooltip:
                                    TranslationService.translate(
                                      context,
                                      'view_carousel',
                                    ) ??
                                    'Carousel',
                              ),
                              _buildViewToggleButton(
                                icon: Icons.view_list,
                                isActive: !(_useCarouselView),
                                onTap: () =>
                                    setState(() => _useCarouselView = false),
                                tooltip:
                                    TranslationService.translate(
                                      context,
                                      'view_list',
                                    ) ??
                                    'Liste',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _isSearching
                      ? const SearchLoadingSkeleton()
                      : _searchResults.isEmpty
                      ? _buildEmptyState()
                      : (_useCarouselView)
                      ? _buildGroupedView()
                      : _buildFlatListView(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewToggleButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isActive
                ? Theme.of(context).primaryColor.withOpacity(0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isActive ? Theme.of(context).primaryColor : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  /// Grouped view with edition cards (Gleeph-style)
  Widget _buildGroupedView() {
    if (_groupedWorks.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView.builder(
      itemCount: _groupedWorks.length,
      itemBuilder: (context, index) {
        final work = _groupedWorks[index];
        final editions = List<Map<String, dynamic>>.from(
          work['editions'] as List,
        );

        return WorkEditionCard(
          workId: work['work_id'] as String,
          title: work['title'] as String,
          author: work['author'] as String?,
          editions: editions,
          onAddBook: _addBook,
          onOpenUrl: _openUrl,
        );
      },
    );
  }

  Widget _buildFlatListView() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final book = _searchResults[index];
        return SearchResultCard(
          book: book,
          onAdd: () => _addBook(book),
          onOpenUrl: () => _openUrl(book),
        );
      },
    );
  }

  /// Green empty state matching NetworkSearchScreen
  Widget _buildEmptyState() {
    // Matching the "Default" theme Teal banner colors from GenieAppBar
    // Gradient there is [Color(0xFF6BB0A9), Color(0xFF5C8C9F)]
    const primaryTeal = Color(0xFF5C8C9F); // Darker shade for text/icon
    const secondaryTeal = Color(0xFF6BB0A9); // Lighter shade for background

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: secondaryTeal.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.search, size: 64, color: primaryTeal),
            ),
            const SizedBox(height: 24),
            Text(
              TranslationService.translate(
                context,
                'feature_search',
              ), // "Rechercher en ligne"
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: primaryTeal,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              TranslationService.translate(
                context,
                'external_search_empty_hint',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
} // End State
