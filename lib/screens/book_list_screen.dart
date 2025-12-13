import 'package:flutter/material.dart';
import '../widgets/genie_app_bar.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/translation_service.dart';
import '../models/book.dart';
import '../widgets/bookshelf_view.dart';
import '../widgets/book_cover_grid.dart'; 
import '../widgets/premium_book_card.dart';
import '../theme/app_design.dart';
import '../providers/theme_provider.dart';
import '../utils/avatars.dart';


enum ViewMode {
  coverGrid, // Netflix style
  spineShelf, // Original bookshelf
  list, // Simple list
}

class BookListScreen extends StatefulWidget {
  final String? initialSearchQuery;

  const BookListScreen({super.key, this.initialSearchQuery});

  @override
  State<BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends State<BookListScreen> {
  List<Book> _books = [];
  List<Book> _filteredBooks = [];
  
  // Filter state
  String? _selectedStatus;
  String? _tagFilter;
  
  bool _isLoading = true;
  ViewMode _viewMode = ViewMode.coverGrid; // Default to cover grid
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  bool _isReordering = false;
  String? _libraryName; // Store library name for title

  final GlobalKey _addKey = GlobalKey();
  final GlobalKey _searchKey = GlobalKey();
  final GlobalKey _viewKey = GlobalKey();
  final GlobalKey _scanKey = GlobalKey();
  final GlobalKey _externalSearchKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _searchQuery = widget.initialSearchQuery ?? '';
    if (_searchQuery.isNotEmpty) {
      _isSearching = true;
    }
    _fetchBooks();
    // Trigger background sync
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SyncService>(context, listen: false).syncAllPeers();
      _checkWizard();
      
      // Initialize filters from query params
      final state = GoRouterState.of(context);
      if (state.uri.queryParameters.containsKey('tag')) {
         setState(() {
           _tagFilter = state.uri.queryParameters['tag'];
           _filterBooks();
         });
      }
    });
  }

  Future<void> _checkWizard() async {
    // Temporarily disabled - use main onboarding tour instead
    /*
    final hasSeen = await WizardService.hasSeenBooksWizard();
    if (!hasSeen && mounted) {
      WizardService.showBooksTutorial(
        context: context,
        addKey: _addKey,
        searchKey: _searchKey,
        viewKey: _viewKey,
        scanKey: _scanKey,
        externalSearchKey: _externalSearchKey,
      );
    }
    */
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    // Banner always shows translated "My Library"
    dynamic titleWidget = _isSearching
            ? _buildSearchField() // Use custom search field with autocomplete
            : TranslationService.translate(context, 'my_library_title');
    
    if (_isReordering) {
      titleWidget = const Text('Reordering Shelf...', style: TextStyle(color: Colors.white, fontSize: 18));
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GenieAppBar(
        title: titleWidget,
        actions: [
          if (_isReordering) ...[
             IconButton(
               icon: const Icon(Icons.sort_by_alpha, color: Colors.white),
               tooltip: 'Sort A→Z by Author',
               onPressed: _autoSortByAuthor,
             ),
             IconButton(
               icon: const Icon(Icons.check, color: Colors.white),
               tooltip: 'Save Order',
               onPressed: _saveOrder,
             ),
             IconButton(
               icon: const Icon(Icons.close, color: Colors.white),
               tooltip: 'Cancel',
               onPressed: () {
                 setState(() {
                   _isReordering = false;
                   _fetchBooks(); // Reset to original order
                 });
               },
             ),
          ] else ...[
            // Reorder Button (Only when Tag Filter is Active)
            if (_tagFilter != null && !_isSearching)
              IconButton(
                icon: const Icon(Icons.sort, color: Colors.white),
                tooltip: 'Reorder Shelf',
                onPressed: () {
                  setState(() {
                    _isReordering = true;
                    _viewMode = ViewMode.list; // Force list view for reordering
                  });
                },
              ),

             IconButton(
              key: _searchKey,
              icon: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.white),
              tooltip: TranslationService.translate(context, _isSearching ? 'cancel' : 'search_books'),
              onPressed: () {
                setState(() {
                  if (_isSearching) {
                    _isSearching = false;
                    _searchController.clear();
                    _filterBooks();
                  } else {
                    _isSearching = true;
                  }
                });
              },
            ),
          ], // End else
          
          if (!_isSearching && !_isReordering) ...[
            IconButton(
              key: _viewKey,
              icon: Icon(_getViewIcon(_viewMode), color: Colors.white),
              tooltip: TranslationService.translate(context, 'action_change_view'),
              onPressed: () {
                setState(() {
                  _viewMode = _getNextViewMode(_viewMode);
                });
              },
            ),
            IconButton(
              key: _scanKey,
              icon: const Icon(Icons.camera_alt, color: Colors.white),
              tooltip: TranslationService.translate(context, 'scan_isbn_title'),
              onPressed: () {
                context.push('/scan');
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: TranslationService.translate(context, 'action_refresh'),
              onPressed: _fetchBooks
            ),
            IconButton(
              key: _externalSearchKey,
              icon: const Icon(Icons.public, color: Colors.white),
              tooltip:
                  TranslationService.translate(context, 'btn_search_online'),
              onPressed: () {
                context.push('/search/external');
              },
            ),
          ],
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppDesign.pageGradient, // Discrete light background
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              _buildFilterBar(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.black54)))
                    : _buildBody(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: _addKey,
        onPressed: () async {
          final result = await context.push('/books/add');
          if (result == true) {
            _fetchBooks(); // Refresh if book was added
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }


  Future<void> _fetchBooks() async {
    setState(() => _isLoading = true);
    final apiService = Provider.of<ApiService>(context, listen: false);
    
    try {
      debugPrint('Fetching books with status: $_selectedStatus, tag: $_tagFilter, search: $_searchQuery');
      // Fetch all books initially, filtering will happen locally
      final books = await apiService.getBooks();

      final configRes = await apiService.getLibraryConfig(); 
      bool showBorrowed = true;
      String? libraryName;
      if (configRes.statusCode == 200) {
         showBorrowed = configRes.data['show_borrowed_books'] == true;
         libraryName = configRes.data['library_name'] as String?;
      }
      
      if (mounted) {
        setState(() {
          _books = showBorrowed ? books : books.where((b) => b.readingStatus != 'borrowed').toList();
          _libraryName = libraryName;
          _filterBooks(); // Apply filters after fetching all books
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('Error loading books: $e');
      }
    }
  }

  // Triggered when filters change or search query changes
  void _filterBooks() {
    List<Book> tempBooks = List.from(_books);

    // Apply status filter
    if (_selectedStatus != null) {
      tempBooks = tempBooks.where((book) => book.readingStatus == _selectedStatus).toList();
    }

    // Apply tag filter
    if (_tagFilter != null) {
      tempBooks = tempBooks.where((book) => (book.subjects ?? []).contains(_tagFilter)).toList();
    }

    // Apply search query filter
    if (_searchQuery.isNotEmpty) {
      tempBooks = tempBooks.where((book) => 
        book.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        (book.author?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false)
      ).toList();
    }

    setState(() {
      _filteredBooks = tempBooks;
    });
  }
  
  void _showTagFilterDialog() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    
    try {
      final tags = await apiService.getTags();
      
      if (!mounted) return;
      
      if (tags.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TranslationService.translate(context, 'no_tags'))),
        );
        return;
      }
      
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) {
          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TranslationService.translate(context, 'filter_by_tag'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: tags.map((tag) {
                    return ActionChip(
                      label: Text('${tag.name} (${tag.count})'),
                      avatar: const Icon(Icons.label, size: 16),
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _tagFilter = tag.name;
                          _filterBooks();
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('Error loading tags: $e');
    }
  }
  
  // _fetchSuggestions is removed as Autocomplete now works directly on _allBooks

  Widget _buildSearchField() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppDesign.subtleShadow,
      ),
      child: Autocomplete<Book>(
        displayStringForOption: (Book option) => option.title,
        optionsBuilder: (TextEditingValue textEditingValue) {
          if (textEditingValue.text.isEmpty) {
            return const Iterable<Book>.empty();
          }
          return _books.where((Book book) {
            return book.title.toLowerCase().contains(textEditingValue.text.toLowerCase()) ||
                   (book.author?.toLowerCase().contains(textEditingValue.text.toLowerCase()) ?? false);
          });
        },
        onSelected: (Book selection) {
          context.push('/books/${selection.id}');
        },
        fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
          // Sync internal _searchQuery with Autocomplete's controller
          if (_searchQuery != textEditingController.text) {
            textEditingController.text = _searchQuery;
          }

          return TextField(
            controller: textEditingController,
            focusNode: focusNode,
            style: const TextStyle(color: Colors.black87),
            decoration: InputDecoration(
              hintText: TranslationService.translate(context, 'search_books'),
              hintStyle: const TextStyle(color: Colors.black38),
              prefixIcon: const Icon(Icons.search, color: Colors.black54),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
                _filterBooks(); // Trigger filter on search query change
              });
            },
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4.0,
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300), // Adjust width as needed
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Book option = options.elementAt(index);
                    return InkWell(
                      onTap: () => onSelected(option),
                      child: ListTile(
                        leading: option.coverUrl != null
                          ? Image.network(option.coverUrl!, width: 30, fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.book, size: 30))
                          : const Icon(Icons.book, size: 30, color: Colors.grey),
                        title: Text(option.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(option.author ?? 'Unknown', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    // Use library name if available, otherwise fallback to translation
    final libraryTitle = _libraryName ?? TranslationService.translate(context, 'my_library_title');
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    // Get avatar info
    final avatarConfig = themeProvider.avatarConfig;
    final avatar = availableAvatars.firstWhere(
      (a) => a.id == themeProvider.currentAvatarId,
      orElse: () => availableAvatars.first,
    );
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        children: [
          // Avatar circle
          GestureDetector(
            onTap: () => context.push('/profile'),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: avatar.themeColor, width: 2),
                color: avatarConfig?.style == 'genie'
                    ? Color(int.parse('FF${avatarConfig?.genieBackground ?? "fbbf24"}', radix: 16))
                    : Colors.white,
              ),
              child: ClipOval(
                child: avatarConfig?.style == 'genie'
                    ? Image.network(
                        avatarConfig?.toUrl(size: 48, format: 'png') ?? '',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Image.asset(avatar.assetPath, fit: BoxFit.cover),
                      )
                    : Image.asset(avatar.assetPath, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              libraryTitle,
              style: const TextStyle(
                fontSize: 28, 
                fontWeight: FontWeight.bold,
                color: Colors.black87, // Dark text
              ),
            ),
          ),
          // Add Book Button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                final result = await context.push('/books/add');
                if (result == true) {
                  _fetchBooks(); // Refresh if book was added
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: AppDesign.subtleShadow,
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          // View Mode Toggles
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                _buildViewModeToggle(Icons.grid_view, ViewMode.coverGrid),
                _buildViewModeToggle(Icons.shelves, ViewMode.spineShelf),
                _buildViewModeToggle(Icons.list, ViewMode.list),
              ],
            ),
          ),
          const SizedBox(width: 12),
          
          // Tag Filter (if active)
          if (_tagFilter != null) ...[
            _buildFilterPill(
              status: 'tag_filter', // A dummy status to identify this pill
              label: '#$_tagFilter',
              isClearAction: true,
            ),
            const SizedBox(width: 8),
          ],

          // Tag Filter Button (to select a tag)
          if (_tagFilter == null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ScaleOnTap(
                onTap: () => _showTagFilterDialog(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.label_outline, size: 16, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 4),
                      Text(
                        TranslationService.translate(context, 'tags'),
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Status Filters
          _buildFilterPill(status: null, label: TranslationService.translate(context, 'filter_all')),
          _buildFilterPill(status: 'reading', label: TranslationService.translate(context, 'reading_status_reading')),
          _buildFilterPill(status: 'to_read', label: TranslationService.translate(context, 'reading_status_to_read')),
          _buildFilterPill(status: 'wanting', label: TranslationService.translate(context, 'reading_status_wanting')),
          _buildFilterPill(status: 'read', label: TranslationService.translate(context, 'reading_status_read')),
        ],
      ),
    );
  }

  Widget _buildViewModeToggle(IconData icon, ViewMode mode) {
    final bool isSelected = _viewMode == mode;
    return ScaleOnTap(
      onTap: () {
        setState(() {
          _viewMode = mode;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: isSelected ? Colors.white : Colors.black54,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildFilterPill({
    required String? status,
    required String label,
    bool isClearAction = false,
  }) {
    final bool isSelected = _selectedStatus == status;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ScaleOnTap(
        onTap: () {
          if (isClearAction) {
            setState(() {
              _tagFilter = null;
              _filterBooks();
            });
          } else {
            setState(() {
              _selectedStatus = isSelected ? null : status;
              _filterBooks();
            });
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isClearAction 
                ? Colors.redAccent.withOpacity(0.8)
                : (isSelected ? Theme.of(context).primaryColor : Colors.white),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? Colors.transparent : Colors.grey.withOpacity(0.3),
            ),
             boxShadow: isSelected && !isClearAction
                ? [
                    BoxShadow(
                      color: Theme.of(context).primaryColor.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isClearAction) ...[
                const Icon(Icons.close, size: 16, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: isClearAction ? Colors.white : (isSelected ? Colors.white : Colors.black54),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onBookTap(Book book) async {
    final result = await context.push('/books/${book.id}', extra: book);
    if (result == true) {
      _fetchBooks();
    }
  }



  ViewMode _getNextViewMode(ViewMode current) {
    switch (current) {
      case ViewMode.coverGrid:
        return ViewMode.spineShelf;
      case ViewMode.spineShelf:
        return ViewMode.list;
      case ViewMode.list:
        return ViewMode.coverGrid;
    }
  }

  IconData _getViewIcon(ViewMode mode) {
    switch (mode) {
      case ViewMode.coverGrid:
        return Icons.grid_view;
      case ViewMode.spineShelf:
        return Icons.shelves;
      case ViewMode.list:
        return Icons.list;
    }
  }

  Widget _buildBody() {
    if (_filteredBooks.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              TranslationService.translate(context, 'no_books_found'),
              style: TextStyle(fontSize: 18, color: Colors.grey.withOpacity(0.8)),
            ),
          ],
        ),
      );
    }
    
    switch (_viewMode) {
      case ViewMode.coverGrid:
        return BookCoverGrid(
          books: _filteredBooks,
          onBookTap: _onBookTap,
        );
      case ViewMode.spineShelf:
        return BookshelfView(
          books: _filteredBooks,
          onBookTap: _onBookTap,
        );
      case ViewMode.list:
        return _buildListView();
    }
  }

  Widget _buildListView() {
    if (_isReordering) {
      return ReorderableListView.builder(
        itemCount: _filteredBooks.length,
        padding: const EdgeInsets.all(16),
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (oldIndex < newIndex) {
              newIndex -= 1;
            }
            final Book item = _filteredBooks.removeAt(oldIndex);
            _filteredBooks.insert(newIndex, item);
          });
        },
        itemBuilder: (context, index) {
          final book = _filteredBooks[index];
          return Card(
            key: ValueKey(book.id ?? index), // Ensure stable key
            margin: const EdgeInsets.only(bottom: 16),
            child: ListTile(
              contentPadding: const EdgeInsets.all(8),
              leading: book.coverUrl != null
                  ? Image.network(book.coverUrl!, width: 40, fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.book))
                  : const Icon(Icons.book, size: 40, color: Colors.grey),
              title: Text(book.title),
              subtitle: Text(book.author ?? 'Unknown'),
              trailing: ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle),
              ),
            ),
          );
        },
      );
    }

    return ListView.builder(
      itemCount: _filteredBooks.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final book = _filteredBooks[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: PremiumBookCard(
            book: book,
            isHero: true, // Use hero layout (horizontal) for list items
            width: double.infinity,
          ),
        );
      },
    );
  }

  Future<void> _saveOrder() async {
    setState(() => _isLoading = true);
    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      final ids = _filteredBooks.map((b) => b.id!).toList();
      await apiService.reorderBooks(ids);
      
      setState(() {
        _isReordering = false;
        _isLoading = false;
      });
      // Optionally refresh
      _fetchBooks();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Shelf order saved!')),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving order: $e')),
      );
    }
  }

  void _autoSortByAuthor() {
    setState(() {
      _filteredBooks.sort((a, b) {
        // Sort by author (null-safe), then by title if same author
        final authorA = (a.author ?? '').toLowerCase();
        final authorB = (b.author ?? '').toLowerCase();
        final authorCompare = authorA.compareTo(authorB);
        if (authorCompare != 0) return authorCompare;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sorted by author A→Z. Click ✓ to save.'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
