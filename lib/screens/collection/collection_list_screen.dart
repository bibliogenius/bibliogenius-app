import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../data/repositories/collection_repository.dart';
import '../../services/translation_service.dart';
import '../../models/collection.dart';
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

  @override
  void initState() {
    super.initState();
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
          TextButton.icon(
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
          const SizedBox(width: 4),
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

    return Column(
      children: [
        _buildCollectionsCountBadge(context, _collections.length),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadCollections,
            child: GridView.builder(
              padding: EdgeInsets.only(
                top: topPadding,
                left: 16,
                right: 16,
                bottom: 80,
              ),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
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
