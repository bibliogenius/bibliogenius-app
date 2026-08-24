import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../data/repositories/collection_repository.dart';
import '../../providers/book_refresh_notifier.dart';
import '../../providers/recommendation_provider.dart';
import '../../services/translation_service.dart';
import '../../theme/app_design.dart';
import '../../models/collection.dart';
import '../../utils/recommendation_display.dart';
import '../../widgets/curated_import_dialog.dart';
import '../../widgets/curated_list_suggestion_card.dart';
import 'import_curated_list_screen.dart' as import_curated;
import 'import_shared_list_screen.dart';
import '../../widgets/genie_app_bar.dart';
import '../../widgets/scaffold_with_nav.dart';
import '../../widgets/contextual_help_sheet.dart';
import '../../widgets/collection_stack_widget.dart';
import 'collection_delete_dialog.dart';

class CollectionListScreen extends StatefulWidget {
  final bool isTabView;
  final VoidCallback? onImportSuccess;

  const CollectionListScreen({
    super.key,
    this.isTabView = false,
    this.onImportSuccess,
  });

  @override
  State<CollectionListScreen> createState() => _CollectionListScreenState();
}

class _CollectionListScreenState extends State<CollectionListScreen> {
  List<Collection> _collections = [];
  Map<String, List<String?>> _coverUrls = {};
  bool _isLoading = true;
  String? _error;
  BookRefreshNotifier? _bookRefreshNotifier;

  @override
  void initState() {
    super.initState();
    _loadCollections();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bookRefreshNotifier = context.read<BookRefreshNotifier>();
      _bookRefreshNotifier?.addListener(_handleBookRefresh);
    });
  }

  @override
  void dispose() {
    _bookRefreshNotifier?.removeListener(_handleBookRefresh);
    super.dispose();
  }

  void _handleBookRefresh() {
    if (!mounted) return;
    _loadCollections();
  }

  Future<void> _loadCollections() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final collectionRepo = context.read<CollectionRepository>();
      final collections = await collectionRepo.getCollections();

      // Fetch cover URLs for each collection (up to 4 per collection).
      final Map<String, List<String?>> covers = {};
      for (final collection in collections) {
        final books = await collectionRepo.getCollectionBooks(collection.id);
        covers[collection.id] = books
            .where((b) => b.coverUrl != null && b.coverUrl!.isNotEmpty)
            .map((b) => b.coverUrl)
            .take(4)
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _collections = collections;
        _coverUrls = covers;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _createCollection() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            TranslationService.translate(context, 'create_collection'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: TranslationService.translate(context, 'name'),
                ),
              ),
              TextField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: TranslationService.translate(
                    context,
                    'description',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(TranslationService.translate(context, 'cancel')),
            ),
            FilledButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  try {
                    final collectionRepo = Provider.of<CollectionRepository>(
                      context,
                      listen: false,
                    );
                    await collectionRepo.createCollection(
                      nameController.text,
                      description: descriptionController.text.isEmpty
                          ? null
                          : descriptionController.text,
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      _loadCollections();
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                }
              },
              child: Text(TranslationService.translate(context, 'create')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteCollection(Collection collection) async {
    final repo = Provider.of<CollectionRepository>(context, listen: false);
    final outcome = await confirmCollectionDeletion(
      context,
      repo,
      collection.id,
    );
    if (outcome == CollectionDeleteOutcome.cancelled) return;
    if (!mounted) return;

    try {
      if (outcome == CollectionDeleteOutcome.withBooks) {
        await repo.deleteCollectionWithBooks(collection.id);
      } else {
        await repo.deleteCollection(collection.id);
      }
      // The reader has taken their import back; the app takes its own
      // dismissal back too, or the list can never be suggested again.
      if (mounted) await forgetCuratedListDismissal(context, collection);
      if (mounted) _loadCollections();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_deleting_collection')}: $e',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isMobile = width <= 600;

    PreferredSizeWidget? appBar;
    if (!widget.isTabView) {
      appBar = GenieAppBar(
        title: TranslationService.translate(context, 'collections'),
        leading: buildDrawerLeading(context),
        automaticallyImplyLeading: false,
        showQuickActions: true,
        actions: [
          // Header actions carry their own 4px margin (see GenieAppBar).
          // Unlike an IconButton, this pill has no invisible tap-target
          // margin: its background reaches the widget edge, so it needs an
          // explicit 4px on each side to keep the uniform 8px visible gap.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: Text(TranslationService.translate(context, 'discover')),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        const import_curated.ImportCuratedListScreen(),
                  ),
                );
                if (result == true) {
                  _loadCollections();
                  widget.onImportSuccess?.call();
                }
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.file_open, color: Colors.white),
            tooltip: TranslationService.translate(context, 'import'),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ImportSharedListScreen(),
                ),
              );
              if (result == true) {
                _loadCollections();
                widget.onImportSuccess?.call();
              }
            },
          ),
          const SizedBox(width: 4),
          ContextualHelpIconButton(
            titleKey: 'help_ctx_collections_title',
            contentKey: 'help_ctx_collections_content',
            tips: const [
              HelpTip(
                icon: Icons.add_circle,
                color: Colors.blue,
                titleKey: 'help_ctx_collections_tip_create',
                descriptionKey: 'help_ctx_collections_tip_create_desc',
              ),
              HelpTip(
                icon: Icons.reorder,
                color: Colors.green,
                titleKey: 'help_ctx_collections_tip_order',
                descriptionKey: 'help_ctx_collections_tip_order_desc',
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: !widget.isTabView,
      appBar: appBar,
      body: _buildBody(context),
      floatingActionButton: FloatingActionButton(
        heroTag: 'collection_add_fab',
        onPressed: _createCollection,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }
    if (_collections.isEmpty) {
      return _buildEmptyState(context);
    }
    return _buildGrid(context);
  }

  Widget _buildGrid(BuildContext context) {
    final topPadding = widget.isTabView
        ? 8.0
        : MediaQuery.of(context).padding.top + kToolbarHeight;

    // A CustomScrollView rather than a GridView: the curated teaser block
    // has to sit AFTER the reader's own collections IN THE SAME SCROLL, so
    // their content always comes first and the block is reached by reading
    // past it, never by pushing it down.
    return Column(
      children: [
        _buildCollectionsCountBadge(context, _collections.length),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadCollections,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(
                    top: topPadding,
                    left: 16,
                    right: 16,
                  ),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          childAspectRatio: 0.62,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: _collections.length,
                    itemBuilder: (context, index) {
                      final collection = _collections[index];
                      final covers = _coverUrls[collection.id] ?? [];
                      return CollectionCoverCard(
                        collection: collection,
                        coverUrls: covers,
                        onTap: () async {
                          await context.push(
                            '/collections/${collection.id}',
                            extra: collection,
                          );
                          if (mounted) _loadCollections();
                        },
                        onLongPress: () => _deleteCollection(collection),
                      );
                    },
                  ),
                ),
                const SliverToBoxAdapter(child: _CuratedTeaserBlock()),
                const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final topPadding = widget.isTabView
        ? 24.0
        : MediaQuery.of(context).padding.top + kToolbarHeight + 24;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(
            top: topPadding,
            left: 24,
            right: 24,
            bottom: 24,
          ),
          sliver: SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.collections_bookmark,
                      size: 64,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    TranslationService.translate(context, 'no_collections'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      TranslationService.translate(
                        context,
                        'collection_empty_state_desc',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _createCollection,
                    icon: const Icon(Icons.add),
                    label: Text(
                      TranslationService.translate(
                        context,
                        'create_collection',
                      ),
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
                  const SizedBox(height: 48),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).primaryColor.withValues(alpha: 0.8),
                          Theme.of(context).primaryColor,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.auto_awesome,
                          size: 48,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          TranslationService.translate(
                            context,
                            'discover_collections_title',
                          ),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          TranslationService.translate(
                            context,
                            'discover_collections_subtitle',
                          ),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const import_curated.ImportCuratedListScreen(),
                              ),
                            );
                            if (result == true) {
                              _loadCollections();
                            }
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Theme.of(context).primaryColor,
                          ),
                          child: Text(
                            TranslationService.translate(
                              context,
                              'explore_collections',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCollectionsCountBadge(BuildContext context, int count) {
    final theme = Theme.of(context);
    final topPadding = widget.isTabView
        ? 8.0
        : MediaQuery.of(context).padding.top + kToolbarHeight + 8;
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: topPadding, bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.collections_bookmark,
                  size: 16,
                  color: theme.primaryColor,
                ),
                const SizedBox(width: 6),
                Text(
                  count == 1
                      ? (TranslationService.translate(
                                  context,
                                  'displayed_collections_count',
                                ) ??
                                '%d collection')
                            .replaceAll('%d', '$count')
                      : (TranslationService.translate(
                                  context,
                                  'displayed_collections_count_plural',
                                ) ??
                                '%d collections')
                            .replaceAll('%d', '$count'),
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
      ),
    );
  }
}

/// Curated selections related to the reader's library (ADR-066), shown in
/// the POPULATED state of this screen, after their own collections.
///
/// It fills a verified gap: the prominent "discover collections" banner
/// exists in the empty state only, and the populated state offers nothing
/// but the app-bar pill, which the tab-view branch does not even render.
///
/// Below the affinity thresholds it renders nothing and occupies no height.
/// Never an empty or lukewarm block: a section header over zero cards would
/// be worse than the silence it replaces. The empty-state banner is left
/// exactly as it is, because it is onboarding and this is not.
///
/// It borrows the Activity strip's shape (see `RecentlyAddedCarousel`): one
/// outlined surface, an icon-and-title header, and a horizontal strip under
/// it. The app already says "here is a side offer, read past it or scroll
/// it" that way at the top of the library, so a second vocabulary here would
/// buy nothing. What it deliberately does NOT borrow is that widget itself:
/// its collapse and hide state is scoped to a library view and persisted per
/// scope, and a suggestion block on the Collections screen has no business
/// riding on it. Stacking full-width rows was the alternative, and it made
/// the page read as a second list of collections competing with the reader's
/// own, above a card whose text column was two words wide.
class _CuratedTeaserBlock extends StatelessWidget {
  const _CuratedTeaserBlock();

  @override
  Widget build(BuildContext context) {
    final affinities = context
        .watch<RecommendationProvider>()
        .curatedAffinitiesFor(
          cap: RecommendationProvider.collectionsMaxCuratedLists,
        );
    if (affinities.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      // Roomier above than the Activity strip is: this one follows a grid of
      // the reader's own collections and has to read as a separate offer,
      // not as its last row.
      padding: const EdgeInsets.fromLTRB(
        AppDesign.spacingMd,
        AppDesign.spacingLg,
        AppDesign.spacingMd,
        AppDesign.spacingSm,
      ),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.5),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDesign.spacingMd,
            AppDesign.spacingSm,
            AppDesign.spacingSm,
            AppDesign.spacingSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    // The icon the library slot already gives to discovery,
                    // as the Activity header gives its own the open book.
                    Icons.auto_awesome,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: AppDesign.spacingSm),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        TranslationService.translate(
                          context,
                          'curated_affinity_section_title',
                        ),
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDesign.spacingSm),
              // A scrolling Row rather than a horizontal ListView: the fan
              // cards size themselves from their content, so the strip has
              // no height to declare and a reader at 200% text size gets a
              // taller block instead of a clipped reason line. The cap is
              // two cards, so nothing here needs to be built lazily.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < affinities.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppDesign.spacingSm),
                      CuratedListSuggestionCard(
                        affinity: affinities[i],
                        // The page's own vocabulary: no book cards share
                        // this strip, so nothing holds the card to the
                        // library slot's two-book-slot grid.
                        layout: CuratedCardLayout.fan,
                        onTap: () => CuratedImportDialog.show(
                          context,
                          affinities[i].list,
                        ),
                        onDismiss: () => dismissCuratedListWithUndo(
                          context,
                          affinities[i].dismissalKey,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
