import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/recently_added_carousel.dart';
import '../widgets/scaffold_with_nav.dart';
import '../widgets/configurable_action_card.dart';
import '../widgets/quick_actions_sheet.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../data/repositories/book_repository.dart';
import '../data/repositories/collection_repository.dart';
import '../data/repositories/tag_repository.dart';
import '../models/collection.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/translation_service.dart';
import '../models/book.dart';
import '../models/tag.dart';
import '../widgets/bookshelf_view.dart';
import '../widgets/collection_stack_widget.dart';
import '../widgets/premium_empty_state.dart';
import '../widgets/book_cover_grid.dart';
import '../widgets/premium_book_card.dart';
import '../theme/app_design.dart';
import '../providers/theme_provider.dart';
import '../providers/book_refresh_notifier.dart';
import '../utils/book_status.dart';

enum ViewMode {
  coverGrid, // Netflix style
  spineShelf, // Original bookshelf
  list, // Simple list
  groupedCollections, // Books grouped by collection
}

class BookListScreen extends StatefulWidget {
  final String? initialSearchQuery;
  final bool isTabView;
  final ValueNotifier<int>? refreshNotifier;
  final String? initialTagFilter;
  final bool showBackToShelves;

  /// When provided (tab mode inside LibraryScreen), this drives the search
  /// query from the sticky sliver header. The internal search UI (filter bar
  /// icon + inline search field) is hidden in this case.
  final ValueListenable<String>? externalSearchQuery;

  const BookListScreen({
    super.key,
    this.initialSearchQuery,
    this.isTabView = false,
    this.refreshNotifier,
    this.initialTagFilter,
    this.showBackToShelves = false,
    this.externalSearchQuery,
  });

  @override
  State<BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends State<BookListScreen>
    with WidgetsBindingObserver {
  List<Book> _books = [];
  List<Book> _filteredBooks = [];

  // Global refresh notifier
  BookRefreshNotifier? _globalRefreshNotifier;

  // Filter state
  String? _selectedStatus;
  String? _tagFilter;

  // Hierarchical shelf navigation state
  List<Tag> _allTags = []; // All tags for hierarchy traversal
  List<Tag> _shelfPath = []; // Breadcrumb path (list of ancestors)
  Tag? _currentShelf; // Currently selected shelf (null = root)

  bool _isLoading = true;
  ViewMode _viewMode = ViewMode.coverGrid; // Default to cover grid
  List<CollectionGroup> _collectionGroups = [];
  bool _isLoadingGroups = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _isSearching = false;
  bool _isReordering = false;
  String? _libraryName; // Store library name for title

  final GlobalKey _addKey = GlobalKey();
  final GlobalKey _searchKey = GlobalKey();
  final GlobalKey _viewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchQuery = widget.initialSearchQuery ?? '';
    if (_searchQuery.isNotEmpty) {
      _isSearching = true;
    }

    // Initialize tag filter from widget parameter if provided
    if (widget.initialTagFilter != null) {
      _tagFilter = widget.initialTagFilter;
    }

    // Listen to refresh trigger (local)
    widget.refreshNotifier?.addListener(_handleRefreshTrigger);

    // Listen to external search query (driven by LibraryScreen's sliver header)
    widget.externalSearchQuery?.addListener(_handleExternalSearchChange);
    if (widget.externalSearchQuery != null) {
      _searchQuery = widget.externalSearchQuery!.value;
    }

    // Listen to global refresh trigger (for cross-screen updates)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _globalRefreshNotifier = context.read<BookRefreshNotifier>();
      _globalRefreshNotifier?.addListener(_handleRefreshTrigger);
    });

    _fetchBooks();

    // Trigger background sync and context-dependent initialization manually
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<SyncService>(context, listen: false).syncAllPeers();
      _checkWizard();

      // Apply default view mode from settings (group by collection)
      final themeProvider = context.read<ThemeProvider>();
      if (themeProvider.groupByCollections &&
          themeProvider.collectionsEnabled) {
        setState(() => _viewMode = ViewMode.groupedCollections);
      }

      // Initialize filters from query params (only if not already set by widget)
      final state = GoRouterState.of(context);
      if (widget.initialTagFilter == null &&
          state.uri.queryParameters.containsKey('tag')) {
        _tagFilter = state.uri.queryParameters['tag'];
      }
      if (state.uri.queryParameters.containsKey('status')) {
        _selectedStatus = state.uri.queryParameters['status'];
      }
      if (_tagFilter != null || _selectedStatus != null) {
        setState(() {
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = GoRouterState.of(context);
    final newTag = state.uri.queryParameters['tag'];

    // If tag changed (including check for null which means cleared), update filter
    if (newTag != _tagFilter) {
      if (mounted) {
        setState(() {
          _tagFilter = newTag;
          _filterBooks();
        });
      }
    }

    // Only sync status from URL if URL explicitly contains the 'status' parameter.
    // This preserves local filter state when navigating without URL params.
    if (state.uri.queryParameters.containsKey('status')) {
      final newStatus = state.uri.queryParameters['status'];
      if (newStatus != _selectedStatus) {
        if (mounted) {
          setState(() {
            _selectedStatus = newStatus;
            _filterBooks();
          });
        }
      }
    }

    // URL-based search sync only when the sticky sliver header isn't driving
    // the query (otherwise LibraryScreen owns the state).
    if (widget.externalSearchQuery == null) {
      final searchQuery =
          state.uri.queryParameters['q'] ?? state.uri.queryParameters['search'];
      if (searchQuery != null &&
          searchQuery.isNotEmpty &&
          searchQuery != _searchQuery) {
        if (mounted) {
          setState(() {
            _searchQuery = searchQuery;
            _isSearching = true;
            _searchController.text = searchQuery;
            _filterBooks();
          });
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh books when app comes back to foreground
    if (state == AppLifecycleState.resumed) {
      _fetchBooks();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.refreshNotifier?.removeListener(_handleRefreshTrigger);
    widget.externalSearchQuery?.removeListener(_handleExternalSearchChange);
    _globalRefreshNotifier?.removeListener(_handleRefreshTrigger);
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _handleExternalSearchChange() {
    if (!mounted) return;
    final newQuery = widget.externalSearchQuery?.value ?? '';
    if (newQuery == _searchQuery) return;
    setState(() {
      _searchQuery = newQuery;
      _filterBooks();
    });
  }

  void _handleRefreshTrigger() {
    _fetchBooks();

    // Smart Refresh: Double-check after 1s to catch any WAL/Hybrid sync latency
    // This ensures books added via the Native+HTTP hybrid methods (which might have a split-second delay
    // in 'owned' status propagation) appear correctly without manual refresh.
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        debugPrint('🔄 Smart Refresh: Executing silent double-check...');
        _fetchBooks(silent: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isMobile = width <= 600;

    // On mobile, hide title (just show icon); on desktop, show full title
    dynamic titleWidget = _isSearching
        ? _buildSearchField() // Use custom search field with autocomplete
        : (isMobile
              ? null
              : TranslationService.translate(context, 'my_library_title'));

    if (_isReordering) {
      titleWidget = Text(
        TranslationService.translate(context, 'reordering_shelf') ??
            'Reordering Shelf...',
        style: const TextStyle(color: Colors.white, fontSize: 18),
      );
    }

    if (widget.isTabView) {
      // Just return the body content for tab view
      return Container(
        decoration: BoxDecoration(
          gradient: AppDesign.pageGradientForTheme(
            context.select<ThemeProvider, String>((p) => p.themeStyle),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              // Custom header for tab view if needed, or reuse parts
              if (_isReordering)
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(context).primaryColor,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          TranslationService.translate(
                                context,
                                'reordering_shelf',
                              ) ??
                              'Reordering Shelf...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.sort_by_alpha,
                          color: Colors.white,
                        ),
                        tooltip: TranslationService.translate(context, 'sort_by_author_az'),
                        onPressed: _autoSortByAuthor,
                      ),
                      IconButton(
                        icon: const Icon(Icons.check, color: Colors.white),
                        tooltip: TranslationService.translate(context, 'save_shelf_order'),
                        onPressed: _saveOrder,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: TranslationService.translate(context, 'cancel'),
                        onPressed: () {
                          setState(() {
                            _isReordering = false;
                            _fetchBooks();
                          });
                        },
                      ),
                    ],
                  ),
                ),

              // Search Bar for Tab View (legacy path, only when the sticky
              // sliver header is not driving the search — i.e. no external
              // query notifier was provided by the parent).
              if (!_isReordering &&
                  _isSearching &&
                  widget.externalSearchQuery == null)
                Container(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Row(
                    children: [
                      Expanded(child: _buildSearchField()),
                    ],
                  ),
                ),

              _buildFilterBar(),
              if (!_isLoading)
                RecentlyAddedCarousel(
                  books: _books,
                  scope: RecentlyAddedCarouselScope.ownLib,
                ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleBodyScroll,
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.black54,
                            ),
                          ),
                        )
                      : _buildBody(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GenieAppBar(
        title: titleWidget,
        // subtitle: _libraryName, // Handled by ThemeProvider
        leading: buildDrawerLeading(context),
        automaticallyImplyLeading: false,
        actions: [
          if (_isReordering) ...[
            IconButton(
              icon: const Icon(Icons.sort_by_alpha, color: Colors.white),
              tooltip: TranslationService.translate(context, 'sort_by_author_az'),
              onPressed: _autoSortByAuthor,
            ),
            IconButton(
              icon: const Icon(Icons.check, color: Colors.white),
              tooltip: TranslationService.translate(context, 'save_shelf_order'),
              onPressed: _saveOrder,
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: TranslationService.translate(context, 'cancel'),
              onPressed: () {
                setState(() {
                  _isReordering = false;
                  _fetchBooks(); // Reset to original order
                });
              },
            ),
          ] else ...[
            // Batch Scan Button (Only when Tag Filter is Active)
            if (_tagFilter != null && !_isSearching)
              IconButton(
                icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                tooltip: TranslationService.translate(
                  context,
                  'scan_into_shelf',
                ),
                onPressed: () async {
                  final shelfId = _currentShelf?.id ?? _tagFilter;
                  final shelfName = _currentShelf?.fullPath ?? _tagFilter;
                  await context.push(
                    '/scan',
                    extra: {
                      'shelfId': shelfId,
                      'shelfName': shelfName,
                      'batch': true,
                    },
                  );
                  _fetchBooks(); // Refresh after scan
                },
              ),
            // Reorder Button (Only when Tag Filter is Active)
            if (_tagFilter != null && !_isSearching)
              IconButton(
                icon: const Icon(Icons.sort, color: Colors.white),
                tooltip: TranslationService.translate(context, 'reorder_shelf'),
                onPressed: () {
                  setState(() {
                    _isReordering = true;
                    _viewMode = ViewMode.list; // Force list view for reordering
                  });
                },
              ),

            IconButton(
              key: const Key('bookSearchButton'),
              icon: Icon(
                _isSearching ? Icons.close : Icons.search,
                color: Colors.white,
              ),
              tooltip: TranslationService.translate(
                context,
                _isSearching ? 'cancel' : 'search_books',
              ),
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
              tooltip: TranslationService.translate(
                context,
                'action_change_view',
              ),
              onPressed: () {
                setState(() {
                  _viewMode = _getNextViewMode(_viewMode);
                });
              },
            ),
          ],
        ],
        contextualQuickActions: [
          Builder(builder: (sheetContext) {
            final handlers = QuickActionsSheet.buildCommonHandlers(
              sheetContext,
              onDone: _fetchBooks,
            );
            final cards = <Widget>[];

            // Shelf-specific: scan into shelf, search into shelf
            if (_currentShelf != null) {
              final shelfId = _currentShelf!.id;
              final shelfName = _currentShelf!.fullPath;
              cards.add(Expanded(
                child: QuickActionCard(
                  icon: Icons.qr_code_scanner,
                  color: Colors.orange,
                  label: '${TranslationService.translate(sheetContext, 'quick_scan_barcode')} → ${_currentShelf!.name}',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final router = GoRouter.of(context);
                    final isbn = await router.push<String>(
                      '/scan',
                      extra: {'shelfId': shelfId, 'shelfName': shelfName},
                    );
                    if (isbn != null && mounted) {
                      final result = await router.push(
                        '/books/add',
                        extra: {'isbn': isbn, 'shelfId': shelfId},
                      );
                      if (result != null && mounted) {
                        _fetchBooks();
                        if (result is int) {
                          router.push('/books/$result');
                        }
                      }
                    }
                  },
                ),
              ));
              cards.add(const SizedBox(width: 12));
              cards.add(Expanded(
                child: QuickActionCard(
                  icon: Icons.travel_explore,
                  color: Colors.blue,
                  label: '${TranslationService.translate(sheetContext, 'quick_search_online')} → ${_currentShelf!.name}',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final result = await context.push(
                      '/search/external',
                      extra: {'shelfId': _currentShelf!.id},
                    );
                    if (result == true) {
                      _fetchBooks();
                    }
                  },
                ),
              ));
            }

            // General actions row
            final generalCards = <Widget>[
              Expanded(
                child: ConfigurableActionCard(
                  slotKey: 'booklist_ctx_slot_1',
                  defaultActionId: 'manage_shelves',
                  allowedActionIds: const [
                    'manage_shelves',
                    'batch_scan',
                    'inventory',
                    'import_csv',
                  ],
                  handlers: handlers,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: QuickActionCard(
                  icon: Icons.filter_list,
                  color: Colors.blueGrey,
                  label: TranslationService.translate(
                      sheetContext, 'filter_books'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showTagFilterDialog();
                  },
                ),
              ),
            ];

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (cards.isNotEmpty) ...[
                  Row(children: cards),
                  const SizedBox(height: 12),
                ],
                Row(children: generalCards),
              ],
            );
          }),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppDesign.pageGradientForTheme(
            context.select<ThemeProvider, String>((p) => p.themeStyle),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // _buildHeader(context), // Header removed, avatar now in AppBar
              _buildFilterBar(),
              if (!_isLoading)
                RecentlyAddedCarousel(
                  books: _books,
                  scope: RecentlyAddedCarouselScope.ownLib,
                ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleBodyScroll,
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.black54,
                            ),
                          ),
                        )
                      : _buildBody(),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _isZeroState ? null : FloatingActionButton(
        heroTag: 'add_book_fab',
        key: const Key('addBookButton'),
        onPressed: _addBook,
        child: const Icon(Icons.add),
      ),
    );
  }

  bool _showBorrowedConfig = true; // Store config value

  Future<void> _scanBook() async {
    final router = GoRouter.of(context);
    final isbn = await router.push<String>(
      '/scan',
      extra: {
        if (_currentShelf != null) 'shelfId': _currentShelf!.id,
        if (_currentShelf != null) 'shelfName': _currentShelf!.fullPath,
      },
    );
    if (isbn != null && mounted) {
      final result = await router.push(
        '/books/add',
        extra: {
          'isbn': isbn,
          if (_currentShelf != null) 'shelfId': _currentShelf!.id,
        },
      );
      if (result != null && mounted) {
        _fetchBooks();
        if (result is int) {
          router.push('/books/$result');
        }
      }
    }
  }

  Future<void> _addBook() async {
    final router = GoRouter.of(context);
    final result = await router.push(
      '/books/add',
      extra: {'shelfId': _currentShelf?.name ?? _tagFilter},
    );
    if (result != null) {
      _handleRefreshTrigger(); // Use central refresh trigger
      if (result is int) {
        router.push('/books/$result');
      }
    }
  }

  Future<void> _fetchBooks({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    final apiService = Provider.of<ApiService>(context, listen: false);

    try {
      debugPrint(
        'Fetching books with status: $_selectedStatus, tag: $_tagFilter, search: $_searchQuery (silent: $silent)',
      );
      // Fetch all books initially, filtering will happen locally
      final books = await bookRepo.getBooks();

      final configRes = await apiService.getLibraryConfig();
      if (configRes.statusCode == 200) {
        _showBorrowedConfig = configRes.data['show_borrowed_books'] != false;
      }
      // Library name comes from ThemeProvider (set via SharedPreferences + FFI)
      final libraryName = Provider.of<ThemeProvider>(
        context,
        listen: false,
      ).libraryName;

      if (mounted) {
        // Also load tags for hierarchy navigation
        final tagRepo = Provider.of<TagRepository>(context, listen: false);
        final tags = await tagRepo.getTags();

        setState(() {
          _books = books; // Store ALL books, filtering happens in _filterBooks
          _allTags = tags; // Store tags for hierarchy traversal
          _libraryName = libraryName;
          _filterBooks(); // Apply filters after fetching all books
          if (!silent) _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        if (!silent) setState(() => _isLoading = false);
        debugPrint('Error loading books: $e');
      }
    }
  }

  // Triggered when filters change or search query changes
  void _filterBooks() {
    List<Book> tempBooks = List.from(_books);
    debugPrint(
      '🔍 _filterBooks: Starting with ${tempBooks.length} books, _selectedStatus=$_selectedStatus',
    );

    // Default view (no status selected): show books I physically have
    // (owned + borrowed). Wanting/wishlist excluded unless explicitly selected.
    if (_selectedStatus == null) {
      tempBooks = tempBooks.where((b) => b.owned || b.readingStatus == 'borrowed' || b.readingStatus == 'lent').toList();
      // Apply "show borrowed" config: hide borrowed/lent if user disabled it in settings
      if (!_showBorrowedConfig) {
        tempBooks = tempBooks.where((b) => b.readingStatus != 'borrowed' && b.readingStatus != 'lent').toList();
      }
      debugPrint(
        '🔍 _filterBooks: After default filter: ${tempBooks.length} books',
      );
    } else {
      // Explicit status selected via dropdown
      debugPrint('🔍 _filterBooks: Filtering by status=$_selectedStatus');

      if (_selectedStatus == 'uncategorized') {
        // "Non classés" = owned books with no reading status (null or empty)
        tempBooks = tempBooks
            .where(
              (book) =>
                  book.owned &&
                  (book.readingStatus == null || book.readingStatus!.isEmpty),
            )
            .toList();
      } else if (_selectedStatus == 'wanting') {
        // Wishlist: not owned, wanting status
        tempBooks = tempBooks
            .where((book) => book.readingStatus == 'wanting')
            .toList();
      } else if (_selectedStatus == 'borrowed') {
        // Borrowed: books I borrowed from someone
        tempBooks = tempBooks
            .where((book) => book.readingStatus == 'borrowed')
            .toList();
      } else if (_selectedStatus == 'lent') {
        // Lent: books I lent to someone (own copy with status "borrowed")
        tempBooks = tempBooks
            .where((book) => book.readingStatus == 'lent')
            .toList();
      } else {
        // Other statuses (reading, to_read, read): owned books with that status
        tempBooks = tempBooks
            .where((book) => book.owned && book.readingStatus == _selectedStatus)
            .toList();
      }
      debugPrint(
        '🔍 _filterBooks: After status filter: ${tempBooks.length} books',
      );
    }

    // Apply tag filter with hierarchy support
    // When filtering by a parent tag, include books from all child tags
    if (_currentShelf != null && _allTags.isNotEmpty) {
      // Get all matching tag names (this tag + descendants)
      final matchingNames = Tag.getTagNamesWithDescendants(
        _currentShelf!,
        _allTags,
      );
      tempBooks = tempBooks.where((book) {
        final bookTags =
            book.subjects?.map((s) => s.toLowerCase()).toSet() ?? {};
        // Book matches if any of its tags match any of the filter tags
        return bookTags.any((tag) => matchingNames.contains(tag));
      }).toList();
    } else if (_tagFilter != null) {
      // Fallback to simple string match for legacy compatibility
      final filterLower = _tagFilter!.toLowerCase();
      tempBooks = tempBooks.where((book) {
        final bookTags =
            book.subjects?.map((s) => s.toLowerCase()).toSet() ?? {};
        return bookTags.contains(filterLower);
      }).toList();
    }

    // Apply search query filter
    if (_searchQuery.isNotEmpty) {
      tempBooks = tempBooks
          .where(
            (book) =>
                book.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                (book.author?.toLowerCase().contains(
                      _searchQuery.toLowerCase(),
                    ) ??
                    false),
          )
          .toList();
    }

    // Default sort: alphabetical by author surname (last word), then by title
    // Helper to extract surname (last word) from author name
    String getSurname(String? author) {
      if (author == null || author.isEmpty) return '';
      final parts = author.trim().split(RegExp(r'\s+'));
      return parts.last.toLowerCase();
    }

    tempBooks.sort((a, b) {
      final surnameA = getSurname(a.author);
      final surnameB = getSurname(b.author);
      final surnameCompare = surnameA.compareTo(surnameB);
      if (surnameCompare != 0) return surnameCompare;
      // If same surname, compare full author name
      final authorA = (a.author ?? '').toLowerCase();
      final authorB = (b.author ?? '').toLowerCase();
      final authorCompare = authorA.compareTo(authorB);
      if (authorCompare != 0) return authorCompare;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    _filteredBooks = tempBooks;

    // Rebuild collection groups whenever filters change and grouped mode is active.
    if (_viewMode == ViewMode.groupedCollections) {
      _fetchCollectionGroups();
    }
  }

  Future<void> _fetchCollectionGroups() async {
    if (!mounted) return;
    setState(() => _isLoadingGroups = true);

    try {
      final collectionRepo = context.read<CollectionRepository>();
      final collections = await collectionRepo.getCollections();

      // Build a bookId -> Collection map (first collection wins for each book).
      final Map<int, Collection> bookToCollection = {};
      for (final collection in collections) {
        final collectionBooks =
            await collectionRepo.getCollectionBooks(collection.id);
        for (final cb in collectionBooks) {
          bookToCollection.putIfAbsent(cb.bookId, () => collection);
        }
      }

      // Bucket each filtered book into its collection (or uncollected).
      final Map<String, List<Book>> byCollectionId = {
        for (final c in collections) c.id: <Book>[],
      };
      final List<Book> uncollected = [];

      for (final book in _filteredBooks) {
        if (book.id == null) continue;
        final col = bookToCollection[book.id];
        if (col != null) {
          byCollectionId[col.id]?.add(book);
        } else {
          uncollected.add(book);
        }
      }

      // Build ordered group list: collections first, then individual uncollected books.
      final groups = <CollectionGroup>[];
      for (final collection in collections) {
        final books = byCollectionId[collection.id] ?? [];
        if (books.isNotEmpty) {
          groups.add(CollectionGroup(collection: collection, books: books));
        }
      }
      for (final book in uncollected) {
        groups.add(CollectionGroup(collection: null, books: [book]));
      }

      if (!mounted) return;
      setState(() => _collectionGroups = groups);
    } catch (e) {
      debugPrint('Error building collection groups: $e');
    } finally {
      if (mounted) setState(() => _isLoadingGroups = false);
    }
  }

  void _showTagFilterDialog() async {
    final tagRepo = Provider.of<TagRepository>(context, listen: false);

    try {
      final tags = await tagRepo.getTags();

      if (!mounted) return;

      if (tags.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TranslationService.translate(context, 'no_tags')),
          ),
        );
        return;
      }

      // Update local tags cache
      _allTags = tags;

      // Show hierarchical shelf navigation dialog
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) {
          return _ShelfNavigationSheet(
            tags: tags,
            currentShelf: _currentShelf,
            shelfPath: _shelfPath,
            onShelfSelected: (tag, path) {
              Navigator.pop(context);
              setState(() {
                _currentShelf = tag;
                _shelfPath = path;
                _tagFilter = tag?.fullPath;
                _filterBooks();
              });
            },
          );
        },
      );
    } catch (e) {
      debugPrint('Error loading tags: $e');
    }
  }

  // _fetchSuggestions is removed as Autocomplete now works directly on _allBooks

  Widget _buildSearchField() {
    // Use a unique key to force complete disposal when search mode changes
    // This prevents Flutter's Autocomplete async semantics from accessing unmounted state
    final isMobile = MediaQuery.of(context).size.width <= 600;
    return Container(
      key: const ValueKey('search_autocomplete'),
      margin: EdgeInsets.symmetric(horizontal: 20, vertical: isMobile ? 5 : 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
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
            return book.title.toLowerCase().contains(
                  textEditingValue.text.toLowerCase(),
                ) ||
                (book.author?.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    ) ??
                    false);
          });
        },
        onSelected: (Book selection) {
          if (!mounted) return; // Guard against unmounted state
          if (selection.id == null) return;
          context.push('/books/${selection.id}', extra: selection);
        },
        fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
          // Sync internal _searchQuery with Autocomplete's controller
          if (_searchQuery != textEditingController.text) {
            textEditingController.text = _searchQuery;
          }

          return TextField(
            controller: textEditingController,
            focusNode: focusNode,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            decoration: InputDecoration(
              labelText: TranslationService.translate(context, 'search_books'),
              labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
              floatingLabelBehavior: FloatingLabelBehavior.never,
              hintText: TranslationService.translate(context, 'search_books'),
              hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
              prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: isMobile ? 10 : 15,
              ),
            ),
            onChanged: (value) {
              if (!mounted) return;
              _searchQuery = value;
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                if (mounted) {
                  setState(() {
                    _filterBooks();
                  });
                }
              });
            },
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4.0,
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 200,
                  maxWidth: 300,
                ), // Adjust width as needed
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
                            ? Semantics(
                                image: true,
                                label: '${option.title}, ${option.author ?? ''}',
                                child: CachedNetworkImage(
                                  imageUrl: option.coverUrl!,
                                  width: 30,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) =>
                                      const Icon(Icons.book, size: 30),
                                ),
                              )
                            : const ExcludeSemantics(
                                child: Icon(
                                  Icons.book,
                                  size: 30,
                                  color: Colors.grey,
                                ),
                              ),
                        title: Text(
                          option.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          option.author ?? 'Unknown',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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

  // Header removed - Avatar is now in GenieAppBar

  Widget _buildFilterBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // determine active label for status filter
    String filterLabel = TranslationService.translate(context, 'filter_all');
    IconData filterIcon = Icons.filter_list;

    bool isFilterActive = false;

    if (_selectedStatus != null) {
      isFilterActive = true;
      // Map status to label
      if (_selectedStatus == 'reading') {
        filterLabel = TranslationService.translate(
          context,
          'reading_status_reading',
        );
      } else if (_selectedStatus == 'to_read') {
        filterLabel = TranslationService.translate(
          context,
          'reading_status_to_read',
        );
      } else if (_selectedStatus == 'wanting') {
        filterLabel = TranslationService.translate(
          context,
          'reading_status_wanting',
        );
      } else if (_selectedStatus == 'read') {
        filterLabel = TranslationService.translate(
          context,
          'reading_status_read',
        );
      } else if (_selectedStatus == 'uncategorized') {
        filterLabel = TranslationService.translate(context, 'status_uncategorized');
      } else if (_selectedStatus == 'borrowed') {
        filterLabel = TranslationService.translate(
          context,
          'reading_status_borrowed',
        );
      } else if (_selectedStatus == 'lent') {
        filterLabel = TranslationService.translate(
          context,
          'reading_status_lent',
        );
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          // 1. View Mode Toggles (Left aligned)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white24 : Colors.grey.withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                _buildViewModeToggle(Icons.grid_view, ViewMode.coverGrid),
                if (context.read<ThemeProvider>().collectionsEnabled)
                  _buildViewModeToggle(
                    Icons.collections_bookmark,
                    ViewMode.groupedCollections,
                    tooltip: TranslationService.translate(
                      context,
                      'view_mode_grouped_collections',
                    ),
                  ),
                _buildViewModeToggle(Icons.shelves, ViewMode.spineShelf),
                _buildViewModeToggle(Icons.list, ViewMode.list),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Search toggle (separate block) — hidden when the sticky sliver
          // header (LibraryScreen) drives the search instead.
          if (widget.externalSearchQuery == null) ...[
            Tooltip(
              message: TranslationService.translate(
                context,
                _isSearching ? 'cancel' : 'search_books',
              ),
              child: ScaleOnTap(
                onTap: () {
                  setState(() {
                    if (_isSearching) {
                      _isSearching = false;
                      _searchQuery = '';
                      _searchController.clear();
                      _filterBooks();
                    } else {
                      _isSearching = true;
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _isSearching
                        ? theme.primaryColor
                        : isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : theme.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isSearching
                          ? theme.primaryColor
                          : isDark
                              ? Colors.white24
                              : theme.primaryColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Icon(
                    _isSearching ? Icons.search_off : Icons.search,
                    size: 20,
                    color: _isSearching
                        ? Colors.white
                        : isDark
                            ? Colors.white70
                            : theme.primaryColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],

          // 2. Tag Filter Trigger
          // If a tag is selected, show it as a clearable chip
          if (_tagFilter != null) ...[
            _buildFilterPill(
              status: 'tag_filter',
              label: '#$_tagFilter',
              isClearAction: true,
            ),
            // Reorder button - only visible when viewing a shelf (tag filter active)
            if (!_isReordering) _buildReorderButton(context),
          ],
          const SizedBox(width: 4),

          // 3. Consolidated Status Filter Dropdown
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                if (value == 'clear') {
                  _selectedStatus = null;
                } else {
                  _selectedStatus = value;
                }
                _filterBooks();
              });
            },
            offset: const Offset(0, 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            itemBuilder: (context) {
              final theme = Theme.of(context);
              return [
                // HEADER: Statut
                PopupMenuItem<String>(
                  enabled: false,
                  height: 32,
                  child: Text(
                    TranslationService.translate(
                          context,
                          'status',
                        )?.toUpperCase() ??
                        'STATUS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.disabledColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Tous mes livres (Clear)
                PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(
                        Icons.library_books,
                        color: _selectedStatus == null
                            ? theme.primaryColor
                            : theme.iconTheme.color,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        TranslationService.translate(
                              context,
                              'filter_all_books',
                            ) ??
                            'Tous mes livres',
                        style: TextStyle(
                          fontWeight: _selectedStatus == null
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: _selectedStatus == null
                              ? theme.primaryColor
                              : null,
                        ),
                      ),
                      if (_selectedStatus == null) ...[
                        const Spacer(),
                        Icon(Icons.check, size: 18, color: theme.primaryColor),
                      ],
                    ],
                  ),
                ),
                // Lecture en cours
                PopupMenuItem(
                  value: 'reading',
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_stories,
                        color: _selectedStatus == 'reading'
                            ? Colors.blue
                            : theme.iconTheme.color,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        TranslationService.translate(
                              context,
                              'reading_status_reading',
                            ) ??
                            'Lecture en cours',
                        style: TextStyle(
                          fontWeight: _selectedStatus == 'reading'
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: _selectedStatus == 'reading'
                              ? Colors.blue
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                // À lire
                PopupMenuItem(
                  value: 'to_read',
                  child: Row(
                    children: [
                      Icon(
                        Icons.bookmark_border,
                        color: _selectedStatus == 'to_read'
                            ? Colors.orange
                            : theme.iconTheme.color,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        TranslationService.translate(
                              context,
                              'reading_status_to_read',
                            ) ??
                            'À lire',
                        style: TextStyle(
                          fontWeight: _selectedStatus == 'to_read'
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: _selectedStatus == 'to_read'
                              ? Colors.orange
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                // Lu
                PopupMenuItem(
                  value: 'read',
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: _selectedStatus == 'read'
                            ? Colors.green
                            : theme.iconTheme.color,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        TranslationService.translate(
                              context,
                              'reading_status_read',
                            ) ??
                            'Lu',
                        style: TextStyle(
                          fontWeight: _selectedStatus == 'read'
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: _selectedStatus == 'read'
                              ? Colors.green
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                // Sans statut (books without reading status)
                PopupMenuItem(
                  value: 'uncategorized',
                  child: Row(
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        color: _selectedStatus == 'uncategorized'
                            ? Colors.blueGrey
                            : Colors.blueGrey,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        TranslationService.translate(
                              context,
                              'status_uncategorized',
                            ) ??
                            'Non classés',
                        style: TextStyle(
                          fontWeight: _selectedStatus == 'uncategorized'
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: _selectedStatus == 'uncategorized'
                              ? Colors.blueGrey
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                // Envie de lire (Wishlist)
                PopupMenuItem(
                  value: 'wanting',
                  child: Row(
                    children: [
                      Icon(
                        Icons.favorite_border,
                        color: _selectedStatus == 'wanting'
                            ? Colors.red
                            : Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        TranslationService.translate(
                              context,
                              'reading_status_wanting',
                            ) ??
                            'Envie de lire',
                        style: TextStyle(
                          fontWeight: _selectedStatus == 'wanting'
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: _selectedStatus == 'wanting'
                              ? Colors.red
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                // Empruntés (only if borrow module is enabled)
                if (Provider.of<ThemeProvider>(context, listen: false).canBorrowBooks)
                  PopupMenuItem(
                    value: 'borrowed',
                    child: Row(
                      children: [
                        Icon(
                          Icons.swap_horiz,
                          color: _selectedStatus == 'borrowed'
                              ? Colors.purple
                              : theme.iconTheme.color,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          TranslationService.translate(
                                context,
                                'reading_status_borrowed',
                              ) ??
                              'Empruntés',
                          style: TextStyle(
                            fontWeight: _selectedStatus == 'borrowed'
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _selectedStatus == 'borrowed'
                                ? Colors.purple
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Prêtés (only if borrow module is enabled)
                if (Provider.of<ThemeProvider>(context, listen: false).canBorrowBooks)
                  PopupMenuItem(
                    value: 'lent',
                    child: Row(
                      children: [
                        Icon(
                          Icons.output,
                          color: _selectedStatus == 'lent'
                              ? Colors.orange
                              : theme.iconTheme.color,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          TranslationService.translate(
                                context,
                                'reading_status_lent',
                              ) ??
                              'Prêtés',
                          style: TextStyle(
                            fontWeight: _selectedStatus == 'lent'
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _selectedStatus == 'lent'
                                ? Colors.orange
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),

              ];
            },
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isFilterActive
                    ? theme.primaryColor.withOpacity(0.1)
                    : (isDark ? theme.cardColor : Colors.white),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isFilterActive
                      ? theme.primaryColor
                      : (isDark
                            ? Colors.white24
                            : Colors.grey.withOpacity(0.3)),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    filterIcon,
                    size: 18,
                    color: isFilterActive
                        ? theme.primaryColor
                        : theme.iconTheme.color,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    filterLabel,
                    style: TextStyle(
                      color: isFilterActive
                          ? theme.primaryColor
                          : (isDark ? Colors.white : Colors.black87),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 20,
                    color: isFilterActive
                        ? theme.primaryColor
                        : theme.iconTheme.color?.withOpacity(0.5),
                  ),
                ],
              ),
            ),
          ),

          // 4. Reset Filters Button - visible when any filter is active
          if (_selectedStatus != null ||
              _tagFilter != null ||
              _searchQuery.isNotEmpty) ...[
            const SizedBox(width: 8),
            ScaleOnTap(
              onTap: _resetAllFilters,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.clear_all, size: 18, color: Colors.red),
                    const SizedBox(width: 6),
                    Text(
                      TranslationService.translate(context, 'reset_filters') ??
                          'Réinitialiser',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // 5. Books Count Badge - always visible when books are displayed
          if (_filteredBooks.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.menu_book, size: 16, color: theme.primaryColor),
                  const SizedBox(width: 6),
                  Text(
                    _filteredBooks.length == 1
                        ? (TranslationService.translate(
                                context, 'displayed_books_count') ??
                            '%d book')
                            .replaceAll('%d', '${_filteredBooks.length}')
                        : (TranslationService.translate(
                                context, 'displayed_books_count_plural') ??
                            '%d books')
                            .replaceAll('%d', '${_filteredBooks.length}'),
                    style: TextStyle(
                      color: theme.primaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _resetAllFilters() {
    if (widget.showBackToShelves) {
      // Navigate back to shelves grid when resetting filters from shelf view
      context.go('/shelves');
      return;
    }
    setState(() {
      _selectedStatus = null;
      _tagFilter = null;
      _currentShelf = null;
      _searchQuery = '';
      _isSearching = false;
      _searchController.clear();
      _filterBooks();
    });
  }

  Widget _buildViewModeToggle(
    IconData icon,
    ViewMode? mode, {
    String? tooltip,
    VoidCallback? onTap,
  }) {
    final bool isSelected = mode != null && _viewMode == mode;
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isSelected
        ? Colors.white
        : isDarkTheme
        ? Colors.white70
        : Colors.black54;

    Widget button = ScaleOnTap(
      onTap: onTap ?? () {
        setState(() {
          _viewMode = mode!;
          if (mode == ViewMode.groupedCollections) {
            _fetchCollectionGroups();
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).primaryColor
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip, child: button);
    }
    return button;
  }

  Widget _buildFilterPill({
    required String? status,
    required String label,
    bool isClearAction = false,
  }) {
    final bool isSelected = _selectedStatus == status;
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    // Get icon for reading status if applicable
    IconData? statusIcon;
    Color? statusColor;
    if (status != null && !isClearAction) {
      final statusObj = individualStatuses.cast<BookStatus?>().firstWhere(
        (s) => s?.value == status,
        orElse: () => null,
      );
      if (statusObj != null) {
        statusIcon = statusObj.icon;
        statusColor = statusObj.color;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ScaleOnTap(
        onTap: () {
          if (isClearAction) {
            if (widget.showBackToShelves) {
              // Navigate back to shelves grid when clearing filter from shelf view
              context.go('/shelves');
            } else {
              setState(() {
                _tagFilter = null;
                _filterBooks();
              });
            }
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
                : (isSelected
                      ? Theme.of(context).primaryColor
                      : isDarkTheme
                      ? Theme.of(context).cardColor.withOpacity(0.8)
                      : Colors.white),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? Colors.transparent
                  : isDarkTheme
                  ? Theme.of(context).colorScheme.outline
                  : Colors.grey.withOpacity(0.3),
              width: isDarkTheme ? 1.5 : 1.0,
            ),
            boxShadow: isSelected && !isClearAction
                ? [
                    BoxShadow(
                      color: Theme.of(context).primaryColor.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isClearAction) ...[
                const Icon(Icons.close, size: 16, color: Colors.white),
                const SizedBox(width: 6),
              ] else if (statusIcon != null) ...[
                Icon(
                  statusIcon,
                  size: 16,
                  color: isSelected ? Colors.white : statusColor,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: isClearAction
                      ? Colors.white
                      : (isSelected
                            ? Colors.white
                            : Theme.of(context).textTheme.bodyMedium?.color ??
                                  Colors.black54),
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

  Widget _buildReorderButton(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'manual') {
            setState(() {
              _isReordering = true;
              _viewMode = ViewMode.list;
            });
          } else if (value == 'sort_az') {
            _autoSortByAuthor(descending: false);
          } else if (value == 'sort_za') {
            _autoSortByAuthor(descending: true);
          }
        },
        offset: const Offset(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'manual',
            child: Row(
              children: [
                Icon(Icons.drag_handle, color: theme.primaryColor, size: 20),
                const SizedBox(width: 12),
                Text(
                  TranslationService.translate(context, 'reorder_manual') ??
                      'Manual reorder',
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'sort_az',
            child: Row(
              children: [
                const Icon(Icons.arrow_downward, color: Colors.green, size: 20),
                const SizedBox(width: 12),
                Text(
                  TranslationService.translate(context, 'sort_by_author_az') ??
                      'Sort A→Z by author',
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'sort_za',
            child: Row(
              children: [
                const Icon(Icons.arrow_upward, color: Colors.orange, size: 20),
                const SizedBox(width: 12),
                Text(
                  TranslationService.translate(context, 'sort_by_author_za') ??
                      'Sort Z→A by author',
                ),
              ],
            ),
          ),
        ],
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? theme.cardColor : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? Colors.white24 : Colors.grey.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sort, size: 18, color: theme.primaryColor),
              const SizedBox(width: 6),
              Text(
                TranslationService.translate(context, 'organize') ?? 'Organize',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 20,
                color: theme.iconTheme.color?.withOpacity(0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onBookTap(Book book) async {
    if (book.id == null) return;
    final result = await context.push('/books/${book.id}', extra: book);
    if (result == true) {
      _fetchBooks();
    }
  }

  Future<void> _onStatusChanged(Book book, String newStatus) async {
    if (book.id == null) return;
    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    try {
      await bookRepo.updateBook(book.id!, {'reading_status': newStatus});
      if (mounted) _fetchBooks();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TranslationService.translate(
            context, 'error_save_failed',
          ))),
        );
      }
    }
  }

  ViewMode _getNextViewMode(ViewMode current) {
    final collectionsEnabled =
        context.read<ThemeProvider>().collectionsEnabled;
    switch (current) {
      case ViewMode.coverGrid:
        return collectionsEnabled
            ? ViewMode.groupedCollections
            : ViewMode.spineShelf;
      case ViewMode.groupedCollections:
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
      case ViewMode.groupedCollections:
        return Icons.collections_bookmark;
      case ViewMode.spineShelf:
        return Icons.shelves;
      case ViewMode.list:
        return Icons.list;
    }
  }

  /// True when the library has no books and no filters are active.
  bool get _isZeroState =>
      _books.isEmpty &&
      !_isLoading &&
      _searchQuery.isEmpty &&
      _tagFilter == null &&
      _selectedStatus == null;

  /// Auto-collapse the recently-added carousel when the book list is scrolled,
  /// expand again when scrolled back to the top. Hysteresis thresholds avoid
  /// flicker at the transition.
  bool _handleBodyScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final provider = context.read<ThemeProvider>();
    if (provider.carouselHiddenOwnLib) return false;
    final pixels = notification.metrics.pixels;
    if (pixels > 60) {
      provider.setCarouselCollapsedOwnLib(true);
    } else if (pixels <= 12) {
      provider.setCarouselCollapsedOwnLib(false);
    }
    return false;
  }

  Widget _buildBody() {
    // 1. Zero State: No books in the library at all (not just filtered out)
    if (_isZeroState) {
      return LayoutBuilder(
        builder: (context, constraints) => RefreshIndicator(
          onRefresh: _fetchBooks,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.only(left: 24, right: 24, bottom: 80),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).primaryColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.menu_book_rounded,
                        size: 64,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      TranslationService.translate(context, 'welcome_title'),
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      TranslationService.translate(
                          context, 'welcome_subtitle'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final router = GoRouter.of(context);
                        final isbn = await router.push<String>('/scan');
                        if (isbn != null && mounted) {
                          final result = await router.push(
                            '/books/add',
                            extra: {'isbn': isbn},
                          );
                          if (result == true && mounted) {
                            _fetchBooks();
                          }
                        }
                      },
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(
                        TranslationService.translate(
                            context, 'scan_first_book'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final result =
                            await context.push('/search/external');
                        if (result == true) {
                          _fetchBooks();
                        }
                      },
                      icon: const Icon(Icons.travel_explore),
                      label: Text(
                        TranslationService.translate(
                          context,
                          'btn_search_book_online',
                        ),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 2. No Results: Books exist but filters/search removed them
    if (_filteredBooks.isEmpty && !_isLoading) {
      return RefreshIndicator(
        onRefresh: _fetchBooks,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PremiumEmptyState(
                    message: _currentShelf != null
                        ? (TranslationService.translate(
                                context,
                                'no_books_found',
                              ) ??
                              'This shelf is empty')
                        : (TranslationService.translate(
                                context,
                                'no_books_found',
                              ) ??
                              'No books found'),
                    description: _currentShelf != null
                        ? (TranslationService.translate(
                                context,
                                'shelf_empty_desc',
                              ) ??
                              'Add books to this shelf to organize your library.')
                        : (TranslationService.translate(
                                context,
                                'search_empty_desc',
                              ) ??
                              'Try adjusting your filters or search terms.'),
                    icon: _currentShelf != null
                        ? Icons.bookmark_border
                        : Icons.search_off,
                    buttonLabel: _currentShelf != null
                        ? (TranslationService.translate(
                                context,
                                'add_first_book_in_shelf',
                              ) ??
                              'Add my first book to this shelf')
                        : (_tagFilter != null ||
                                  _searchQuery.isNotEmpty ||
                                  _selectedStatus != null
                              ? (TranslationService.translate(
                                      context,
                                      'reset_filters',
                                    ) ??
                                    'Reset')
                              : null),
                    onAction: _currentShelf != null
                        ? _addBook
                        : (_tagFilter != null ||
                                  _searchQuery.isNotEmpty ||
                                  _selectedStatus != null
                              ? _resetAllFilters
                              : null),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    switch (_viewMode) {
      case ViewMode.coverGrid:
        return RefreshIndicator(
          onRefresh: _fetchBooks,
          child: BookCoverGrid(
            books: _filteredBooks,
            onBookTap: _onBookTap,
            onStatusChanged: _onStatusChanged,
          ),
        );
      case ViewMode.spineShelf:
        return RefreshIndicator(
          onRefresh: _fetchBooks,
          child: BookshelfView(books: _filteredBooks, onBookTap: _onBookTap),
        );
      case ViewMode.list:
        return RefreshIndicator(
          onRefresh: _fetchBooks,
          child: _buildListView(),
        );
      case ViewMode.groupedCollections:
        if (_isLoadingGroups) {
          return const Center(child: CircularProgressIndicator());
        }
        return RefreshIndicator(
          onRefresh: () async {
            await _fetchBooks();
            await _fetchCollectionGroups();
          },
          child: CollectionGroupGrid(
            groups: _collectionGroups,
            onBookTap: _onBookTap,
          ),
        );
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
                  ? Semantics(
                      image: true,
                      label: '${book.title}, ${book.author ?? ''}',
                      child: CachedNetworkImage(
                        imageUrl: book.coverUrl!,
                        width: 40,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const Icon(Icons.book),
                      ),
                    )
                  : const ExcludeSemantics(
                      child: Icon(Icons.book, size: 40, color: Colors.grey),
                    ),
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
            isHero: true,
            width: double.infinity,
            onStatusChanged: (status) => _onStatusChanged(book, status),
          ),
        );
      },
    );
  }

  Future<void> _saveOrder() async {
    setState(() => _isLoading = true);
    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    try {
      final ids = _filteredBooks.map((b) => b.id!).toList();
      await bookRepo.reorderBooks(ids);

      setState(() {
        _isReordering = false;
        _isLoading = false;
      });
      // Don't call _fetchBooks() here - it would reload with global order
      // and lose the tag-filtered order we just saved
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.translate(context, 'shelf_order_saved'),
          ),
        ),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${TranslationService.translate(context, 'error_saving_order')}: $e',
          ),
        ),
      );
    }
  }

  void _autoSortByAuthor({bool descending = false}) {
    // Helper to extract surname (last word) from author name
    String getSurname(String? author) {
      if (author == null || author.isEmpty) return '';
      final parts = author.trim().split(RegExp(r'\s+'));
      return parts.last.toLowerCase();
    }

    setState(() {
      _filteredBooks.sort((a, b) {
        // Sort by author surname (last word), then full name, then title
        final surnameA = getSurname(a.author);
        final surnameB = getSurname(b.author);
        var surnameCompare = surnameA.compareTo(surnameB);
        if (descending) surnameCompare = -surnameCompare;
        if (surnameCompare != 0) return surnameCompare;
        // If same surname, compare full author name
        final authorA = (a.author ?? '').toLowerCase();
        final authorB = (b.author ?? '').toLowerCase();
        var authorCompare = authorA.compareTo(authorB);
        if (descending) authorCompare = -authorCompare;
        if (authorCompare != 0) return authorCompare;
        var titleCompare = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        if (descending) titleCompare = -titleCompare;
        return titleCompare;
      });
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          descending
              ? (TranslationService.translate(context, 'sorted_by_author_za') ??
                  'Sorted Z→A by author')
              : (TranslationService.translate(context, 'sorted_by_author_az') ??
                  'Sorted A→Z by author'),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// Netflix-style hierarchical shelf navigation sheet
/// Shows breadcrumbs + category cards with drill-down support
class _ShelfNavigationSheet extends StatefulWidget {
  final List<Tag> tags;
  final Tag? currentShelf;
  final List<Tag> shelfPath;
  final void Function(Tag? tag, List<Tag> path) onShelfSelected;

  const _ShelfNavigationSheet({
    required this.tags,
    required this.currentShelf,
    required this.shelfPath,
    required this.onShelfSelected,
  });

  @override
  State<_ShelfNavigationSheet> createState() => _ShelfNavigationSheetState();
}

class _ShelfNavigationSheetState extends State<_ShelfNavigationSheet> {
  late List<Tag> _path;
  Tag? _currentLevel;

  @override
  void initState() {
    super.initState();
    _path = List.from(widget.shelfPath);
    _currentLevel = widget.currentShelf;
  }

  List<Tag> get _visibleTags {
    if (_currentLevel == null) {
      // Show root tags only
      final rootTags = Tag.getRootTags(widget.tags);
      // Debug: print all tags to see parentId values
      debugPrint('📚 All tags (${widget.tags.length}):');
      for (final t in widget.tags) {
        debugPrint('  - ${t.name} (id=${t.id}, parentId=${t.parentId})');
      }
      debugPrint(
        '📚 Root tags (${rootTags.length}): ${rootTags.map((t) => t.name).join(", ")}',
      );
      return rootTags;
    } else {
      // Show direct children of current level
      return Tag.getDirectChildren(_currentLevel!.id, widget.tags);
    }
  }

  void _drillDown(Tag tag) {
    setState(() {
      if (_currentLevel != null) {
        _path.add(_currentLevel!);
      }
      _currentLevel = tag;
    });
  }

  void _navigateToPath(int index) {
    setState(() {
      if (index < 0) {
        // Go to root
        _path.clear();
        _currentLevel = null;
      } else if (index < _path.length) {
        _currentLevel = _path[index];
        _path = _path.sublist(0, index);
      }
    });
  }

  void _selectCurrent() {
    widget.onShelfSelected(_currentLevel, _path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = _visibleTags;
    final hasChildren = children.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with title and clear button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    TranslationService.translate(context, 'filter_by_tag'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_currentLevel != null || widget.currentShelf != null)
                    TextButton.icon(
                      onPressed: () => widget.onShelfSelected(null, []),
                      icon: const Icon(Icons.clear, size: 18),
                      label: Text(
                        TranslationService.translate(context, 'clear') ??
                            'Clear',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Breadcrumb navigation
              _buildBreadcrumbs(theme),
              const SizedBox(height: 16),

              // Current shelf info and select button
              if (_currentLevel != null) ...[
                _buildCurrentShelfCard(theme),
                const SizedBox(height: 16),
              ],

              // Sub-categories section
              if (hasChildren) ...[
                Text(
                  TranslationService.translate(context, 'sub_categories') ??
                      'Sub-categories',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Category cards grid
              Expanded(
                child: hasChildren
                    ? GridView.builder(
                        controller: scrollController,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 1.8,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        itemCount: children.length,
                        itemBuilder: (context, index) {
                          return _buildCategoryCard(children[index], theme);
                        },
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_open,
                              size: 48,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              TranslationService.translate(
                                    context,
                                    'no_sub_shelves',
                                  ) ??
                                  'No sub-shelves',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBreadcrumbs(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Home / All shelves
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _navigateToPath(-1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.home,
                    size: 18,
                    color: _currentLevel == null
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    TranslationService.translate(context, 'all_shelves') ??
                        'All Shelves',
                    style: TextStyle(
                      fontWeight: _currentLevel == null
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: _currentLevel == null
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Path segments
          for (int i = 0; i < _path.length; i++) ...[
            Icon(
              Icons.chevron_right,
              size: 20,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _navigateToPath(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  _path[i].name,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ],

          // Current level
          if (_currentLevel != null) ...[
            Icon(
              Icons.chevron_right,
              size: 20,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                _currentLevel!.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCurrentShelfCard(ThemeData theme) {
    final aggregatedCount = Tag.getAggregatedCount(_currentLevel!, widget.tags);

    return Card(
      elevation: 2,
      color: theme.colorScheme.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _selectCurrent,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.folder,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentLevel!.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (TranslationService.translate(
                                context,
                                'shelf_books_count',
                              ) ??
                              '%d books')
                          .replaceAll('%d', aggregatedCount.toString()),
                      style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _selectCurrent,
                icon: const Icon(Icons.filter_list, size: 18),
                label: Text(
                  TranslationService.translate(context, 'browse_shelf') ??
                      'Browse',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryCard(Tag tag, ThemeData theme) {
    final hasChildren = Tag.getDirectChildren(tag.id, widget.tags).isNotEmpty;
    final aggregatedCount = Tag.getAggregatedCount(tag, widget.tags);

    return Card(
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (hasChildren) {
            _drillDown(tag);
          } else {
            // No children, directly select
            widget.onShelfSelected(tag, [
              ..._path,
              if (_currentLevel != null) _currentLevel!,
            ]);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.surface,
                theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(
                    hasChildren ? Icons.folder : Icons.label,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                  if (hasChildren)
                    Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      size: 20,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                tag.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                (TranslationService.translate(context, 'shelf_books_count') ??
                        '%d books')
                    .replaceAll('%d', aggregatedCount.toString()),
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
