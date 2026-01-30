import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/curated_lists_service.dart';
import '../../services/api_service.dart';
import '../../services/collection_import_service.dart';
import '../../services/translation_service.dart';

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
  String _profileType = 'individual';

  @override
  void initState() {
    super.initState();
    _loadProfileAndCategories();
  }

  Future<void> _loadProfileAndCategories() async {
    // Load profile type first to determine category ordering
    final prefs = await SharedPreferences.getInstance();
    _profileType = prefs.getString('ffi_profile_type') ?? 'individual';
    await _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      var categories = await _curatedService.loadCategories();

      // Prioritize jeunesse category for kid profiles
      if (_profileType == 'kid') {
        categories = _prioritizeCategory(categories, 'jeunesse');
      }

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

  /// Move a specific category to the front of the list
  List<CuratedCategory> _prioritizeCategory(
    List<CuratedCategory> categories,
    String categoryId,
  ) {
    final index = categories.indexWhere((c) => c.id == categoryId);
    if (index > 0) {
      final category = categories.removeAt(index);
      categories.insert(0, category);
    }
    return categories;
  }

  Future<void> _selectCategory(String categoryId) async {
    setState(() {
      _selectedCategoryId = categoryId;
      _isLoading = true;
    });

    final category = _categories.firstWhere((c) => c.id == categoryId);
    final lists = await _curatedService.loadListsForCategory(category);

    if (mounted) {
      setState(() {
        _currentLists = lists;
        _isLoading = false;
      });
    }
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

                // Lists
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _currentLists.isEmpty
                      ? const Center(
                          child: Text('Aucune liste dans cette catégorie'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _currentLists.length,
                          itemBuilder: (context, index) {
                            final list = _currentLists[index];
                            return _buildListCard(list, langCode);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildListCard(CuratedList list, String langCode) {
    final title = list.getTitle(langCode);
    final description = list.getDescription(langCode);

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
                Text(
                  'Contient ${list.books.length} livres',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),

                // Preview first 3 books (show note if available)
                ...list.books
                    .take(3)
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
                                b.note ?? b.isbn,
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
                    padding: const EdgeInsets.only(left: 24, top: 4),
                    child: Text(
                      '+ ${list.books.length - 3} autres...',
                      style: Theme.of(context).textTheme.bodySmall,
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
