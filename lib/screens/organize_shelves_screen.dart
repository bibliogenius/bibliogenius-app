import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/tag_repository.dart';
import '../models/tag.dart';
import '../providers/book_refresh_notifier.dart';
import '../providers/ownership_preference_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../utils/app_constants.dart';
import '../utils/book_filters.dart';
import '../widgets/move_shelf_sheet.dart';
import '../widgets/shelf_actions.dart';
import '../widgets/shelf_tree_view.dart';

/// Where the shelves are rearranged: the whole tree, with its drag and its
/// Undo, on a screen of its own that a reader visibly enters and leaves.
///
/// Leaving it, by "Done", Escape or the system back, sends a deletion still
/// waiting on its Undo and tells what shows the shelves to read them again.
class OrganizeShelvesScreen extends StatefulWidget {
  const OrganizeShelvesScreen({super.key});

  @override
  State<OrganizeShelvesScreen> createState() => _OrganizeShelvesScreenState();
}

class _OrganizeShelvesScreenState extends State<OrganizeShelvesScreen> {
  late final ShelfActionsController _actions = ShelfActionsController(
    () => mounted ? context : null,
  )..onWritten = _refresh.refresh;

  late final BookRefreshNotifier _refresh;

  List<Tag> _allTags = [];
  bool _isLoading = true;
  String? _error;

  /// Something here changed what the screens behind show.
  bool _changed = false;

  /// What the tree shows: [_allTags] without the shelves waiting on a
  /// deletion. Kept as one list instance between changes, the tree index is
  /// cached per instance.
  List<Tag>? _shownCache;
  List<Tag> get _shownTags => _shownCache ??= _actions.shown(_allTags);

  /// Off while a page opened over this one hides it.
  ValueListenable<bool>? _tickerMode;

  @override
  void initState() {
    super.initState();
    _refresh = context.read<BookRefreshNotifier>();
    _refresh.addListener(_loadTags);
    _actions.addListener(_onActionsChanged);
    _loadTags();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerMode = TickerMode.getNotifier(context);
    if (!identical(tickerMode, _tickerMode)) {
      _tickerMode?.removeListener(_onTickerModeChanged);
      _tickerMode = tickerMode..addListener(_onTickerModeChanged);
    }
  }

  void _onTickerModeChanged() {
    if (_tickerMode?.value == false) _actions.leave();
  }

  void _onActionsChanged() {
    if (!mounted) return;
    setState(() => _shownCache = null);
  }

  @override
  void dispose() {
    _actions.removeListener(_onActionsChanged);
    // Sends a waiting deletion. Its write runs on the repository captured when
    // it started, and tells the notifier once done.
    _actions.dispose();
    _tickerMode?.removeListener(_onTickerModeChanged);
    _refresh.removeListener(_loadTags);
    super.dispose();
  }

  /// Reload the tags and keep the reader where they are.
  ///
  /// The tree keeps painting the previous list while the new one loads: a
  /// spinner on every delete or rename reads as "something is off", while a
  /// row that simply disappears reads as done.
  Future<void> _loadTags() async {
    final generation = _actions.beginListing();
    try {
      final tags = await context.read<TagRepository>().getTags();
      if (!mounted || generation != _actions.generation) return;
      setState(() {
        _allTags = tags;
        _actions.listingLanded(generation);
        _shownCache = null;
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || generation != _actions.generation) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _reloadIfMounted() {
    _changed = true;
    if (mounted) _loadTags();
  }

  void _close() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      context.go('/shelves');
    }
  }

  void _openShelfBooks(Tag tag) {
    context.go('/shelves?tag=${Uri.encodeQueryComponent(tag.name)}');
  }

  void _showEditShelfDialog(Tag tag) => showRenameShelfDialog(
    context,
    tag: tag,
    allTags: _allTags,
    onRenamed: (_) => _reloadIfMounted(),
    onUndone: _reloadIfMounted,
    onUndoShown: _actions.keepUndo,
  );

  void _showCreateShelfDialog({Tag? parent}) => showNewShelfDialog(
    context,
    parent: parent,
    shownTags: _shownTags,
    onCreated: _reloadIfMounted,
  );

  Future<void> _moveShelf(Tag tag) async {
    final moved = await showMoveShelfSheet(
      context,
      shelf: tag,
      allTags: _shownTags,
      onUndone: _reloadIfMounted,
      onUndoShown: _actions.keepUndo,
    );
    if (moved) _reloadIfMounted();
  }

  void _deleteShelf(Tag tag) {
    _changed = true;
    _actions.delete(
      context,
      tag,
      subShelfCount: Tag.getDirectChildren(tag.id, _shownTags).length,
    );
  }

  /// A drop in the tree: the same write and message as "Move to…", then
  /// the tree reloaded so the shelf shows at its new place.
  Future<bool> _dropShelf(Tag shelf, Tag? parent) async {
    final moved = await moveShelf(
      context,
      shelf: shelf,
      parent: parent,
      undo: ShelfMoveUndo(
        previousParentId: Tag.effectiveParentId(shelf, _shownTags),
        onUndone: _reloadIfMounted,
        onShown: _actions.keepUndo,
      ),
    );
    if (moved && mounted) {
      _changed = true;
      await _loadTags();
    }
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
        .then((_) => _reloadIfMounted());
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
            _deleteShelf(tag);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final themeStyle = context.select<ThemeProvider, String>(
      (p) => p.themeStyle,
    );
    final scope = resolveOwnershipScope(
      explicit: context.watch<OwnershipPreferenceProvider>().scope,
      status: null,
    );
    // Whatever closes this screen: going back to a screen still mounted, it
    // has to read what changed here. A link out rebuilds what it leads to.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _changed) _refresh.refresh();
      },
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              backgroundColor: scheme.surface,
              foregroundColor: scheme.onSurface,
              elevation: 0,
              title: Semantics(
                header: true,
                child: Text(
                  TranslationService.translate(context, 'organize_shelves'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  onPressed: _close,
                  child: Text(
                    TranslationService.translate(context, 'done'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            floatingActionButton: FloatingActionButton(
              heroTag: 'organize_shelves_add_fab',
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
              child: SafeArea(top: false, child: _buildBody(context, scope)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, String scope) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 16),
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Text(
            TranslationService.translate(context, 'organize_hint'),
            key: const Key('organizeHint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: _shownTags.isEmpty
              ? Center(
                  child: Text(
                    TranslationService.translate(context, 'no_shelves_title'),
                    style: theme.textTheme.titleMedium,
                  ),
                )
              : ShelfTreeView(
                  allTags: _shownTags,
                  bookCount: (tag) =>
                      aggregatedCountForScope(tag, _shownTags, scope),
                  onOpen: _openShelfBooks,
                  onMoveRequested: _moveShelf,
                  onDrop: _dropShelf,
                  menuBuilder: _buildRowMenu,
                  onRefresh: _loadTags,
                ),
        ),
      ],
    );
  }
}
