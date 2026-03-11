import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/translation_service.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/scaffold_with_nav.dart';
import '../widgets/configurable_action_card.dart';
import '../widgets/contextual_help_sheet.dart';
import '../widgets/invite_share_sheet.dart';
import '../widgets/quick_actions_sheet.dart';
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
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final collectionEnabled = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).collectionsEnabled;
    // 3 tabs if collections enabled, else 2
    final length = collectionEnabled ? 3 : 2;
    _tabController = TabController(
      length: length,
      vsync: this,
      initialIndex: widget.initialIndex < length ? widget.initialIndex : 0,
    );
    _tabController.addListener(_handleTabSelection);
  }

  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialIndex != oldWidget.initialIndex) {
      _tabController.animateTo(widget.initialIndex, duration: Duration.zero);
    }
    // Trigger rebuild when shelfTagFilter changes
    if (widget.shelfTagFilter != oldWidget.shelfTagFilter) {
      setState(() {});
    }
  }

  void _handleTabSelection() {
    setState(() {});
  }

  final ValueNotifier<int> _refreshNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _shelvesRefreshNotifier = ValueNotifier<int>(0);
  int _collectionsRefreshKey = 0;

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    _refreshNotifier.dispose();
    _shelvesRefreshNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final width = MediaQuery.of(context).size.width;
    final isMobile = width <= 600;

    // Get filter tag to force rebuild of BookListScreen when it changes
    final tagFilter = GoRouterState.of(context).uri.queryParameters['tag'];

    return Scaffold(
      appBar: GenieAppBar(
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
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          onTap: (index) {
            switch (index) {
              case 0:
                context.go('/books');
                break;
              case 1:
                context.go('/shelves');
                break;
              case 2:
                if (themeProvider.collectionsEnabled) {
                  context.go('/collections');
                }
                break;
            }
          },
          tabs: [
            Tab(
              icon: const Icon(Icons.book),
              text: TranslationService.translate(context, 'books'),
            ),
            Tab(
              icon: const Icon(Icons.shelves),
              text: TranslationService.translate(context, 'shelves'),
            ),
            if (themeProvider.collectionsEnabled)
              Tab(
                icon: const Icon(Icons.collections_bookmark),
                text: TranslationService.translate(context, 'collections'),
              ),
          ],
        ),
        contextualQuickActions: _buildQuickActions(context),
        onBookAdded: () => _refreshNotifier.value++,
        onShelfCreated: () => _shelvesRefreshNotifier.value++,
        preSelectedShelfId: widget.shelfTagFilter,
        destinationName: widget.shelfTagFilter,
      ),
      body: IndexedStack(
        index: _tabController.index,
        children: [
          BookListScreen(
            key: ValueKey(tagFilter),
            isTabView: true,
            refreshNotifier: _refreshNotifier,
          ),
          // Show filtered books when a shelf tag is selected, otherwise show shelves grid
          widget.shelfTagFilter != null
              ? BookListScreen(
                  key: ValueKey('shelf_${widget.shelfTagFilter}'),
                  isTabView: true,
                  refreshNotifier: _refreshNotifier,
                  initialTagFilter: widget.shelfTagFilter,
                  showBackToShelves: true,
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
      floatingActionButton: _tabController.index == 0 ||
              (_tabController.index == 1 && widget.shelfTagFilter != null)
          ? FloatingActionButton(
              heroTag: 'library_add_fab',
              key: const Key('addBookButton'),
              onPressed: () async {
                final extra = <String, dynamic>{};
                if (_tabController.index == 1 &&
                    widget.shelfTagFilter != null) {
                  extra['shelfId'] = widget.shelfTagFilter;
                  extra['shelfName'] = widget.shelfTagFilter;
                }
                final result = await context.push(
                  '/books/add',
                  extra: extra.isNotEmpty ? extra : null,
                );
                if (result != null) {
                  _refreshNotifier.value++;
                  if (result is int) {
                    context.push('/books/$result');
                  }
                }
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  List<Widget> _buildQuickActions(BuildContext context) {
    // Books Tab (Index 0) and Shelves Tab (Index 1): same layout
    if (_tabController.index == 0 || _tabController.index == 1) {
      return [
        Builder(builder: (sheetContext) {
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
                  defaultActionId: 'share_library',
                  allowedActionIds: const [
                    'share_library',
                    'batch_scan',
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
        }),
      ];
    }

    // Collections Tab (Index 2 if enabled)
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    if (themeProvider.collectionsEnabled && _tabController.index == 2) {
      return [
        Builder(builder: (sheetContext) {
          return Row(
            children: [
              Expanded(
                child: QuickActionCard(
                  icon: Icons.auto_awesome,
                  color: Colors.purple,
                  label: TranslationService.translate(
                      sheetContext, 'discover'),
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
                      sheetContext, 'import_list'),
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
        }),
      ];
    }

    return [];
  }
}
