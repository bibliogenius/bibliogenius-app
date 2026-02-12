import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/collection.dart';

import '../../services/translation_service.dart';
import '../../data/repositories/collection_repository.dart';
import '../../services/api_service.dart';
import '../../providers/theme_provider.dart';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/hierarchical_tag_selector.dart';
import '../../widgets/collection_selector.dart';
import '../../widgets/work_edition_card.dart';

class ImportFromSearchScreen extends StatefulWidget {
  final Collection? initialCollection;

  const ImportFromSearchScreen({super.key, this.initialCollection});

  @override
  State<ImportFromSearchScreen> createState() => _ImportFromSearchScreenState();
}

class _ImportFromSearchScreenState extends State<ImportFromSearchScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();

  // Now using unified search results (Map) instead of OpenLibraryBook
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _groupedWorks = [];
  final Set<int> _selectedIndices = {}; // Track by index for Map results

  List<String> _selectedTags = [];
  List<Collection> _selectedCollections = [];

  bool _isLoading = false;
  bool _isImporting = false;
  bool _importAsOwned = false;
  bool _showOptions = false; // Collapsed by default on mobile
  String? _errorMessage;

  // Source filter
  String? _selectedSource; // null = all sources
  Set<String> _availableSources = {}; // Populated from search results

  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    if (widget.initialCollection != null) {
      _selectedCollections.add(widget.initialCollection!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Provider.of<ThemeProvider>(context, listen: false);
    if (theme.editionBrowserEnabled && _tabController == null) {
      _tabController = TabController(length: 2, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Normalize a title for grouping purposes
  String _normalizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Group search results by work (title + author combination)
  List<Map<String, dynamic>> _groupResultsByWork(
    List<Map<String, dynamic>> results,
  ) {
    final Map<String, Map<String, dynamic>> workMap = {};
    final userLang = Localizations.localeOf(context).languageCode.toLowerCase();

    for (final book in results) {
      final title = book['title'] as String? ?? '';
      final author = book['author'] as String? ?? '';
      final normalizedTitle = _normalizeTitle(title);
      final normalizedAuthor = author.toLowerCase().trim();

      final workKey = '$normalizedTitle|$normalizedAuthor';

      if (workMap.containsKey(workKey)) {
        (workMap[workKey]!['editions'] as List).add(book);
      } else {
        workMap[workKey] = {
          'work_id': workKey,
          'title': title,
          'author': author.isNotEmpty ? author : null,
          'editions': [book],
        };
      }
    }

    // Sort editions: completeness + language first, then year
    for (final work in workMap.values) {
      final editions = work['editions'] as List<Map<String, dynamic>>;
      editions.sort((a, b) {
        final scoreA = _calculateEditionScore(a, userLang);
        final scoreB = _calculateEditionScore(b, userLang);
        if (scoreA != scoreB) return scoreB.compareTo(scoreA);

        final yearA = a['publication_year'] as int?;
        final yearB = b['publication_year'] as int?;
        if (yearA == null && yearB == null) return 0;
        if (yearA == null) return 1;
        if (yearB == null) return -1;
        return yearB.compareTo(yearA);
      });
    }

    // Sort works by best edition score
    final worksList = workMap.values.toList();
    worksList.sort((a, b) {
      final editionsA = a['editions'] as List<Map<String, dynamic>>;
      final editionsB = b['editions'] as List<Map<String, dynamic>>;
      final scoreA = editionsA.isNotEmpty
          ? _calculateEditionScore(editionsA.first, userLang)
          : 0;
      final scoreB = editionsB.isNotEmpty
          ? _calculateEditionScore(editionsB.first, userLang)
          : 0;
      return scoreB.compareTo(scoreA);
    });

    return worksList;
  }

  /// Calculate score for edition sorting (higher = better)
  int _calculateEditionScore(Map<String, dynamic> edition, String userLang) {
    int score = 0;

    if (edition['cover_url'] != null) score += 10;
    if (edition['isbn'] != null) score += 5;
    if (edition['publisher'] != null) score += 3;
    if (edition['publication_year'] != null) score += 2;
    if (edition['summary'] != null &&
        (edition['summary'] as String).isNotEmpty) {
      score += 4;
    }

    // Source bonus - Inventaire often has better French data
    final source = (edition['source'] as String?)?.toLowerCase() ?? '';
    if (source.contains('inventaire')) {
      score += 8; // Inventaire bonus
    }

    // Language boost based on publisher
    final publisher = (edition['publisher'] as String?)?.toLowerCase() ?? '';
    if (userLang == 'fr' &&
        (publisher.contains('gallimard') ||
            publisher.contains('folio') ||
            publisher.contains('poche') ||
            publisher.contains('hachette') ||
            publisher.contains('flammarion') ||
            publisher.contains('seuil') ||
            publisher.contains('actes sud') ||
            publisher.contains('livre de poche'))) {
      score += 15;
    } else if (userLang == 'en' &&
        (publisher.contains('penguin') ||
            publisher.contains('harper') ||
            publisher.contains('random house') ||
            publisher.contains('oxford') ||
            publisher.contains('vintage'))) {
      score += 15;
    }

    return score;
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.length < 3) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _searchResults = [];
      _groupedWorks = [];
      _selectedIndices.clear();
      FocusScope.of(context).unfocus();
    });

    try {
      // Use unified search via ApiService (Inventaire + OpenLibrary)
      final api = Provider.of<ApiService>(context, listen: false);
      final userLang = Localizations.localeOf(context).languageCode;

      final results = await api.searchBooks(query: query, lang: userLang);

      if (mounted) {
        // Extract available sources from results
        final sources = results
            .map((r) => r['source'] as String?)
            .where((s) => s != null && s.isNotEmpty)
            .cast<String>()
            .toSet();

        setState(() {
          _searchResults = results;
          _groupedWorks = _groupResultsByWork(results);
          _availableSources = sources;
          _selectedSource = null; // Reset filter on new search
          _isLoading = false;
          if (results.isEmpty) {
            _errorMessage = TranslationService.translate(context, 'no_results');
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              '${TranslationService.translate(context, 'search_failed')}: $e';
        });
      }
    }
  }

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  /// Add a single book from the edition browser
  Future<void> _addBookFromEdition(Map<String, dynamic> editionData) async {
    setState(() => _isImporting = true);

    final apiService = Provider.of<ApiService>(context, listen: false);
    final collectionRepo = Provider.of<CollectionRepository>(context, listen: false);

    try {
      final bookData = {
        'title': editionData['title'],
        'author': editionData['author'],
        'isbn': editionData['isbn'],
        'publisher': editionData['publisher'],
        'publication_year': editionData['publication_year'],
        'cover_url': editionData['cover_url'],
        'summary': editionData['summary'],
        'reading_status': _importAsOwned ? 'to_read' : 'wanting',
        'owned': _importAsOwned,
        'subjects': _selectedTags.map((t) => t.split(' > ').last).toList(),
      };

      final response = await apiService.createBook(bookData);
      int? bookId;

      if (response.statusCode == 201) {
        final data = response.data;
        if (data is Map && data.containsKey('book')) {
          bookId = data['book']['id'];
        } else {
          bookId = data['id'];
        }
      }

      if (bookId != null) {
        for (final collection in _selectedCollections) {
          try {
            if (collection.id.isNotEmpty) {
              await collectionRepo.addBookToCollection(collection.id, bookId);
            }
          } catch (e) {
            debugPrint('Failed to add to collection ${collection.name}: $e');
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '"${editionData['title']}" ${TranslationService.translate(context, 'added_to_library')}',
            ),
            backgroundColor: Colors.green,
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
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _importSelected() async {
    if (_selectedIndices.isEmpty) return;

    setState(() => _isImporting = true);

    final apiService = Provider.of<ApiService>(context, listen: false);
    final collectionRepo = Provider.of<CollectionRepository>(context, listen: false);
    int successCount = 0;
    int failCount = 0;

    for (final index in _selectedIndices) {
      final book = _searchResults[index];
      try {
        int? bookId;

        final bookData = {
          'title': book['title'],
          'author': book['author'],
          'isbn': book['isbn'],
          'publisher': book['publisher'],
          'publication_year': book['publication_year'],
          'cover_url': book['cover_url'],
          'summary': book['summary'],
          'reading_status': _importAsOwned ? 'to_read' : 'wanting',
          'owned': _importAsOwned,
          'subjects': _selectedTags.map((t) => t.split(' > ').last).toList(),
        };

        final response = await apiService.createBook(bookData);

        if (response.statusCode == 201) {
          final data = response.data;
          if (data is Map && data.containsKey('book')) {
            bookId = data['book']['id'];
          } else {
            bookId = data['id'];
          }
        } else {
          final isbn = book['isbn'] as String?;
          if (isbn != null && isbn.isNotEmpty) {
            final existing = await apiService.findBookByIsbn(isbn);
            if (existing != null) {
              bookId = existing.id;
            }
          }

          if (bookId == null) {
            final title = book['title'] as String?;
            if (title != null) {
              final books = await apiService.getBooks(title: title);
              if (books.isNotEmpty) {
                bookId = books.first.id;
              }
            }
          }
        }

        if (bookId != null) {
          successCount++;

          for (final collection in _selectedCollections) {
            try {
              if (collection.id.isNotEmpty) {
                await collectionRepo.addBookToCollection(collection.id, bookId);
              }
            } catch (e) {
              debugPrint('Failed to add to collection ${collection.name}: $e');
            }
          }
        } else {
          failCount++;
          debugPrint('Failed to import/find book: ${book['title']}');
        }
      } catch (e) {
        debugPrint('Error importing ${book['title']}: $e');
        failCount++;
      }
    }

    if (mounted) {
      setState(() => _isImporting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$successCount livres importés. ($failCount échecs)'),
        ),
      );

      if (successCount > 0) {
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final useEditionBrowser = theme.editionBrowserEnabled;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          TranslationService.translate(context, 'external_search_title'),
        ),
        bottom: useEditionBrowser && _tabController != null
            ? TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                tabs: [
                  Tab(
                    text: TranslationService.translate(
                      context,
                      'search_tab_list',
                    ),
                    icon: const Icon(Icons.list),
                  ),
                  Tab(
                    text: TranslationService.translate(
                      context,
                      'search_tab_editions',
                    ),
                    icon: const Icon(Icons.layers),
                  ),
                ],
              )
            : null,
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: TranslationService.translate(
                        context,
                        'search_placeholder',
                      ),
                      hintText: TranslationService.translate(
                        context,
                        'search_hint_example',
                      ),
                      border: const OutlineInputBorder(),
                      suffixIcon: const Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isLoading ? null : _search,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          TranslationService.translate(context, 'search_btn'),
                        ),
                ),
              ],
            ),
          ),

          // Source filter - compact, only shown if multiple sources
          if (_searchResults.isNotEmpty && _availableSources.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_alt_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    TranslationService.translate(context, 'filter_by_source'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<String?>(
                      value: _selectedSource,
                      isExpanded: true,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      hint: Text(
                        TranslationService.translate(context, 'all_sources'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            TranslationService.translate(
                              context,
                              'all_sources',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        ..._availableSources.map(
                          (source) => DropdownMenuItem(
                            value: source,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _getSourceColor(source),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _getSourceFullLabel(source),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _selectedSource = value);
                      },
                    ),
                  ),
                ],
              ),
            ),

          // Collapsible Options Panel
          ExpansionTile(
            title: Text(
              TranslationService.translate(context, 'import_options'),
            ),
            initiallyExpanded: _showOptions,
            onExpansionChanged: (val) => setState(() => _showOptions = val),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 700;
                    final tagSection = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.label_outline, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              TranslationService.translate(context, 'add_tags'),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        HierarchicalTagSelector(
                          selectedTags: _selectedTags,
                          onTagsChanged: (list) {
                            setState(() => _selectedTags = list);
                          },
                        ),
                      ],
                    );

                    final collectionSection = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.collections_bookmark_outlined,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              TranslationService.translate(
                                context,
                                'add_to_collections_label',
                              ),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        CollectionSelector(
                          selectedCollections: _selectedCollections,
                          onChanged: (list) {
                            setState(() => _selectedCollections = list);
                          },
                        ),
                      ],
                    );

                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: tagSection),
                          const SizedBox(width: 32),
                          Expanded(child: collectionSection),
                        ],
                      );
                    } else {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          tagSection,
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),
                          collectionSection,
                        ],
                      );
                    }
                  },
                ),
              ),
            ],
          ),

          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),

          // Control Bar (only for list view)
          if (_searchResults.isNotEmpty &&
              (!useEditionBrowser ||
                  _tabController == null ||
                  _tabController!.index == 0))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text(
                      TranslationService.translate(
                        context,
                        'selected_books_count',
                        params: {'count': _selectedIndices.length.toString()},
                      ),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text(
                      TranslationService.translate(context, 'mark_as_owned'),
                    ),
                    Switch(
                      value: _importAsOwned,
                      onChanged: (val) {
                        setState(() => _importAsOwned = val);
                      },
                    ),
                  ],
                ),
              ),
            ),

          const Divider(),

          // Results Area
          Expanded(
            child: useEditionBrowser && _tabController != null
                ? TabBarView(
                    controller: _tabController,
                    children: [_buildListView(), _buildEditionView()],
                  )
                : _buildListView(),
          ),

          // Import Button (only for list view)
          if (_selectedIndices.isNotEmpty &&
              (!useEditionBrowser ||
                  _tabController == null ||
                  _tabController!.index == 0))
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isImporting ? null : _importSelected,
                    icon: const Icon(Icons.download),
                    label: Text(
                      _isImporting
                          ? 'Importation...'
                          : 'Importer ${_selectedIndices.length} livre(s)',
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildListView() {
    // Apply source filter
    final filteredResults = _selectedSource == null
        ? _searchResults
        : _searchResults.where((r) => r['source'] == _selectedSource).toList();

    return ListView.builder(
      itemCount: filteredResults.length,
      itemBuilder: (context, index) {
        final book = filteredResults[index];
        // Find original index for selection tracking
        final originalIndex = _searchResults.indexOf(book);
        final isSelected = _selectedIndices.contains(originalIndex);
        final source = book['source'] as String?;

        return ListTile(
          leading: SizedBox(
            width: 40,
            height: 60,
            child: Stack(
              children: [
                // 1. Fallback Colored Cover (Always visible behind)
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _getCoverColor(book['title'] ?? ''),
                        _getCoverColor(book['title'] ?? '').withOpacity(0.7),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      (book['title'] as String?)
                              ?.substring(0, 1)
                              .toUpperCase() ??
                          '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),

                // 2. Network Image (if available)
                if (book['cover_url'] != null &&
                    (book['cover_url'] as String).isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: book['cover_url'],
                      width: 40,
                      height: 60,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const SizedBox.shrink(),
                      errorWidget: (context, url, error) =>
                          const SizedBox.shrink(),
                    ),
                  ),

                // 3. Source Badge
                if (source != null)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: _getSourceColor(source),
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        _getSourceLabel(source),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          title: Text(book['title'] ?? 'Unknown'),
          subtitle: Text(
            '${book['author'] ?? ''} (${book['publication_year'] ?? '?'})',
          ),
          trailing: Checkbox(
            value: isSelected,
            onChanged: (val) => _toggleSelection(originalIndex),
          ),
        ); // End ListTile
      },
    ); // End ListView.builder
  }

  Widget _buildEditionView() {
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
          onAddBook: _addBookFromEdition,
        );
      },
    );
  }

  Color _getSourceColor(String source) {
    if (source.contains('Inventaire')) return Colors.green;
    if (source.toLowerCase().contains('bnf')) return Colors.orange;
    if (source.contains('Google')) return Colors.red;
    return Colors.blue; // OpenLibrary or default
  }

  String _getSourceLabel(String source) {
    if (source.contains('Inventaire')) return 'INV';
    if (source.toLowerCase().contains('bnf')) return 'BNF';
    if (source.contains('Google')) return 'GB';
    return 'OL';
  }

  /// Full source name for dropdown filter (truncated if too long)
  String _getSourceFullLabel(String source) {
    if (source.contains('Inventaire')) return 'Inventaire.io';
    if (source.toLowerCase().contains('bnf')) return 'data.bnf.fr';
    if (source.contains('Google')) return 'Google Books';
    if (source.contains('Open Library')) return 'Open Library';
    // Return original if not recognized, truncate if > 20 chars
    return source.length > 20 ? '${source.substring(0, 17)}...' : source;
  }

  Color _getCoverColor(String title) {
    if (title.isEmpty) return Colors.grey;
    final random = Random(title.hashCode);
    return Color.fromARGB(
      255,
      random.nextInt(200),
      random.nextInt(200),
      random.nextInt(200),
    );
  }
}
