import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../data/repositories/tag_repository.dart';
import '../models/tag.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/contextual_help_sheet.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../providers/theme_provider.dart';
import '../utils/app_constants.dart';

class ShelvesScreen extends StatefulWidget {
  final bool isTabView;
  final ValueNotifier<int>? refreshNotifier;

  const ShelvesScreen({super.key, this.isTabView = false, this.refreshNotifier});

  @override
  State<ShelvesScreen> createState() => _ShelvesScreenState();
}

class _ShelvesScreenState extends State<ShelvesScreen> {
  late Future<List<Tag>> _tagsFuture;
  List<Tag> _allTags = [];
  Tag? _currentParent; // null = root level
  List<Tag> _path = []; // breadcrumb path

  @override
  void initState() {
    super.initState();
    _tagsFuture = Provider.of<TagRepository>(context, listen: false).getTags();
    widget.refreshNotifier?.addListener(_onRefreshRequested);
  }

  void _onRefreshRequested() {
    _refreshTags();
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_onRefreshRequested);
    super.dispose();
  }

  void _refreshTags() {
    setState(() {
      _tagsFuture = Provider.of<TagRepository>(context, listen: false).getTags();
      _currentParent = null;
      _path = [];
    });
  }

  /// Get tags to display at current level
  List<Tag> get _visibleTags {
    if (_currentParent == null) {
      // Show only root tags (no parent)
      return _allTags.where((t) => t.parentId == null).toList();
    } else {
      // Show direct children of current parent
      return _allTags.where((t) => t.parentId == _currentParent!.id).toList();
    }
  }

  /// Drill down into a tag's children
  void _drillDown(Tag tag) {
    final children = _allTags.where((t) => t.parentId == tag.id).toList();
    if (children.isNotEmpty) {
      setState(() {
        if (_currentParent != null) {
          _path.add(_currentParent!);
        }
        _currentParent = tag;
      });
    } else {
      // No children, navigate to books filtered by this tag
      context.go('/shelves?tag=${tag.name}');
    }
  }

  /// Go back one level
  void _goBack() {
    setState(() {
      if (_path.isNotEmpty) {
        _currentParent = _path.removeLast();
      } else {
        _currentParent = null;
      }
    });
  }

  /// Go to root
  void _goToRoot() {
    setState(() {
      _currentParent = null;
      _path = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isMobile = width <= 600;
    final themeStyle = Provider.of<ThemeProvider>(context).themeStyle;

    if (widget.isTabView) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton(
          heroTag: 'shelf_add_fab_tab',
          onPressed: _showCreateShelfDialog,
          child: const Icon(Icons.add),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: AppDesign.pageGradientForTheme(themeStyle),
          ),
          child: SafeArea(
            child: FutureBuilder<List<Tag>>(
              future: _tagsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return _buildErrorState(snapshot.error.toString());
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return _buildEmptyState(context);
                }

                _allTags = snapshot.data!;
                final visibleTags = _visibleTags;

                if (visibleTags.isEmpty && _currentParent != null) {
                  // Navigate logic handled in post frame
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    context.go('/shelves?tag=${_currentParent!.name}');
                  });
                  return const Center(child: CircularProgressIndicator());
                }

                return RefreshIndicator(
                  onRefresh: () async => _refreshTags(),
                  child: Column(
                    children: [
                      // Always show breadcrumb if parent != null, or even if root for consistency?
                      // Original code only showed if _currentParent != null
                      if (_currentParent != null) _buildBreadcrumb(context),

                      // Shelves count badge
                      if (visibleTags.isNotEmpty)
                        _buildShelvesCountBadge(context, visibleTags.length),

                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: GridView.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: isMobile ? 2 : 3,
                                  childAspectRatio: 1.2,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                ),
                            itemCount: visibleTags.length,
                            itemBuilder: (context, index) {
                              final tag = visibleTags[index];
                              return _buildShelfCard(context, tag, index);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'shelf_add_fab',
        onPressed: _showCreateShelfDialog,
        child: const Icon(Icons.add),
      ),
      appBar: GenieAppBar(
        title:
            _currentParent?.name ??
            (TranslationService.translate(context, 'shelves') ?? 'Shelves'),
        leading: _currentParent != null
            ? IconButton(
                icon: Icon(Icons.adaptive.arrow_back, color: Colors.white),
                onPressed: _goBack,
              )
            : (isMobile
                  ? IconButton(
                      icon: const Icon(Icons.menu, color: Colors.white),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    )
                  : null),
        automaticallyImplyLeading: false,
        showQuickActions: true,
        actions: [
          ContextualHelpIconButton(
            titleKey: 'help_ctx_shelves_title',
            contentKey: 'help_ctx_shelves_content',
            tips: const [
              HelpTip(
                icon: Icons.add_circle,
                color: Colors.blue,
                titleKey: 'help_ctx_shelves_tip_create',
                descriptionKey: 'help_ctx_shelves_tip_create_desc',
              ),
              HelpTip(
                icon: Icons.book,
                color: Colors.green,
                titleKey: 'help_ctx_shelves_tip_assign',
                descriptionKey: 'help_ctx_shelves_tip_assign_desc',
              ),
            ],
          ),
        ],
        contextualQuickActions: [
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: Text(
              TranslationService.translate(context, 'create_shelf') ??
                  'Create Shelf',
            ),
            onTap: () {
              Navigator.pop(context); // Close Quick Actions sheet
              _showCreateShelfDialog();
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: Text(
              TranslationService.translate(context, 'manage_shelves') ??
                  'Manage Shelves',
            ),
            onTap: () {
              Navigator.pop(context);
              context.push('/shelves-management');
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppDesign.pageGradientForTheme(themeStyle),
        ),
        child: FutureBuilder<List<Tag>>(
          future: _tagsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return _buildErrorState(snapshot.error.toString());
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return _buildEmptyState(context);
            }

            // Store all tags for hierarchy navigation
            _allTags = snapshot.data!;
            final visibleTags = _visibleTags;

            if (visibleTags.isEmpty && _currentParent != null) {
              // Current level has no children - show books for this tag
              WidgetsBinding.instance.addPostFrameCallback((_) {
                context.go('/shelves?tag=${_currentParent!.name}');
              });
              return const Center(child: CircularProgressIndicator());
            }

            return RefreshIndicator(
              onRefresh: () async => _refreshTags(),
              child: Column(
                children: [
                  // Breadcrumb navigation
                  if (_currentParent != null) _buildBreadcrumb(context),

                  // Shelves count badge
                  if (visibleTags.isNotEmpty)
                    _buildShelvesCountBadge(context, visibleTags.length),

                  // Grid of shelves
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isMobile ? 2 : 3,
                          childAspectRatio: 1.2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: visibleTags.length,
                        itemBuilder: (context, index) {
                          final tag = visibleTags[index];
                          return _buildShelfCard(context, tag, index);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Build breadcrumb navigation bar
  Widget _buildBreadcrumb(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
      child: Row(
        children: [
          // Home button
          InkWell(
            onTap: _goToRoot,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.home,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    TranslationService.translate(context, 'all_shelves') ??
                        'All',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Path segments
          ..._path.map(
            (tag) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chevron_right, size: 20, color: Colors.grey[400]),
                InkWell(
                  onTap: () {
                    final index = _path.indexOf(tag);
                    setState(() {
                      _currentParent = tag;
                      _path = _path.sublist(0, index);
                    });
                  },
                  child: Text(
                    tag.name,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Current level
          if (_currentParent != null) ...[
            Icon(Icons.chevron_right, size: 20, color: Colors.grey[400]),
            Text(
              _currentParent!.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShelvesCountBadge(BuildContext context, int count) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shelves, size: 16, color: theme.primaryColor),
                const SizedBox(width: 6),
                Text(
                  count == 1
                      ? (TranslationService.translate(
                              context, 'displayed_shelves_count') ??
                          '%d shelf')
                          .replaceAll('%d', '$count')
                      : (TranslationService.translate(
                              context, 'displayed_shelves_count_plural') ??
                          '%d shelves')
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

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shelves, size: 64, color: Colors.amber),
            ),
            const SizedBox(height: 24),
            Text(
              TranslationService.translate(context, 'no_shelves_title'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              TranslationService.translate(context, 'no_shelves_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _showCreateShelfDialog,
              icon: const Icon(Icons.add),
              label: Text(
                TranslationService.translate(context, 'create_first_shelf'),
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
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Error loading shelves',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: Colors.red),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _refreshTags,
              icon: const Icon(Icons.refresh),
              label: Text(TranslationService.translate(context, 'retry')),
            ),
          ],
        ),
      ),
    );
  }

    // Methods for editing and deleting shelves

  void _showEditShelfDialog(Tag tag) {
    final controller = TextEditingController(text: tag.name);
    final formKey = GlobalKey<FormState>();
    // Find the parent tag object from the list of all tags
    Tag? selectedParent;
    if (tag.parentId != null) {
      try {
        selectedParent = _allTags.firstWhere((t) => t.id == tag.parentId);
      } catch (e) {
        // Parent not found, can happen if tags are out of sync
        selectedParent = null;
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(TranslationService.translate(context, 'edit_shelf') ?? 'Edit Shelf'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: TranslationService.translate(context, 'shelf_name') ?? 'Shelf Name',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return TranslationService.translate(context, 'field_required') ?? 'This field is required';
                        }
                        return null;
                      },
                    ),
                    if (AppConstants.enableHierarchicalTags && _allTags.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<Tag?>(
                        value: selectedParent,
                        decoration: InputDecoration(
                          labelText: TranslationService.translate(context, 'parent_shelf') ?? 'Parent Shelf (optional)',
                          border: const OutlineInputBorder(),
                        ),
                        isExpanded: true,
                        items: [
                          DropdownMenuItem<Tag?>(
                            value: null,
                            child: Text(
                              TranslationService.translate(context, 'none') ?? 'None (root level)',
                              style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
                            ),
                          ),
                          // Exclude the current tag and its children from being a parent
                          ..._allTags.where((t) => t.id != tag.id).map((t) => DropdownMenuItem<Tag?>(
                            value: t,
                            child: Text(t.name),
                          )),
                        ],
                        onChanged: (Tag? value) {
                          setDialogState(() {
                            selectedParent = value;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(TranslationService.translate(context, 'cancel') ?? 'Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      Navigator.pop(context);
                      await _updateShelf(
                        tag.id,
                        controller.text.trim(),
                        parentId: selectedParent?.id,
                      );
                    }
                  },
                  child: Text(TranslationService.translate(context, 'update') ?? 'Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updateShelf(int id, String name, {int? parentId}) async {
    try {
      final api = Provider.of<TagRepository>(context, listen: false);
      await api.updateTag(id, name, parentId: parentId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TranslationService.translate(context, 'shelf_updated') ?? 'Shelf updated'),
            backgroundColor: Colors.green,
          ),
        );
        _refreshTags();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showDeleteConfirmDialog(Tag tag) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(TranslationService.translate(context, 'delete_shelf') ?? 'Delete Shelf'),
          content: Text(
            (TranslationService.translate(context, 'delete_shelf_confirm') ?? 'Are you sure you want to delete the shelf "%s"? This action cannot be undone.')
                .replaceAll('%s', tag.name),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(TranslationService.translate(context, 'cancel') ?? 'Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text(
                TranslationService.translate(context, 'delete') ?? 'Delete',
                style: const TextStyle(color: Colors.white),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteShelf(tag);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteShelf(Tag tag) async {
    try {
      final api = Provider.of<TagRepository>(context, listen: false);
      await api.deleteTag(tag.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (TranslationService.translate(context, 'shelf_deleted') ?? 'Shelf "%s" deleted.')
                  .replaceAll('%s', tag.name),
            ),
            backgroundColor: Colors.green,
          ),
        );
        _refreshTags();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildShelfCard(BuildContext context, Tag tag, int index) {
    final themeStyle = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).themeStyle;
    final isSorbonne = themeStyle == 'sorbonne';

    // Autumn palette for Sorbonne, colorful for others
    final colors = isSorbonne
        ? [
            const Color(0xFF8B4513), // Saddle brown
            const Color(0xFFCD853F), // Peru/tan
            const Color(0xFFD2691E), // Chocolate
            const Color(0xFFA0522D), // Sienna
            const Color(0xFF6B4423), // Dark brown
            const Color(0xFFCC7722), // Ochre
            const Color(0xFF8B6914), // Bronze
            const Color(0xFF704214), // Sepia
          ]
        : [
            const Color(0xFF667eea), // Indigo
            const Color(0xFF764ba2), // Purple
            const Color(0xFFf093fb), // Pink
            const Color(0xFF4facfe), // Blue
            const Color(0xFF43e97b), // Green
            const Color(0xFFfa709a), // Rose
            const Color(0xFFfee140), // Yellow
            const Color(0xFFf5576c), // Red
          ];
    // Check if tag has children
    final hasChildren = _allTags.any((t) => t.parentId == tag.id);
    // Calculate aggregated count (this tag + children)
    int aggregatedCount = tag.count;
    for (final t in _allTags) {
      if (t.parentId == tag.id) {
        aggregatedCount += t.count;
      }
    }

    final color = colors[index % colors.length];
    final gradient = LinearGradient(
      colors: [color, color.withValues(alpha: 0.7)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Card(
      elevation: 8,
      shadowColor: color.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _drillDown(tag),
        child: Container(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            children: [
              // Decorative pattern
              Positioned(
                right: -20,
                top: -20,
                child: Icon(
                  Icons.shelves,
                  size: 100,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),

              // Edit/delete menu
              Positioned(
                top: 8,
                right: 8,
                child: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'scan') {
                      context.push('/scan', extra: {
                        'shelfId': tag.name,
                        'shelfName': tag.fullPath,
                        'batch': true,
                      }).then((_) => _refreshTags());
                    } else if (value == 'edit') {
                      _showEditShelfDialog(tag);
                    } else if (value == 'delete') {
                      _showDeleteConfirmDialog(tag);
                    }
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'scan',
                      child: ListTile(
                        leading: const Icon(Icons.qr_code_scanner, color: Colors.orange),
                        title: Text(TranslationService.translate(context, 'scan_into_shelf') ?? 'Scan into this shelf'),
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: ListTile(
                        leading: const Icon(Icons.edit),
                        title: Text(TranslationService.translate(context, 'edit_shelf') ?? 'Edit'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: ListTile(
                        leading: const Icon(Icons.delete),
                        title: Text(TranslationService.translate(context, 'delete_shelf') ?? 'Delete'),
                      ),
                    ),
                  ],
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  color: Theme.of(context).colorScheme.surface,
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Shelf icon with count badge
                    Padding(
                      padding: const EdgeInsets.only(right: 32),
                      child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            hasChildren ? Icons.folder : Icons.label,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$aggregatedCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              if (hasChildren) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.chevron_right,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    ),
                    // Tag name
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tag.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            letterSpacing: 0.5,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tag.count == 1
                              ? '${tag.count} ${TranslationService.translate(context, 'book')}'
                              : '${tag.count} ${TranslationService.translate(context, 'books')}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Direct access button for shelves with sub-shelves
              if (hasChildren)
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => context.go('/shelves?tag=${tag.name}'),
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.visibility,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              TranslationService.translate(context, 'view'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Methods for direct shelf creation (copied/adapted from ShelfManagementScreen)
  Future<void> _createShelf(String name, {int? parentId}) async {
    try {
      final api = Provider.of<TagRepository>(context, listen: false);
      await api.createTag(name, parentId: parentId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'shelf_created') ??
                  'Shelf created',
            ),
            backgroundColor: Colors.green,
          ),
        );
        _refreshTags();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showCreateShelfDialog() {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    // Pre-select current parent if navigating within a sub-shelf
    Tag? selectedParent = _currentParent;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                TranslationService.translate(context, 'create_shelf') ??
                    'Create Shelf',
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText:
                            TranslationService.translate(context, 'shelf_name') ??
                            'Shelf Name',
                        hintText:
                            TranslationService.translate(
                              context,
                              'shelf_name_hint',
                            ) ??
                            'e.g. Science Fiction',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return TranslationService.translate(
                                context,
                                'field_required',
                              ) ??
                              'This field is required';
                        }
                        return null;
                      },
                    ),
                    // Parent shelf selector (only if hierarchical tags enabled and shelves exist)
                    if (AppConstants.enableHierarchicalTags && _allTags.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<Tag?>(
                        value: selectedParent,
                        decoration: InputDecoration(
                          labelText:
                              TranslationService.translate(context, 'parent_shelf') ??
                              'Parent Shelf (optional)',
                          border: const OutlineInputBorder(),
                        ),
                        isExpanded: true,
                        items: [
                          DropdownMenuItem<Tag?>(
                            value: null,
                            child: Text(
                              TranslationService.translate(context, 'none') ??
                                  'None (root level)',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                          ..._allTags.map((tag) => DropdownMenuItem<Tag?>(
                            value: tag,
                            child: Text(tag.name),
                          )),
                        ],
                        onChanged: (Tag? value) {
                          setDialogState(() {
                            selectedParent = value;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    TranslationService.translate(context, 'cancel') ?? 'Cancel',
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      Navigator.pop(context);
                      await _createShelf(
                        controller.text.trim(),
                        parentId: selectedParent?.id,
                      );
                    }
                  },
                  child: Text(
                    TranslationService.translate(context, 'create') ?? 'Create',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
