import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/book_repository.dart';
import '../../providers/theme_provider.dart';
import '../../services/curated_lists_service.dart';
import '../../services/api_service.dart';
import '../../services/collection_import_service.dart';
import '../../services/ffi_service.dart';
import '../../services/translation_service.dart';
import '../../utils/language_constants.dart';

class ImportCuratedListScreen extends StatefulWidget {
  const ImportCuratedListScreen({Key? key}) : super(key: key);

  @override
  _ImportCuratedListScreenState createState() =>
      _ImportCuratedListScreenState();
}

class _ImportCuratedListScreenState extends State<ImportCuratedListScreen> {
  final CuratedListsService _curatedService = CuratedListsService.instance;

  bool _isLoading = true;
  bool _isImporting = false;
  List<CuratedCategory> _categories = [];
  String? _selectedCategoryId;
  List<CuratedList> _currentLists = [];
  Set<String> _libraryIsbns = {};
  bool _otherLanguagesExpanded = false;

  /// Cleaned ISBNs of the displayed lists that at least one paired peer or
  /// followed library owns (shared Rust wishlist join, ISBN-only mode).
  Set<String> _networkIsbns = {};

  /// Lists whose card shows every book instead of the 3-book preview.
  final Set<String> _expandedLists = {};

  /// Extract display title from a curated book note.
  /// Notes may contain "Title - Author (Year)" format; return just the title.
  String _displayTitle(CuratedBook b) {
    final note = b.note;
    if (note == null) return b.isbn;
    final dashIdx = note.indexOf(' - ');
    return dashIdx > 0 ? note.substring(0, dashIdx).trim() : note;
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadLibraryIsbns();
  }

  Future<void> _loadLibraryIsbns() async {
    try {
      final bookRepo = Provider.of<BookRepository>(context, listen: false);
      final books = await bookRepo.getBooks();
      final isbns = <String>{};
      for (final book in books) {
        if (book.isbn != null && book.isbn!.isNotEmpty) {
          isbns.add(book.isbn!.replaceAll(RegExp(r'[^0-9X]'), ''));
        }
      }
      if (mounted) {
        setState(() => _libraryIsbns = isbns);
      }
    } catch (e) {
      debugPrint('Error loading library ISBNs: $e');
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _curatedService.loadCategories();

      if (mounted) {
        setState(() {
          _categories = categories;
          _isLoading = false;
          // Auto-select first category
          if (categories.isNotEmpty) {
            _selectCategory(categories.first.id);
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading curated categories: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectCategory(String categoryId) async {
    setState(() {
      _selectedCategoryId = categoryId;
      _isLoading = true;
      // Reset the collapsed state so a newly opened category never shows
      // an old expansion choice that is no longer relevant.
      _otherLanguagesExpanded = false;
    });

    final category = _categories.firstWhere((c) => c.id == categoryId);
    final lists = await _curatedService.loadListsForCategory(category);

    if (mounted) {
      setState(() {
        _currentLists = lists;
        _isLoading = false;
      });
      _loadNetworkAvailability();
    }
  }

  /// Normalize an ISBN the way the backend stores it (digits and X only).
  String _cleanIsbn(String isbn) => isbn.replaceAll(RegExp(r'[^0-9X]'), '');

  /// Query which of the displayed ISBNs are available in the user's
  /// network. Fire-and-forget; no result means no badge (no empty state).
  Future<void> _loadNetworkAvailability() async {
    final ffi = FfiService();
    if (!ffi.isInitialized) return;
    final langCode = _currentLangCode;
    final isbns = <String>{};
    for (final list in _currentLists) {
      for (final book in list.books) {
        final clean = _cleanIsbn(book.getIsbnForLanguage(langCode));
        if (clean.isNotEmpty) isbns.add(clean);
      }
    }
    if (isbns.isEmpty) return;
    final providers = await ffi.getIsbnProviders(isbns.toList());
    if (!mounted || providers.isEmpty) return;
    setState(() => _networkIsbns = providers.map((p) => p.isbn).toSet());
  }

  /// User's preferred reading languages, de-duplicated and normalized.
  /// Combines the explicit `userLanguages` setting with the UI locale so a
  /// user who never opened the language picker still sees relevant content.
  Set<String> _resolveUserLanguages(ThemeProvider theme) {
    return {
      normalizeLanguageCode(theme.locale.languageCode),
      ...theme.userLanguages.map(normalizeLanguageCode),
    };
  }

  /// Map `['fr', 'en']` to `"Français, English"` using native names.
  String _languageLabel(List<String> codes) {
    return codes
        .map((c) => kLanguageNativeNames[c] ?? c.toUpperCase())
        .join(', ');
  }

  String get _currentLangCode {
    final locale = Localizations.localeOf(context);
    return locale.languageCode;
  }

  Future<void> _importList(CuratedList list) async {
    final langCode = _currentLangCode;
    final listTitle = list.getTitle(langCode);

    // DEBUG: Trace title values
    debugPrint('📚 Import DEBUG - list.id: ${list.id}');
    debugPrint('📚 Import DEBUG - langCode: $langCode');
    debugPrint('📚 Import DEBUG - list.title map: ${list.title}');
    debugPrint('📚 Import DEBUG - listTitle (resolved): $listTitle');

    String selectedStatus = 'wanting'; // Default to "Wishlist"

    final String? confirmedStatus = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: Text(
                TranslationService.translate(
                  dialogContext,
                  'import_list_title',
                  params: {'title': listTitle},
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TranslationService.translate(
                      dialogContext,
                      'import_list_desc',
                      params: {'count': list.books.length.toString()},
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    TranslationService.translate(
                      dialogContext,
                      'imported_books_status',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'owned',
                        child: Row(
                          children: [
                            const Icon(Icons.remove_circle_outline, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              TranslationService.translate(
                                dialogContext,
                                'no_reading_status',
                              ),
                            ),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'to_read',
                        child: Row(
                          children: [
                            const Icon(Icons.bookmark_border, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              TranslationService.translate(
                                dialogContext,
                                'to_read_status',
                              ),
                            ),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'wanting',
                        child: Row(
                          children: [
                            const Icon(Icons.favorite_border, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              TranslationService.translate(
                                dialogContext,
                                'wishlist_status',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      setState(() {
                        selectedStatus = val ?? 'owned';
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    selectedStatus == 'wanting'
                        ? TranslationService.translate(
                            dialogContext,
                            'books_added_to_wishlist',
                          )
                        : TranslationService.translate(
                            dialogContext,
                            'copies_created_automatically',
                          ),
                    style: Theme.of(
                      dialogContext,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, null),
                  child: Text(
                    TranslationService.translate(dialogContext, 'cancel'),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, selectedStatus),
                  child: Text(
                    TranslationService.translate(dialogContext, 'import'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmedStatus == null) return; // Dialog was cancelled

    final bool shouldMarkAsOwned = confirmedStatus != 'wanting';
    // 'owned' = no reading status (empty string, will show as "Sans statut" in filters)
    final String readingStatus = confirmedStatus == 'owned'
        ? ''
        : confirmedStatus;

    if (!mounted) return;

    setState(() {
      _isImporting = true;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final importService = CollectionImportService(apiService);

      final result = await importService.importList(
        list: list,
        langCode: langCode,
        readingStatus: readingStatus,
        shouldMarkAsOwned: shouldMarkAsOwned,
      );

      if (!mounted) return;

      // The wishlist-match aggregation for the batch happens inside
      // CollectionImportService.importList, shared with the YAML import.

      if (result.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error')}: ${result.error}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(
                context,
                'collection_created',
                params: {
                  'title': listTitle,
                  'count': result.successCount.toString(),
                },
              ),
            ),
          ),
        );
        Navigator.pop(context, true); // Return true to refresh
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'unexpected_error')}: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  IconData _getIconForCategory(String iconName) {
    switch (iconName) {
      case 'emoji_events':
        return Icons.emoji_events;
      case 'category':
        return Icons.category;
      case 'auto_stories':
        return Icons.auto_stories;
      case 'school':
        return Icons.school;
      case 'menu_book':
        return Icons.menu_book;
      default:
        return Icons.list;
    }
  }

  @override
  Widget build(BuildContext context) {
    final langCode = _currentLangCode;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          TranslationService.translate(context, 'discover_collections'),
        ),
      ),
      body: _isImporting
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    TranslationService.translate(
                      context,
                      'importing_collection',
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Category chips
                if (_categories.isNotEmpty)
                  Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _categories.length,
                      itemBuilder: (context, index) {
                        final category = _categories[index];
                        final isSelected = category.id == _selectedCategoryId;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            selected: isSelected,
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getIconForCategory(category.icon),
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(category.getTitle(langCode)),
                              ],
                            ),
                            onSelected: (_) => _selectCategory(category.id),
                          ),
                        );
                      },
                    ),
                  ),

                // Lists partitioned by user language relevance.
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _currentLists.isEmpty
                      ? Center(
                          child: Text(
                            TranslationService.translate(
                              context,
                              'curated_no_lists',
                            ),
                          ),
                        )
                      : Consumer<ThemeProvider>(
                          builder: (ctx, theme, _) {
                            final partition = partitionCuratedListsByLanguage(
                              _currentLists,
                              _resolveUserLanguages(theme),
                            );
                            return LayoutBuilder(
                              builder: (context, constraints) {
                                final cols = constraints.maxWidth >= 600
                                    ? 2
                                    : 1;
                                return ListView(
                                  padding: const EdgeInsets.all(16),
                                  children: [
                                    if (partition
                                        .inYourLanguages
                                        .isNotEmpty) ...[
                                      _sectionHeader(
                                        TranslationService.translate(
                                          context,
                                          'curated_section_in_your_languages',
                                        ),
                                      ),
                                      ..._gridRows(
                                        partition.inYourLanguages,
                                        langCode,
                                        cols,
                                      ),
                                      const SizedBox(height: 24),
                                    ],
                                    if (partition.otherLanguages.isNotEmpty)
                                      if (partition.inYourLanguages.isEmpty)
                                        // No content in user's languages at
                                        // all: show directly, no collapse
                                        // toggle, so the screen isn't empty.
                                        ..._gridRows(
                                          partition.otherLanguages,
                                          langCode,
                                          cols,
                                        )
                                      else
                                        _buildOtherLanguagesSection(
                                          partition.otherLanguages,
                                          langCode,
                                          cols,
                                        ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  /// Section title used at the top of each language group.
  Widget _sectionHeader(String text) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  /// Build the rows of curated-list cards for either 1 or 2 columns.
  List<Widget> _gridRows(List<CuratedList> lists, String langCode, int cols) {
    final rows = <Widget>[];
    for (var i = 0; i < lists.length; i += cols) {
      if (cols == 1) {
        rows.add(_buildListCard(lists[i], langCode));
      } else {
        rows.add(
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var k = 0; k < cols; k++) ...[
                  if (k > 0) const SizedBox(width: 16),
                  Expanded(
                    child: i + k < lists.length
                        ? _buildListCard(lists[i + k], langCode)
                        : const SizedBox(),
                  ),
                ],
              ],
            ),
          ),
        );
      }
    }
    return rows;
  }

  /// "Other languages" section with a tappable header that toggles
  /// visibility of the underlying grid. Collapsed by default so the user's
  /// relevant content stays above the fold; an affordance hints at how many
  /// lists remain hidden so users know the section is not empty.
  Widget _buildOtherLanguagesSection(
    List<CuratedList> lists,
    String langCode,
    int cols,
  ) {
    final headerText = TranslationService.translate(
      context,
      'curated_section_other_languages',
    );
    final hintText = TranslationService.translate(
      context,
      'curated_other_languages_hint',
      params: {'count': '${lists.length}'},
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          header: true,
          label: headerText,
          child: InkWell(
            onTap: () => setState(
              () => _otherLanguagesExpanded = !_otherLanguagesExpanded,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _otherLanguagesExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headerText,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (!_otherLanguagesExpanded)
                          Text(
                            hintText,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_otherLanguagesExpanded) ..._gridRows(lists, langCode, cols),
      ],
    );
  }

  int _countOwnedBooks(CuratedList list, String langCode) {
    int count = 0;
    for (final book in list.books) {
      final clean = _cleanIsbn(book.getIsbnForLanguage(langCode));
      if (_libraryIsbns.contains(clean)) count++;
    }
    return count;
  }

  /// Books of the list not yet in the library but owned by someone in the
  /// user's network (borrowable instead of bought).
  int _countNetworkBooks(CuratedList list, String langCode) {
    int count = 0;
    for (final book in list.books) {
      final clean = _cleanIsbn(book.getIsbnForLanguage(langCode));
      if (!_libraryIsbns.contains(clean) && _networkIsbns.contains(clean)) {
        count++;
      }
    }
    return count;
  }

  Widget _buildListCard(CuratedList list, String langCode) {
    final title = list.getTitle(langCode);
    final description = list.getDescription(langCode);
    final total = list.books.length;
    final owned = _countOwnedBooks(list, langCode);
    final progress = total > 0 ? owned / total : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (list.coverUrl != null)
            Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: NetworkImage(list.coverUrl!),
                  fit: BoxFit.cover,
                ),
              ),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black54, Colors.transparent],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
                alignment: Alignment.bottomLeft,
                padding: const EdgeInsets.all(16),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (list.coverUrl == null) ...[
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                ],
                Text(description),
                const SizedBox(height: 12),

                // Language badge - indicates which language(s) the books are in.
                if (list.contentLanguages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Semantics(
                      label: _languageLabel(list.contentLanguages),
                      child: Chip(
                        avatar: const Icon(Icons.translate, size: 14),
                        label: Text(
                          _languageLabel(list.contentLanguages),
                          style: const TextStyle(fontSize: 11),
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                      ),
                    ),
                  ),

                // Tags
                if (list.tags.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: list.tags
                        .take(4)
                        .map(
                          (tag) => Chip(
                            label: Text(
                              tag,
                              style: const TextStyle(fontSize: 11),
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                        .toList(),
                  ),

                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          color: owned == total
                              ? Colors.green
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$owned / $total',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  TranslationService.translate(
                    context,
                    'curated_progress_label',
                    params: {'owned': '$owned', 'total': '$total'},
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                // Network availability: shown only when at least one
                // not-yet-owned book has a provider (no empty state).
                if (_countNetworkBooks(list, langCode) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.people,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            TranslationService.translate(
                              context,
                              'curated_import_available_network',
                              params: {
                                'count':
                                    '${_countNetworkBooks(list, langCode)}',
                              },
                            ),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),

                // Preview: 3 books collapsed, every book once unfolded
                // (the "see all" link below toggles).
                ...(_expandedLists.contains(list.id)
                        ? list.books
                        : list.books.take(3))
                    .map(
                      (b) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.book,
                              size: 16,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _displayTitle(b),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                if (list.books.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => setState(() {
                          if (!_expandedLists.add(list.id)) {
                            _expandedLists.remove(list.id);
                          }
                        }),
                        child: Text(
                          _expandedLists.contains(list.id)
                              ? TranslationService.translate(
                                  context,
                                  'curated_see_less',
                                )
                              : TranslationService.translate(
                                  context,
                                  'curated_see_all_books',
                                  params: {'count': '${list.books.length}'},
                                ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _importList(list),
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(
                      TranslationService.translate(context, 'import_list'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
