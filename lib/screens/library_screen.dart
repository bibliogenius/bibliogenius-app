import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../services/translation_service.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/scaffold_with_nav.dart';
import '../widgets/configurable_action_card.dart';
import '../widgets/contextual_help_sheet.dart';
import '../widgets/quick_actions_sheet.dart';
import '../widgets/sticky_tabs_header.dart';
import '../providers/theme_provider.dart';
import 'book_list_screen.dart';
import 'shelves_screen.dart';
import 'collection/collection_list_screen.dart';
import 'collection/import_curated_list_screen.dart' as import_curated;
import 'collection/import_shared_list_screen.dart';

class LibraryScreen extends StatefulWidget {
  final int initialIndex;
  final String? shelfTagFilter;

  const LibraryScreen({super.key, this.initialIndex = 0, this.shelfTagFilter});

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
    if (widget.initialIndex != oldWidget.initialIndex) {
      _tabController.animateTo(widget.initialIndex, duration: Duration.zero);
    }
    if (widget.shelfTagFilter != oldWidget.shelfTagFilter) {
      setState(() {});
    }
  }

  void _handleTabSelection() {
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
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
      actions: [
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
              ),
            ),
          ],
          body: IndexedStack(
            sizing: StackFit.expand,
            index: _tabController.index,
            children: [
              BookListScreen(
                key: ValueKey(tagFilter),
                isTabView: true,
                refreshNotifier: _refreshNotifier,
                externalSearchQuery: _searchQuery,
              ),
              widget.shelfTagFilter != null
                  ? BookListScreen(
                      key: ValueKey('shelf_${widget.shelfTagFilter}'),
                      isTabView: true,
                      refreshNotifier: _refreshNotifier,
                      initialTagFilter: widget.shelfTagFilter,
                      showBackToShelves: true,
                      externalSearchQuery: _searchQuery,
                    )
                  : ShelvesScreen(
                      isTabView: true,
                      refreshNotifier: _shelvesRefreshNotifier,
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
                        extra['shelfId'] = widget.shelfTagFilter;
                        extra['shelfName'] = widget.shelfTagFilter;
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
                          if (result is int) {
                            router.push('/books/$result');
                          }
                        }
                      }
                    },
                    child: const Icon(Icons.qr_code_scanner, size: 22),
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
                        extra['shelfId'] = widget.shelfTagFilter;
                        extra['shelfName'] = widget.shelfTagFilter;
                      }
                      final result = await router.push(
                        '/books/add',
                        extra: extra.isNotEmpty ? extra : null,
                      );
                      if (result != null && mounted) {
                        _refreshNotifier.value++;
                        if (result is int) {
                          router.push('/books/$result');
                        }
                      }
                    },
                    child: const Icon(Icons.add, size: 22),
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
