import 'package:flutter/material.dart';
import '../widgets/genie_app_bar.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/translation_service.dart';
import '../models/book.dart';
import '../widgets/bookshelf_view.dart';
import '../widgets/book_cover_grid.dart'; // Import the new grid

import '../widgets/app_drawer.dart';
import '../services/wizard_service.dart';

enum ViewMode {
  coverGrid, // Netflix style
  spineShelf, // Original bookshelf
  list, // Simple list
}

class BookListScreen extends StatefulWidget {
  const BookListScreen({super.key});

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
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  final GlobalKey _addKey = GlobalKey();
  final GlobalKey _searchKey = GlobalKey();
  final GlobalKey _viewKey = GlobalKey();
  final GlobalKey _scanKey = GlobalKey();
  final GlobalKey _externalSearchKey = GlobalKey();

  @override
  void initState() {
    super.initState();
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
    return Scaffold(
      appBar: GenieAppBar(
        title: _isSearching
            ? _buildSearchField() // Use custom search field with autocomplete
            : TranslationService.translate(context, 'my_library_title'),
        actions: [
          IconButton(
            key: _searchKey,
            icon: Icon(_isSearching ? Icons.close : Icons.search),
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
          if (!_isSearching) ...[
            IconButton(
              key: _viewKey,
              icon: Icon(_getViewIcon(_viewMode)),
              onPressed: () {
                setState(() {
                  _viewMode = _getNextViewMode(_viewMode);
                });
              },
            ),
            IconButton(
              key: _scanKey,
              icon: const Icon(Icons.camera_alt),
              onPressed: () {
                context.push('/scan');
              },
            ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchBooks),
            IconButton(
              key: _externalSearchKey,
              icon: const Icon(Icons.public),
              tooltip:
                  TranslationService.translate(context, 'btn_search_online'),
              onPressed: () {
                context.push('/search/external');
              },
            ),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: _buildFilterBar(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
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
      // Build filters
      // Note: Backend supports status, title, author, tag.
      // We map our search query to 'title' for now, or use a general search if backend supports 'q'.
      // Looking at `ApiService`, getBooks takes named args.
      
      debugPrint('Fetching books with status: $_selectedStatus, tag: $_tagFilter, search: ${_searchController.text}');
      final books = await apiService.getBooks(
        status: _selectedStatus,
        tag: _tagFilter,
        title: _searchController.text.isNotEmpty ? _searchController.text : null,
      );

      final configRes = await apiService.getLibraryConfig(); // Keep config check?
      bool showBorrowed = true;
      if (configRes.statusCode == 200) {
         showBorrowed = configRes.data['show_borrowed_books'] == true;
      }
      
      if (mounted) {
        setState(() {
          // If config hides borrowed, we filter them out client side OR update backend to support it.
          // For safety, filter client side too.
          _books = showBorrowed ? books : books.where((b) => b.readingStatus != 'borrowed').toList();
          _filteredBooks = _books; // They are same now, as filtering happened on server
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('Error loading books: $e');
        // Optional: Show snackbar
      }
    }
  }

  // Triggered when filters change
  void _filterBooks() {
    _fetchBooks();
  }
  
  // Fetch autocomplete suggestions
  Future<Iterable<String>> _fetchSuggestions(String query) async {
    if (query.isEmpty) return [];
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      // We can use the same getBooks query but just for titles
      final books = await api.getBooks(title: query);
      return books.map((b) => b.title).toSet().toList(); // Unique titles
    } catch (e) {
       return [];
    }
  }

  Widget _buildSearchField() {
    return Autocomplete<String>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        return _fetchSuggestions(textEditingValue.text);
      },
      onSelected: (String selection) {
        _searchController.text = selection;
        _filterBooks();
      },
      fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
        // Sync with our controller
        if (_searchController.text != textEditingController.text) {
           textEditingController.text = _searchController.text;
        }
        
        return TextField(
          controller: textEditingController,
          focusNode: focusNode,
          style: const TextStyle(color: Colors.white), 
          decoration: InputDecoration(
            hintText: TranslationService.translate(context, 'search_hint') ?? 'Search title, author...',
            hintStyle: const TextStyle(color: Colors.white70),
            border: InputBorder.none,
          ),
          onChanged: (value) {
            _searchController.text = value; 
             _filterBooks(); 
          },
        );
      },
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Tag Filter (if active)
          if (_tagFilter != null) ...[
            _buildFilterPill(
              label: '#$_tagFilter',
              icon: Icons.tag,
              isActive: true, // Always active if visible
              isClearAction: true, // Special styling for clearable tags
              onTap: () {
                setState(() {
                  _tagFilter = null;
                  _filterBooks();
                });
              },
            ),
            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: Theme.of(context).dividerColor,
            ),
            const SizedBox(width: 8),
          ],
          
          // "All" Filter
          _buildFilterPill(
            label: TranslationService.translate(context, 'filter_all') ?? 'All',
            icon: Icons.apps,
            isActive: _selectedStatus == null,
            onTap: () {
              setState(() {
                _selectedStatus = null;
                _filterBooks();
              });
            },
          ),
          const SizedBox(width: 8),
          
          // Reading
          _buildFilterPill(
            label: TranslationService.translate(context, 'reading_status_reading') ?? 'Reading',
            icon: Icons.auto_stories, // or local_library
            isActive: _selectedStatus == 'reading',
            onTap: () {
              setState(() {
                _selectedStatus = _selectedStatus == 'reading' ? null : 'reading';
                _filterBooks();
              });
            },
          ),
          const SizedBox(width: 8),
          
          // To Read
          _buildFilterPill(
            label: TranslationService.translate(context, 'reading_status_to_read') ?? 'To Read',
            icon: Icons.bookmark_border,
            isActive: _selectedStatus == 'to_read',
            onTap: () {
               setState(() {
                _selectedStatus = _selectedStatus == 'to_read' ? null : 'to_read';
                _filterBooks();
              });
            },
          ),
          const SizedBox(width: 8),
          
          // Finished
          _buildFilterPill(
            label: TranslationService.translate(context, 'reading_status_read') ?? 'Finished',
            icon: Icons.check_circle_outline,
            isActive: _selectedStatus == 'read',
            onTap: () {
               setState(() {
                _selectedStatus = _selectedStatus == 'read' ? null : 'read';
                _filterBooks();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPill({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    bool isClearAction = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Active colors
    final activeBg = theme.colorScheme.primary;
    final activeFg = theme.colorScheme.onPrimary;
    
    // Inactive colors
    final inactiveBg = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1);
    final inactiveFg = isDark ? Colors.white70 : Colors.black87;
    
    // Clear action specific logic (like for tags)
    final bg = isClearAction 
        ? theme.colorScheme.tertiaryContainer 
        : (isActive ? activeBg : inactiveBg);
    final fg = isClearAction
        ? theme.colorScheme.onTertiaryContainer
        : (isActive ? activeFg : inactiveFg);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: isActive 
              ? null 
              : Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
          boxShadow: isActive && !isClearAction
              ? [
                  BoxShadow(
                    color: activeBg.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isClearAction ? Icons.close : icon,
              size: 16,
              color: fg,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
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

  Future<void> _navigateToEditBook(Book book) async {
    final result = await context.push('/books/${book.id}/edit', extra: book);
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
        child: Text(TranslationService.translate(context, 'no_books_found') ?? 'No books found'),
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
    return ListView.separated(
      itemCount: _filteredBooks.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, index) {
        final book = _filteredBooks[index];
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 40,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: Colors.grey[200],
              image: book.coverUrl != null
                  ? DecorationImage(
                      image: NetworkImage(book.coverUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: book.coverUrl == null
                ? const Icon(Icons.book, color: Colors.grey, size: 20)
                : null,
          ),
          title: Text(
            book.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                book.publisher ?? 'Unknown Publisher',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (book.readingStatus != null) ...[
                const SizedBox(height: 4),
                Text(
                  book.readingStatus!.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (context) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.edit),
                        title: Text(TranslationService.translate(
                            context, 'menu_edit')),
                        onTap: () {
                          Navigator.pop(context);
                          _navigateToEditBook(book);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.library_books),
                        title: Text(TranslationService.translate(
                            context, 'menu_manage_copies')),
                        onTap: () {
                          Navigator.pop(context);
                          context.push(
                            '/books/${book.id}/copies',
                            extra: {
                              'bookId': book.id,
                              'bookTitle': book.title
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          onTap: () => _onBookTap(book),
        );
      },
    );
  }
}
