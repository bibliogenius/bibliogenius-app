import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../data/repositories/tag_repository.dart';
import '../models/tag.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/scaffold_with_nav.dart';
import '../widgets/configurable_action_card.dart';
import '../widgets/contextual_help_sheet.dart';
import '../widgets/quick_actions_sheet.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../providers/book_refresh_notifier.dart';
import '../providers/theme_provider.dart';
import '../providers/ownership_preference_provider.dart';
import '../utils/book_filters.dart';
import '../utils/app_constants.dart';

class ShelvesScreen extends StatefulWidget {
  final bool isTabView;
  final ValueNotifier<int>? refreshNotifier;

  const ShelvesScreen({
    super.key,
    this.isTabView = false,
    this.refreshNotifier,
  });

  @override
  State<ShelvesScreen> createState() => _ShelvesScreenState();
}

class _ShelvesScreenState extends State<ShelvesScreen> {
  /// The badge must announce what the tap will open, and what it opens is the
  /// reader's remembered ownership axis (ADR-063). Watched rather than read
  /// once: changing the axis from the library screen has to repaint these.
  int _shelfCount(Tag tag) => countForOwnershipScope(
    tag,
    resolveOwnershipScope(
      explicit: context.watch<OwnershipPreferenceProvider>().scope,
      status: null,
    ),
  );
  List<Tag> _allTags = [];
  bool _isLoading = true;
  String? _error;
  Tag? _currentParent; // null = root level
  List<Tag> _path = []; // breadcrumb path
  BookRefreshNotifier? _bookRefreshNotifier;

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier?.addListener(_loadTags);
    // The tab stays mounted behind whatever the reader pushes on top of it
    // (a book form, a scan), so a shelf created or filled there has to reach
    // this grid through the global notifier, or it only shows after leaving
    // the tab and coming back.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bookRefreshNotifier = context.read<BookRefreshNotifier>();
      _bookRefreshNotifier?.addListener(_loadTags);
    });
    _loadTags();
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_loadTags);
    _bookRefreshNotifier?.removeListener(_loadTags);
    super.dispose();
  }

  /// Reload the tags and keep the reader where they are.
  ///
  /// The grid keeps painting the previous list while the new one loads: a
  /// spinner on every delete or rename reads as "something is off", while a
  /// card that simply disappears reads as done. The current level is
  /// re-resolved against the fresh list, and only dropped when the shelf the
  /// reader was in no longer exists or no longer has sub-shelves.
  Future<void> _loadTags() async {
    try {
      final tags = await Provider.of<TagRepository>(
        context,
        listen: false,
      ).getTags();
      if (!mounted) return;
      setState(() {
        _allTags = tags;
        _error = null;
        _isLoading = false;
        _resolveLevel();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _resolveLevel() {
    Tag? find(Tag tag) {
      for (final t in _allTags) {
        if (t.id == tag.id) return t;
      }
      return null;
    }

    final resolvedPath = <Tag>[];
    for (final ancestor in _path) {
      final found = find(ancestor);
      if (found == null) break;
      resolvedPath.add(found);
    }
    _path = resolvedPath;

    final parent = _currentParent == null ? null : find(_currentParent!);
    if (parent == null || _childrenOf(parent).isEmpty) {
      // The shelf is gone or became a leaf: climb one level rather than
      // bounce the reader to an empty book list.
      _currentParent = _path.isNotEmpty ? _path.removeLast() : null;
    } else {
      _currentParent = parent;
    }
  }

  List<Tag> _childrenOf(Tag tag) =>
      _allTags.where((t) => t.parentId == tag.id).toList();

  /// Own books plus every descendant's: the number the shelf's book list
  /// will show, since filtering on a parent includes its whole subtree.
  int _aggregatedCount(Tag tag) {
    final descendants = Tag.getDescendantIds(tag.id, _allTags);
    var total = _shelfCount(tag);
    for (final t in _allTags) {
      if (descendants.contains(t.id)) total += _shelfCount(t);
    }
    return total;
  }

  /// Get tags to display at current level
  List<Tag> get _visibleTags {
    if (_currentParent == null) {
      // Show only root tags (no parent)
      return _allTags.where((t) => t.parentId == null).toList();
    } else {
      // Show direct children of current parent
      return _childrenOf(_currentParent!);
    }
  }

  /// Open a shelf: its sub-shelves when it has some, its books otherwise.
  void _openShelf(Tag tag) {
    if (_childrenOf(tag).isNotEmpty) {
      setState(() {
        if (_currentParent != null) {
          _path.add(_currentParent!);
        }
        _currentParent = tag;
      });
    } else {
      _openShelfBooks(tag);
    }
  }

  /// The book list of a shelf, sub-shelves included.
  void _openShelfBooks(Tag tag) {
    context.go('/shelves?tag=${Uri.encodeQueryComponent(tag.name)}');
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

  String _plural(BuildContext context, String key, int count) =>
      TranslationService.translate(
        context,
        count == 1 ? key : '${key}_plural',
      ).replaceAll('%d', '$count');

  @override
  Widget build(BuildContext context) {
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
          child: SafeArea(top: false, child: _buildBody(context)),
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
        preSelectedShelfId: _currentParent?.name,
        title:
            _currentParent?.name ??
            TranslationService.translate(context, 'shelves'),
        leading: _currentParent != null
            ? IconButton(
                icon: Icon(Icons.adaptive.arrow_back, color: Colors.white),
                tooltip: TranslationService.translate(context, 'back'),
                onPressed: _goBack,
              )
            : buildDrawerLeading(context),
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
          Builder(
            builder: (sheetContext) {
              final handlers = QuickActionsSheet.buildCommonHandlers(
                sheetContext,
                onDone: _loadTags,
              );
              // Override create_shelf to use the local dialog with parent preselect
              handlers['create_shelf'] = () {
                Navigator.pop(sheetContext);
                _showCreateShelfDialog();
              };
              return Row(
                children: [
                  Expanded(
                    child: ConfigurableActionCard(
                      slotKey: 'shelves_ctx_slot_1',
                      defaultActionId: 'create_shelf',
                      allowedActionIds: const [
                        'create_shelf',
                        'manage_shelves',
                        'inventory',
                      ],
                      handlers: handlers,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ConfigurableActionCard(
                      slotKey: 'shelves_ctx_slot_2',
                      defaultActionId: 'manage_shelves',
                      allowedActionIds: const [
                        'manage_shelves',
                        'create_shelf',
                        'inventory',
                      ],
                      handlers: handlers,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ConfigurableActionCard(
                      slotKey: 'shelves_ctx_slot_3',
                      defaultActionId: 'scan_barcode',
                      allowedActionIds: const [
                        'scan_barcode',
                        'add_manual',
                        'search_online',
                      ],
                      handlers: handlers,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppDesign.pageGradientForTheme(themeStyle),
        ),
        child: _buildBody(context),
      ),
    );
  }

  /// Shared by both branches: the standalone route and the library tab.
  Widget _buildBody(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isMobile = width <= 600;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildErrorState(_error!);
    }
    if (_allTags.isEmpty) {
      return _buildEmptyState(context);
    }

    final visibleTags = _visibleTags;

    return RefreshIndicator(
      onRefresh: _loadTags,
      child: Column(
        children: [
          if (_currentParent != null) _buildLevelHeader(context),

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
                  childAspectRatio: 1.0,
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
  }

  /// Where the reader is, and the one thing a level cannot show as a card:
  /// the books of the shelf itself.
  ///
  /// The tab has no app bar of its own, so without this the only trace of
  /// having entered "Genre" was a thin breadcrumb line above a changed grid.
  Widget _buildLevelHeader(BuildContext context) {
    final theme = Theme.of(context);
    final parent = _currentParent!;
    final subShelves = _childrenOf(parent).length;
    final books = _aggregatedCount(parent);
    final summary =
        '${_plural(context, 'sub_shelves_count', subShelves)} · '
        '${_plural(context, 'displayed_books_count', books)}';

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
      color: theme.colorScheme.surface.withValues(alpha: 0.9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.adaptive.arrow_back),
                tooltip: TranslationService.translate(context, 'back'),
                onPressed: _goBack,
              ),
              Expanded(child: _buildBreadcrumb(context)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          parent.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(summary, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: () => _openShelfBooks(parent),
                  icon: const Icon(Icons.menu_book, size: 18),
                  label: Text(
                    TranslationService.translate(context, 'view_shelf_books'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build breadcrumb navigation bar
  Widget _buildBreadcrumb(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
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
                    TranslationService.translate(context, 'all_shelves'),
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
                ExcludeSemantics(
                  child: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: Colors.grey[400],
                  ),
                ),
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
            ExcludeSemantics(
              child: Icon(
                Icons.chevron_right,
                size: 20,
                color: Colors.grey[400],
              ),
            ),
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
    return Semantics(
      label: _plural(context, 'displayed_shelves_count', count),
      child: Padding(
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
                                    context,
                                    'displayed_shelves_count',
                                  ) ??
                                  '%d shelf')
                              .replaceAll('%d', '$count')
                        : (TranslationService.translate(
                                    context,
                                    'displayed_shelves_count_plural',
                                  ) ??
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
              onPressed: _loadTags,
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
              title: Text(
                TranslationService.translate(context, 'edit_shelf') ??
                    'Edit Shelf',
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
                            TranslationService.translate(
                              context,
                              'shelf_name',
                            ) ??
                            'Shelf Name',
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
                    if (AppConstants.enableHierarchicalTags &&
                        _allTags.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<Tag?>(
                        value: selectedParent,
                        decoration: InputDecoration(
                          labelText:
                              TranslationService.translate(
                                context,
                                'parent_shelf',
                              ) ??
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
                          // Exclude the current tag and its children from being a parent
                          ..._allTags
                              .where((t) => t.id != tag.id)
                              .map(
                                (t) => DropdownMenuItem<Tag?>(
                                  value: t,
                                  child: Text(t.name),
                                ),
                              ),
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
                      await _updateShelf(
                        tag.id,
                        controller.text.trim(),
                        parentId: selectedParent?.id,
                      );
                    }
                  },
                  child: Text(
                    TranslationService.translate(context, 'update') ?? 'Update',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updateShelf(String id, String name, {String? parentId}) async {
    try {
      final api = Provider.of<TagRepository>(context, listen: false);
      // The tag is addressed by its uuid, resolved from the loaded list by its
      // local id. Synthetic (subject-derived) shelves have no row to update.
      final uuid = _allTags
          .firstWhere(
            (t) => t.id == id,
            orElse: () => Tag(id: id, name: name, count: 0),
          )
          .uuid;
      if (uuid == null) return;
      await api.updateTag(uuid, name, parentId: parentId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'shelf_updated') ??
                  'Shelf updated',
            ),
            backgroundColor: Colors.green,
          ),
        );
        _loadTags();
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
          title: Text(TranslationService.translate(context, 'delete_shelf')),
          content: Text(
            '${TranslationService.translate(context, 'delete_shelf_confirm').replaceAll('%s', tag.name)}\n\n'
            '${TranslationService.translate(context, 'delete_shelf_books_kept')}',
          ),
          actions: <Widget>[
            TextButton(
              child: Text(TranslationService.translate(context, 'cancel')),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text(
                TranslationService.translate(context, 'delete'),
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
      // Row or not, the name has to leave the books: a shelf that only
      // exists in their subjects is deleted the same way (see deleteShelf).
      await api.deleteShelf(tag);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(
                context,
                'shelf_deleted',
              ).replaceAll('%s', tag.name),
            ),
            backgroundColor: Colors.green,
          ),
        );
        await _loadTags();
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
    final isDark = themeStyle == 'dark';

    // Cyan palette for dark theme, colorful for others
    final colors = isDark
        ? [
            const Color(0xFF06B6D4), // Cyan
            const Color(0xFF0891B2), // Cyan dark
            const Color(0xFF22D3EE), // Cyan light
            const Color(0xFF0E7490), // Cyan 700
            const Color(0xFF155E75), // Cyan 800
            const Color(0xFF67E8F9), // Cyan 300
            const Color(0xFF0284C7), // Sky 600
            const Color(0xFF0369A1), // Sky 700
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
    final subShelves = _childrenOf(tag).length;
    final hasChildren = subShelves > 0;
    // The badge counts the whole subtree: that is what the book list shows.
    final aggregatedCount = _aggregatedCount(tag);
    final booksLabel = _plural(
      context,
      'displayed_books_count',
      aggregatedCount,
    );
    final subShelvesLabel = _plural(context, 'sub_shelves_count', subShelves);

    final color = colors[index % colors.length];
    final gradient = LinearGradient(
      colors: [color, color.withValues(alpha: 0.7)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Semantics(
      button: true,
      label: hasChildren
          ? '${tag.name}, $subShelvesLabel, $booksLabel'
          : '${tag.name}, $booksLabel',
      child: Card(
        elevation: 8,
        shadowColor: color.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openShelf(tag),
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
                  child: ExcludeSemantics(
                    child: Icon(
                      Icons.shelves,
                      size: 100,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                ),

                // Edit/delete menu
                Positioned(
                  top: 8,
                  right: 8,
                  child: PopupMenuButton<String>(
                    tooltip: TranslationService.translate(
                      context,
                      'more_actions',
                    ),
                    onSelected: (value) {
                      if (value == 'view_books') {
                        _openShelfBooks(tag);
                      } else if (value == 'scan') {
                        context
                            .push(
                              '/scan',
                              extra: {
                                'shelfId': tag.name,
                                'shelfName': tag.fullPath,
                                'batch': true,
                              },
                            )
                            .then((_) => _loadTags());
                      } else if (value == 'edit') {
                        _showEditShelfDialog(tag);
                      } else if (value == 'delete') {
                        _showDeleteConfirmDialog(tag);
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                          // A parent's tap opens its sub-shelves; its own
                          // book list is reachable from here and from the
                          // level header.
                          if (hasChildren)
                            PopupMenuItem<String>(
                              value: 'view_books',
                              child: ListTile(
                                leading: const Icon(Icons.menu_book),
                                title: Text(
                                  TranslationService.translate(
                                    context,
                                    'view_shelf_books',
                                  ),
                                ),
                              ),
                            ),
                          PopupMenuItem<String>(
                            value: 'scan',
                            child: ListTile(
                              leading: const Icon(
                                Icons.qr_code_scanner,
                                color: Colors.orange,
                              ),
                              title: Text(
                                TranslationService.translate(
                                  context,
                                  'scan_into_shelf',
                                ),
                              ),
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem<String>(
                            value: 'edit',
                            child: ListTile(
                              leading: const Icon(Icons.edit),
                              title: Text(
                                TranslationService.translate(
                                  context,
                                  'edit_shelf',
                                ),
                              ),
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: ListTile(
                              leading: const Icon(Icons.delete),
                              title: Text(
                                TranslationService.translate(
                                  context,
                                  'delete_shelf',
                                ),
                              ),
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
                              child: Text(
                                '$aggregatedCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Tag name, then what the tap opens: the sub-shelves,
                      // spelled out, or the books.
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
                          const SizedBox(height: 6),
                          if (hasChildren)
                            _SubShelvesChip(label: subShelvesLabel)
                          else
                            Text(
                              booksLabel,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Methods for direct shelf creation (copied/adapted from ShelfManagementScreen)
  Future<void> _createShelf(String name, {String? parentId}) async {
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
        _loadTags();
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
                            TranslationService.translate(
                              context,
                              'shelf_name',
                            ) ??
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
                    if (AppConstants.enableHierarchicalTags &&
                        _allTags.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<Tag?>(
                        value: selectedParent,
                        decoration: InputDecoration(
                          labelText:
                              TranslationService.translate(
                                context,
                                'parent_shelf',
                              ) ??
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
                          ..._allTags.map(
                            (tag) => DropdownMenuItem<Tag?>(
                              value: tag,
                              child: Text(tag.name),
                            ),
                          ),
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

/// The explicit way into a shelf's sub-shelves: a labelled pill, where a
/// bare chevron next to the count used to be the only hint.
class _SubShelvesChip extends StatelessWidget {
  final String label;

  const _SubShelvesChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_open, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white, size: 16),
        ],
      ),
    );
  }
}
