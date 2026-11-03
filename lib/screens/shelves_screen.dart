import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../data/repositories/tag_repository.dart';
import '../models/tag.dart';
import '../widgets/delete_shelf_dialog.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/move_shelf_sheet.dart';
import '../widgets/scaffold_with_nav.dart';
import '../widgets/shelf_or_collection_note.dart';
import '../widgets/shelf_tree_view.dart';
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

  /// Books in the default view on no shelf: drives the "to shelve" card.
  int _unshelvedCount = 0;
  bool _isLoading = true;
  String? _error;
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
  /// The tree keeps painting the previous list while the new one loads: a
  /// spinner on every delete or rename reads as "something is off", while a
  /// row that simply disappears reads as done.
  Future<void> _loadTags() async {
    try {
      final repo = Provider.of<TagRepository>(context, listen: false);
      // Both in flight at once; the count never throws, so a failed tag
      // load still reaches the error state with its own message.
      final unshelvedLoad = _loadUnshelvedCount(repo);
      final tags = await repo.getTags();
      final unshelved = await unshelvedLoad;
      if (!mounted) return;
      setState(() {
        _allTags = tags;
        _unshelvedCount = unshelved;
        _error = null;
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

  /// The card is a shortcut: a failed count hides it rather than turning the
  /// whole grid into an error.
  Future<int> _loadUnshelvedCount(TagRepository repo) async {
    try {
      return await repo.countUnshelvedBooks();
    } catch (e) {
      debugPrint('ShelvesScreen: unshelved count failed: $e');
      return 0;
    }
  }

  List<Tag> _childrenOf(Tag tag) => Tag.getDirectChildren(tag.id, _allTags);

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

  /// The book list of a shelf, sub-shelves included.
  void _openShelfBooks(Tag tag) {
    context.go('/shelves?tag=${Uri.encodeQueryComponent(tag.name)}');
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
          child: Icon(
            Icons.add,
            semanticLabel: TranslationService.translate(
              context,
              'create_shelf',
            ),
          ),
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
        child: Icon(
          Icons.add,
          semanticLabel: TranslationService.translate(context, 'create_shelf'),
        ),
      ),
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'shelves'),
        leading: buildDrawerLeading(context),
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
              // Override create_shelf to use the local dialog
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildErrorState(_error!);
    }
    final showToShelve = _unshelvedCount > 0;

    if (_allTags.isEmpty) {
      // Books scanned before any shelf exists: the card is where to start.
      if (!showToShelve) return _buildEmptyState(context);
      return Column(
        children: [
          _buildToShelveCard(context),
          Expanded(child: _buildEmptyState(context)),
        ],
      );
    }

    // Every level at once: a tap opens a shelf's books, its sub-shelves
    // are already in sight below it.
    return ShelfTreeView(
      allTags: _allTags,
      bookCount: _aggregatedCount,
      header: showToShelve ? _buildToShelveCard(context) : null,
      onOpen: _openShelfBooks,
      onMoveRequested: _moveShelf,
      onDrop: _dropShelf,
      menuBuilder: _buildRowMenu,
      onRefresh: _loadTags,
    );
  }

  /// The books on no shelf, gathered in one card: a tap lists them in this
  /// tab with selection armed, ready for the bulk shelving sheet. Coming back
  /// to the tree remounts this screen, which reloads the count.
  Widget _buildToShelveCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppDesign.radiusMedium);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      // One button, read as its title then its count.
      child: MergeSemantics(
        key: const Key('toShelveCard'),
        child: Semantics(
          button: true,
          child: Material(
            color: scheme.primaryContainer,
            borderRadius: radius,
            child: InkWell(
              borderRadius: radius,
              onTap: () => context.go(toShelveLocation),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(
                          AppDesign.radiusSmall,
                        ),
                      ),
                      child: Icon(
                        Icons.move_to_inbox_outlined,
                        color: scheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            TranslationService.translate(
                              context,
                              'to_shelve_title',
                            ),
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          Text(
                            _plural(
                              context,
                              'to_shelve_count',
                              _unshelvedCount,
                            ),
                            style: textTheme.bodyMedium?.copyWith(
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    // Scrollable: the two concept sentences make the column taller than a
    // small phone in landscape or with large text.
    return Center(
      child: SingleChildScrollView(
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
              TranslationService.translate(context, 'shelf_concept'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            const SizedBox(height: 32),
            const ShelfOrCollectionNote(conceptKey: 'collection_concept'),
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
                      // Renaming only: the shelf stays where the tree shows
                      // it. Moving goes through "Move to…".
                      await _updateShelf(
                        tag.id,
                        controller.text.trim(),
                        parentId: Tag.effectiveParentId(tag, _allTags),
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

  Future<void> _moveShelf(Tag tag) async {
    final moved = await showMoveShelfSheet(
      context,
      shelf: tag,
      allTags: _allTags,
    );
    if (moved && mounted) _loadTags();
  }

  Future<void> _showDeleteConfirmDialog(Tag tag) async {
    final confirmed = await confirmDeleteShelf(
      context,
      tag,
      subShelfCount: _childrenOf(tag).length,
    );
    if (confirmed && mounted) await _deleteShelf(tag);
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

  /// A drop in the tree: the same write and message as "Move to…", then
  /// the tree reloaded so the shelf shows at its new place.
  Future<bool> _dropShelf(Tag shelf, Tag? parent) async {
    final moved = await moveShelf(context, shelf: shelf, parent: parent);
    if (moved && mounted) await _loadTags();
    return moved;
  }

  void _scanInto(Tag tag) {
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
  }

  /// The "…" of a tree row. Opening the shelf's books is the row's own tap.
  Widget _buildRowMenu(BuildContext context, Tag tag) {
    PopupMenuItem<String> item(String value, IconData icon, String key) =>
        PopupMenuItem<String>(
          value: value,
          child: ListTile(
            leading: Icon(icon),
            title: Text(TranslationService.translate(context, key)),
          ),
        );

    return PopupMenuButton<String>(
      tooltip: TranslationService.translate(
        context,
        'shelf_actions_named',
      ).replaceAll('{name}', tag.name),
      onSelected: (value) {
        switch (value) {
          case 'scan':
            _scanInto(tag);
          case 'add_sub':
            _showCreateShelfDialog(parent: tag);
          case 'edit':
            _showEditShelfDialog(tag);
          case 'move':
            _moveShelf(tag);
          case 'delete':
            _showDeleteConfirmDialog(tag);
        }
      },
      itemBuilder: (context) => [
        item('scan', Icons.qr_code_scanner, 'scan_into_shelf'),
        if (AppConstants.enableHierarchicalTags)
          item('add_sub', Icons.create_new_folder_outlined, 'add_sub_shelf'),
        const PopupMenuDivider(),
        item('edit', Icons.edit, 'edit_shelf'),
        if (AppConstants.enableHierarchicalTags)
          item('move', Icons.drive_file_move, 'move_shelf_to'),
        item('delete', Icons.delete, 'delete_shelf'),
      ],
      icon: const Icon(Icons.more_vert),
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

  /// Creates a shelf at the first level, or inside [parent] when a row's
  /// menu asks for a sub-shelf.
  void _showCreateShelfDialog({Tag? parent}) {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    Tag? selectedParent = parent;

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
                              TranslationService.translate(
                                context,
                                'first_level',
                              ),
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
