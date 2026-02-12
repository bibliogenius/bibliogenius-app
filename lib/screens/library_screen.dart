import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/translation_service.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/contextual_help_sheet.dart';
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
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
              )
            : null,
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
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              heroTag: 'library_add_fab',
              key: const Key('addBookButton'),
              onPressed: () async {
                final result = await context.push('/books/add');
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
    final batchScanTile = ListTile(
      leading: const Icon(Icons.document_scanner, color: Colors.deepOrange),
      title: Text(
        TranslationService.translate(context, 'batch_scan_title') ??
            'Batch Scan',
      ),
      subtitle: Text(
        TranslationService.translate(context, 'batch_scan_desc') ??
            'Scan multiple books in a row',
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      onTap: () {
        Navigator.pop(context);
        context.push('/scan', extra: {'batch': true});
      },
    );

    // Books Tab (Index 0)
    if (_tabController.index == 0) {
      return [batchScanTile];
    }

    // Shelves Tab (Index 1)
    if (_tabController.index == 1) {
      return [
        batchScanTile,
        ListTile(
          leading: const Icon(Icons.settings, color: Colors.blueGrey),
          title: Text(
            TranslationService.translate(context, 'manage_shelves') ??
                'Manage Shelves',
          ),
          subtitle: Text(
            TranslationService.translate(context, 'manage_shelves_desc') ??
                'Rename, delete or reorganize shelves',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          onTap: () {
            Navigator.pop(context);
            context.push('/shelves-management');
          },
        ),
      ];
    }

    // Collections Tab (Index 2 if enabled)
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    if (themeProvider.collectionsEnabled && _tabController.index == 2) {
      return [
        ListTile(
          leading: const Icon(Icons.auto_awesome, color: Colors.purple),
          title: Text(
            TranslationService.translate(context, 'discover') ?? 'Discover',
          ),
          onTap: () async {
            Navigator.pop(context);
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    const import_curated.ImportCuratedListScreen(),
              ),
            );
            if (result == true && mounted) {
              _refreshNotifier.value++; // Refresh book list
              setState(() {
                _collectionsRefreshKey++; // Refresh collections list
              });
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.file_open, color: Colors.blue),
          title: Text(
            TranslationService.translate(context, 'import_list') ??
                'Import List',
          ),
          onTap: () async {
            Navigator.pop(context);
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ImportSharedListScreen(),
              ),
            );
            if (result == true && mounted) {
              _refreshNotifier.value++; // Refresh book list
              setState(() {
                _collectionsRefreshKey++; // Refresh collections list
              });
            }
          },
        ),
      ];
    }

    return [];
  }
}
