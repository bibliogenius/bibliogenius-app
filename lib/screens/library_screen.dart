import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../services/translation_service.dart';
import '../models/tag.dart';
import '../providers/book_refresh_notifier.dart';
import '../theme/app_design.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/shelf_actions.dart';
import '../widgets/shelf_fan_flight.dart';
import '../widgets/shelf_place_header.dart';
import '../widgets/suggestions_app_bar_action.dart';
import '../widgets/scaffold_with_nav.dart';
import '../widgets/configurable_action_card.dart';
import '../widgets/contextual_help_sheet.dart';
import '../widgets/quick_actions_sheet.dart';
import '../widgets/sticky_tabs_header.dart';
import '../providers/theme_provider.dart';
import '../data/repositories/book_repository.dart';
import 'book_list_screen.dart';
import 'shelves_screen.dart';
import 'collection/collection_list_screen.dart';
import 'collection/import_curated_list_screen.dart' as import_curated;
import 'collection/import_shared_list_screen.dart';

class LibraryScreen extends StatefulWidget {
  final int initialIndex;
  final String? shelfTagFilter;

  /// The shelves tab lists the books on no shelf instead of the grid: where
  /// the "to shelve" card leads.
  final bool shelfUnshelvedFilter;

  /// That list opens with selection mode armed.
  final bool shelfSelectOnOpen;

  const LibraryScreen({
    super.key,
    this.initialIndex = 0,
    this.shelfTagFilter,
    this.shelfUnshelvedFilter = false,
    this.shelfSelectOnOpen = false,
  });

  /// The `/shelves` route: `?tag=` opens a shelf's books, `?unshelved=1` the
  /// books on no shelf (`&select=1` arms selection). Both render in the
  /// shelves tab, so back returns to the grid.
  factory LibraryScreen.forShelvesUri(Uri uri) {
    final query = uri.queryParameters;
    return LibraryScreen(
      initialIndex: 1,
      shelfTagFilter: query['tag'],
      shelfUnshelvedFilter: query['unshelved'] == '1',
      shelfSelectOnOpen: query['select'] == '1',
    );
  }

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late bool _collectionsEnabled;

  final ValueNotifier<int> _refreshNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _shelvesRefreshNotifier = ValueNotifier<int>(0);
  int _collectionsRefreshKey = 0;

  final GlobalKey<NestedScrollViewState> _scrollKey =
      GlobalKey<NestedScrollViewState>();

  /// The head of the shelf page on show, published by its list of books.
  final ValueNotifier<ShelfPlace?> _place = ValueNotifier<ShelfPlace?>(null);

  /// Shelves as last listed: the next shelf page draws its head from them
  /// while its books load.
  List<Tag>? _knownTags;

  /// The waiting deletion and the Undos of the shelves tab and the shelf
  /// pages. Here because a deletion from a page shows its Undo on the parent
  /// page, which replaces it.
  late final ShelfActionsController _shelfActions = ShelfActionsController(
    () => mounted ? context : null,
  );

  final ShelfFanFlight _fanFlight = ShelfFanFlight();

  /// Off while a page opened over the library hides it.
  ValueListenable<bool>? _tickerMode;

  // The contextual-help button is onboarding aid: show it only while the
  // library is still small (a new user). Once the shelf fills up the user
  // knows the ropes, and help stays reachable from the main menu. Null while
  // the count is loading (help shown by default so newcomers never miss it).
  static const int _kOnboardingHelpMaxBooks = 5;
  int? _bookCount;

  // Global search state (lifted from BookListScreen so the search field in the
  // sticky sliver header can drive filtering of the active tab's content).
  final ValueNotifier<String> _searchQuery = ValueNotifier<String>('');
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _collectionsEnabled = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).collectionsEnabled;
    _createTabController(widget.initialIndex);
    // Reload the count whenever the library content changes so the help button
    // disappears the moment the user crosses the onboarding threshold.
    _refreshNotifier.addListener(_loadBookCount);
    _loadBookCount();
  }

  Future<void> _loadBookCount() async {
    try {
      final books = await Provider.of<BookRepository>(
        context,
        listen: false,
      ).getBooks();
      if (mounted) setState(() => _bookCount = books.length);
    } catch (_) {
      // Non-critical: on failure keep the help visible (treat as a new user).
    }
  }

  void _createTabController(int initialIndex) {
    final length = _collectionsEnabled ? 3 : 2;
    _tabController = TabController(
      length: length,
      vsync: this,
      initialIndex: initialIndex < length ? initialIndex : 0,
    );
    _tabController.addListener(_handleTabSelection);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shelfActions.onWritten ??= context.read<BookRefreshNotifier>().refresh;
    final tickerMode = TickerMode.getNotifier(context);
    if (!identical(tickerMode, _tickerMode)) {
      _tickerMode?.removeListener(_onTickerModeChanged);
      _tickerMode = tickerMode..addListener(_onTickerModeChanged);
    }
    final newEnabled = Provider.of<ThemeProvider>(context).collectionsEnabled;
    if (newEnabled != _collectionsEnabled) {
      _collectionsEnabled = newEnabled;
      final currentIndex = _tabController.index;
      _tabController.removeListener(_handleTabSelection);
      _tabController.dispose();
      _createTabController(currentIndex);
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final otherTab = widget.initialIndex != oldWidget.initialIndex;
    if (otherTab) {
      _tabController.animateTo(widget.initialIndex, duration: Duration.zero);
    }
    final otherShelf = widget.shelfTagFilter != oldWidget.shelfTagFilter;
    if (otherTab ||
        otherShelf ||
        widget.shelfUnshelvedFilter != oldWidget.shelfUnshelvedFilter ||
        widget.shelfSelectOnOpen != oldWidget.shelfSelectOnOpen) {
      // Walking to another page is leaving, unless the page itself sent the
      // reader there with an Undo to show. The library tabs share this screen:
      // their routes reuse it, so changing tab comes through here too.
      if (!_shelfActions.consumeLanding()) _shelfActions.leave();
      setState(() {});
    }
    if (otherShelf) _scrollToTop();
  }

  /// A page starts at its own top, not where the last one was left: the head
  /// of the page is in the scroll view the pages share.
  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final outer = _scrollKey.currentState?.outerController;
      if (outer != null && outer.hasClients) outer.jumpTo(0);
    });
  }

  void _onTickerModeChanged() {
    if (_tickerMode?.value == false) _shelfActions.leave();
  }

  void _handleTabSelection() {
    setState(() {});
  }

  @override
  void dispose() {
    _fanFlight.cancel();
    _tickerMode?.removeListener(_onTickerModeChanged);
    _shelfActions.dispose();
    _place.dispose();
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    _refreshNotifier.removeListener(_loadBookCount);
    _refreshNotifier.dispose();
    _shelvesRefreshNotifier.dispose();
    _searchQuery.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _openSearch() {
    // Search is book-scoped: if the user taps search from Étagères/Collections,
    // switch back to the Livres tab so they see the list they're filtering.
    if (_tabController.index != 0) {
      _tabController.animateTo(0);
      context.go('/books');
    }
    setState(() => _isSearching = true);
  }

  /// The open shelf as it is named, whatever the case of the link: filing on
  /// the name of the link would make a second shelf.
  String? get _openShelfName {
    final requested = widget.shelfTagFilter;
    return Tag.byName(_knownTags ?? const [], requested)?.name ?? requested;
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _searchQuery.value = '';
    setState(() => _isSearching = false);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _searchQuery.value = value;
    });
  }

  void _onTabTap(int index) {
    switch (index) {
      case 0:
        context.go('/books');
        break;
      case 1:
        context.go('/shelves');
        break;
      case 2:
        final themeProvider = Provider.of<ThemeProvider>(
          context,
          listen: false,
        );
        if (themeProvider.collectionsEnabled) {
          context.go('/collections');
        }
        break;
    }
  }

  List<Tab> _buildTabs(bool collectionsEnabled) {
    return [
      Tab(text: TranslationService.translate(context, 'books')),
      Tab(text: TranslationService.translate(context, 'shelves')),
      if (collectionsEnabled)
        Tab(text: TranslationService.translate(context, 'collections')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    // Get filter tag to force rebuild of BookListScreen when it changes
    final tagFilter = GoRouterState.of(context).uri.queryParameters['tag'];

    final genieAppBar = GenieAppBar(
      title: TranslationService.translate(context, 'library'),
      leading: buildDrawerLeading(context),
      automaticallyImplyLeading: false,
      headerSearch: IconButton(
        icon: const Icon(Icons.search, color: Colors.white),
        tooltip: TranslationService.translate(context, 'search_books'),
        onPressed: _openSearch,
        style: AppDesign.headerIconButtonStyle(),
      ),
      actions: [
        // The direct path to the suggestions (ADR-062 R4) belongs HERE, not
        // in BookListScreen: /books renders it with isTabView, a branch that
        // has no app bar of its own, so an action placed there is invisible
        // on the very screen R4 exists to serve.
        SuggestionsAppBarAction(
          color: Colors.white,
          style: AppDesign.headerIconButtonStyle(),
        ),
        if (_bookCount == null || _bookCount! < _kOnboardingHelpMaxBooks)
          ContextualHelpIconButton(
            titleKey: 'help_ctx_library_title',
            contentKey: 'help_ctx_library_content',
            tips: const [
              HelpTip(
                icon: Icons.add_circle,
                color: Colors.blue,
                titleKey: 'help_ctx_library_tip_add',
                descriptionKey: 'help_ctx_library_tip_add_desc',
              ),
              HelpTip(
                icon: Icons.shelves,
                color: Colors.green,
                titleKey: 'help_ctx_library_tip_shelves',
                descriptionKey: 'help_ctx_library_tip_shelves_desc',
              ),
              HelpTip(
                icon: Icons.search,
                color: Colors.orange,
                titleKey: 'help_ctx_library_tip_search',
                descriptionKey: 'help_ctx_library_tip_search_desc',
              ),
            ],
          ),
      ],
      contextualQuickActions: _buildQuickActions(context),
      onBookAdded: () => _refreshNotifier.value++,
      onShelfCreated: () => _shelvesRefreshNotifier.value++,
      preSelectedShelfId: widget.shelfTagFilter,
      destinationName: widget.shelfTagFilter,
    );

    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: NestedScrollView(
          key: _scrollKey,
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverPersistentHeader(
              pinned: true,
              delegate: StatusBarCoverHeader(
                height: topInset,
                themeStyle: themeProvider.themeStyle,
              ),
            ),
            GenieSliverAppBar(
              source: genieAppBar,
              floating: true,
              snap: true,
              pinned: false,
              forceElevated: innerBoxIsScrolled,
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: StickyTabsHeader(
                tabController: _tabController,
                tabs: _buildTabs(themeProvider.collectionsEnabled),
                themeStyle: themeProvider.themeStyle,
                onTabTap: _onTabTap,
                isSearching: _isSearching,
                searchController: _searchController,
                onOpenSearch: _openSearch,
                onCloseSearch: _closeSearch,
                onSearchChanged: _onSearchChanged,
                showSearchButton: false,
              ),
            ),
            if (_tabController.index == 1 &&
                widget.shelfTagFilter != null &&
                !widget.shelfUnshelvedFilter)
              ValueListenableBuilder<ShelfPlace?>(
                valueListenable: _place,
                builder: (context, place, _) {
                  // Nothing for another shelf's page still in the notifier.
                  if (place == null ||
                      place.hidden ||
                      place.requestedName != widget.shelfTagFilter) {
                    return const SliverToBoxAdapter();
                  }
                  return ShelfPlaceSlivers(place: place);
                },
              ),
          ],
          // The IndexedStack keeps every tab mounted, so all of their scroll
          // views stay attached to the single PrimaryScrollController that
          // NestedScrollView injects into its body. On desktop the default
          // ScrollBehavior wraps each vertical scroll view in a Scrollbar,
          // which requires exactly one attached ScrollPosition and throws
          // "attached to more than one ScrollPosition" on every scroll frame.
          // Dropping the scrollbars here keeps the sliver header coordination
          // intact; the scrollbars could not paint anyway.
          body: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: IndexedStack(
              sizing: StackFit.expand,
              index: _tabController.index,
              children: [
                BookListScreen(
                  key: ValueKey(tagFilter),
                  isTabView: true,
                  refreshNotifier: _refreshNotifier,
                  externalSearchQuery: _searchQuery,
                  onCloseHeaderSearch: _closeSearch,
                ),
                widget.shelfTagFilter != null || widget.shelfUnshelvedFilter
                    ? BookListScreen(
                        // A new list for each filter: the state of one shelf's
                        // list (selection, scope) must not carry over.
                        key: ValueKey(
                          widget.shelfUnshelvedFilter
                              ? 'shelf_unshelved'
                              : 'shelf_${widget.shelfTagFilter}',
                        ),
                        isTabView: true,
                        refreshNotifier: _refreshNotifier,
                        initialTagFilter: widget.shelfTagFilter,
                        unshelvedOnly: widget.shelfUnshelvedFilter,
                        startInSelection: widget.shelfSelectOnOpen,
                        showBackToShelves: true,
                        externalSearchQuery: _searchQuery,
                        onCloseHeaderSearch: _closeSearch,
                        placeNotifier: _place,
                        shelfActions: _shelfActions,
                        initialTags: _knownTags,
                        onTagsLoaded: (tags) => _knownTags = tags,
                        fanFlight: _fanFlight,
                      )
                    : ShelvesScreen(
                        isTabView: true,
                        refreshNotifier: _shelvesRefreshNotifier,
                        actions: _shelfActions,
                        onTagsLoaded: (tags) => _knownTags = tags,
                        fanFlight: _fanFlight,
                      ),
                if (themeProvider.collectionsEnabled)
                  CollectionListScreen(
                    key: ValueKey('collections_$_collectionsRefreshKey'),
                    isTabView: true,
                    onImportSuccess: () {
                      _refreshNotifier.value++;
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton:
          _tabController.index == 0 ||
              (_tabController.index == 1 && widget.shelfTagFilter != null)
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: FloatingActionButton(
                    heroTag: 'library_scan_fab',
                    onPressed: () async {
                      final router = GoRouter.of(context);
                      final extra = <String, dynamic>{};
                      if (_tabController.index == 1 &&
                          widget.shelfTagFilter != null) {
                        extra['shelfId'] = _openShelfName!;
                        extra['shelfName'] = _openShelfName!;
                      }
                      final isbn = await router.push<String>(
                        '/scan',
                        extra: extra.isNotEmpty ? extra : null,
                      );
                      if (isbn != null && mounted) {
                        extra['isbn'] = isbn;
                        final result = await router.push(
                          '/books/add',
                          extra: extra,
                        );
                        if (result != null && mounted) {
                          _refreshNotifier.value++;
                          if (result is String) {
                            router.push('/books/$result');
                          }
                        }
                      }
                    },
                    // The icon's label names the button: a FAB has no text
                    // and, without it, is announced as a bare "button".
                    child: Icon(
                      Icons.qr_code_scanner,
                      size: 22,
                      semanticLabel: TranslationService.translate(
                        context,
                        'scan_isbn',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: FloatingActionButton(
                    heroTag: 'library_add_fab',
                    key: const Key('addBookButton'),
                    onPressed: () async {
                      final router = GoRouter.of(context);
                      final extra = <String, dynamic>{};
                      if (_tabController.index == 1 &&
                          widget.shelfTagFilter != null) {
                        extra['shelfId'] = _openShelfName!;
                        extra['shelfName'] = _openShelfName!;
                      }
                      final result = await router.push(
                        '/books/add',
                        extra: extra.isNotEmpty ? extra : null,
                      );
                      if (result != null && mounted) {
                        _refreshNotifier.value++;
                        if (result is String) {
                          router.push('/books/$result');
                        }
                      }
                    },
                    child: Icon(
                      Icons.add,
                      size: 22,
                      semanticLabel: TranslationService.translate(
                        context,
                        'add_book_button',
                      ),
                    ),
                  ),
                ),
              ],
            )
          : null,
    );
  }

  List<Widget> _buildQuickActions(BuildContext context) {
    // Books Tab (Index 0) and Shelves Tab (Index 1): same layout
    if (_tabController.index == 0 || _tabController.index == 1) {
      return [
        Builder(
          builder: (sheetContext) {
            final handlers = QuickActionsSheet.buildCommonHandlers(
              sheetContext,
              onDone: () {
                _refreshNotifier.value++;
                _shelvesRefreshNotifier.value++;
              },
            );
            final slotPrefix = _tabController.index == 0
                ? 'library_books'
                : 'library_shelves';
            return Row(
              children: [
                Expanded(
                  child: ConfigurableActionCard(
                    slotKey: '${slotPrefix}_slot_1',
                    defaultActionId: 'batch_scan',
                    allowedActionIds: const [
                      'batch_scan',
                      'share_library',
                      'manage_shelves',
                      'inventory',
                      'create_shelf',
                      'import_csv',
                    ],
                    handlers: handlers,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ConfigurableActionCard(
                    slotKey: '${slotPrefix}_slot_2',
                    defaultActionId: 'create_shelf',
                    allowedActionIds: const [
                      'create_shelf',
                      'batch_scan',
                      'manage_shelves',
                      'inventory',
                      'share_library',
                      'import_csv',
                    ],
                    handlers: handlers,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ConfigurableActionCard(
                    slotKey: '${slotPrefix}_slot_3',
                    defaultActionId: 'manage_shelves',
                    allowedActionIds: const [
                      'manage_shelves',
                      'batch_scan',
                      'share_library',
                      'inventory',
                      'create_shelf',
                      'import_csv',
                    ],
                    handlers: handlers,
                  ),
                ),
              ],
            );
          },
        ),
      ];
    }

    // Collections Tab (Index 2 if enabled)
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    if (themeProvider.collectionsEnabled && _tabController.index == 2) {
      return [
        Builder(
          builder: (sheetContext) {
            return Row(
              children: [
                Expanded(
                  child: QuickActionCard(
                    icon: Icons.auto_awesome,
                    color: Colors.purple,
                    label: TranslationService.translate(
                      sheetContext,
                      'discover',
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const import_curated.ImportCuratedListScreen(),
                        ),
                      );
                      if (result == true && mounted) {
                        _refreshNotifier.value++;
                        setState(() {
                          _collectionsRefreshKey++;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: QuickActionCard(
                    icon: Icons.file_open,
                    color: Colors.blue,
                    label: TranslationService.translate(
                      sheetContext,
                      'import_list',
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ImportSharedListScreen(),
                        ),
                      );
                      if (result == true && mounted) {
                        _refreshNotifier.value++;
                        setState(() {
                          _collectionsRefreshKey++;
                        });
                      }
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ];
    }

    return [];
  }
}
