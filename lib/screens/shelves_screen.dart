import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../data/repositories/tag_repository.dart';
import '../models/tag.dart';
import '../widgets/app_snack_bar.dart';
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
import '../providers/sort_preference_provider.dart';
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

class _ShelvesScreenState extends State<ShelvesScreen>
    with WidgetsBindingObserver {
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

  /// Shelves deleted in the tree whose write has not landed yet: the one
  /// waiting on its Undo, and any whose write is still on its way. Keyed
  /// by [_hideKey].
  final Set<String> _hiddenShelves = {};

  /// A shelf with a row by its id. One known only from the books' subjects
  /// by its name: the core numbers those `legacy:` ids afresh, in no stable
  /// order, on every listing.
  static String _hideKey(Tag tag) =>
      tag.isPersisted ? tag.id : 'name:${tag.name}';

  /// The latest Undo of a move or a rename. It goes when the reader leaves
  /// the tab: under a screen reader it would otherwise follow them
  /// everywhere.
  UndoableMessage? _undoMessage;

  /// The deletion waiting on its Undo. One at a time.
  _PendingShelfDeletion? _pendingDeletion;

  /// What the tree shows: [_allTags] without [_hiddenShelves]. Kept as one
  /// list instance between changes, the tree index is cached per instance.
  List<Tag>? _shownCache;
  List<Tag> get _shownTags => _shownCache ??= Tag.withoutShelves(_allTags, {
    for (final t in _allTags)
      if (_hiddenShelves.contains(_hideKey(t))) t.id,
  });

  /// Off while a page opened over the tab hides it. Another library tab is
  /// another route: going there disposes this screen.
  ValueListenable<bool>? _tickerMode;

  /// Books in the default view on no shelf: drives the "to shelve" card.
  int _unshelvedCount = 0;
  bool _isLoading = true;
  String? _error;
  BookRefreshNotifier? _bookRefreshNotifier;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerMode = TickerMode.getNotifier(context);
    if (!identical(tickerMode, _tickerMode)) {
      _tickerMode?.removeListener(_onTickerModeChanged);
      _tickerMode = tickerMode..addListener(_onTickerModeChanged);
    }
  }

  /// Out of sight is leaving the tab.
  void _onTickerModeChanged() {
    if (_tickerMode?.value == false) _leaveTab();
  }

  /// A waiting deletion goes, and no Undo of the tab stays up behind.
  void _leaveTab() {
    _sendPendingDeletion();
    _undoMessage?.dismiss();
    _undoMessage = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app sends a waiting deletion. Inactive is not leaving: a
    // glance at the control centre or a system dialog passes through it.
    // The Undo of a move or a rename stays: nothing waits behind it.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _sendPendingDeletion();
    }
  }

  @override
  void dispose() {
    // Leaving the tab sends a waiting deletion. Its write runs on the
    // repository captured when it started and touches no state from here.
    _leaveTab();
    WidgetsBinding.instance.removeObserver(this);
    _tickerMode?.removeListener(_onTickerModeChanged);
    widget.refreshNotifier?.removeListener(_loadTags);
    _bookRefreshNotifier?.removeListener(_loadTags);
    super.dispose();
  }

  /// Bumped by each load: a listing that lands after a later one is stale
  /// (it may still hold a shelf deleted since) and is dropped.
  int _loadGeneration = 0;

  /// Deletions the core has taken, by [_hideKey], with the load generation
  /// current when the write landed. Their rows stay hidden until a listing
  /// started after that lands: any earlier one may still hold the shelf.
  final Map<String, int> _writtenDeletions = {};

  /// Reload the tags and keep the reader where they are.
  ///
  /// The tree keeps painting the previous list while the new one loads: a
  /// spinner on every delete or rename reads as "something is off", while a
  /// row that simply disappears reads as done.
  Future<void> _loadTags() async {
    final generation = ++_loadGeneration;
    try {
      final repo = Provider.of<TagRepository>(context, listen: false);
      // Both in flight at once; the count never throws, so a failed tag
      // load still reaches the error state with its own message.
      final unshelvedLoad = _loadUnshelvedCount(repo);
      final tags = await repo.getTags();
      final unshelved = await unshelvedLoad;
      if (!mounted || generation != _loadGeneration) return;
      // A shelf deleted elsewhere (the management screen, another device)
      // leaves no order behind. An empty listing proves nothing: the FFI
      // answers one on any core error, and a library with no shelf has no
      // order to forget anyway.
      if (tags.isNotEmpty) {
        _sortPreference?.retainShelfOrders({
          for (final t in tags)
            if (t.isPersisted) t.id,
        });
      }
      setState(() {
        _allTags = tags;
        _writtenDeletions.removeWhere((key, writtenAt) {
          if (generation <= writtenAt) return false;
          _hiddenShelves.remove(key);
          return true;
        });
        _shownCache = null;
        _unshelvedCount = unshelved;
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
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

  /// Absent from screens tested without it.
  SortPreferenceProvider? get _sortPreference =>
      Provider.of<SortPreferenceProvider?>(context, listen: false);

  List<Tag> _childrenOf(Tag tag) =>
      Tag.getDirectChildren(tag.id, _shownTags);

  /// Own books plus every descendant's: the number the shelf's book list
  /// will show, since filtering on a parent includes its whole subtree.
  int _aggregatedCount(Tag tag) {
    final shown = _shownTags;
    final descendants = Tag.getDescendantIds(tag.id, shown);
    var total = _shelfCount(tag);
    for (final t in shown) {
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

    if (_shownTags.isEmpty) {
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
      allTags: _shownTags,
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
                        // From the stored tree: the one shown moves the
                        // sub-shelves of a deletion waiting on its Undo.
                        parentId: Tag.effectiveParentIds(_allTags)[tag.id],
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
      final shelf = _allTags.firstWhere(
        (t) => t.id == id,
        orElse: () => Tag(id: id, name: name, count: 0),
      );
      final uuid = shelf.uuid;
      if (uuid == null) return;
      // What Undo gives back.
      final previousName = shelf.name;
      await api.updateTag(uuid, name, parentId: parentId);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        final taken = TranslationService.translate(
          context,
          'shelf_undo_name_taken',
        ).replaceAll('%s', previousName);
        _undoMessage = AppSnackBar.undoable(
          context,
          TranslationService.translate(context, 'shelf_updated'),
          onUndo: () =>
              _undoRename(api, messenger, id, previousName, taken),
        );
        _loadTags();
      }
    } catch (e) {
      if (mounted) AppSnackBar.error(context, e.toString());
    }
  }

  /// Gives [previousName] back to the shelf [id], as Undo of a rename.
  ///
  /// Read afresh: names are unique byte for byte, and one taken by another
  /// shelf since stays with it; the rename then holds, and the reader is
  /// told why. A move made meanwhile is kept.
  Future<void> _undoRename(
    TagRepository repo,
    ScaffoldMessengerState messenger,
    String id,
    String previousName,
    String takenMessage,
  ) async {
    try {
      final tags = await repo.getTags();
      final shelf = tags.where((t) => t.id == id).firstOrNull;
      if (shelf == null) {
        debugPrint('ShelvesScreen: undo found no shelf to rename');
        return;
      }
      if (tags.any((t) => t.id != id && t.name == previousName)) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(takenMessage)));
        return;
      }
      await repo.updateTag(
        shelf.uuid,
        previousName,
        parentId: Tag.effectiveParentId(shelf, tags),
      );
    } catch (e) {
      debugPrint('ShelvesScreen: undo of a rename failed: ${e.runtimeType}');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      return;
    }
    if (mounted) _loadTags();
  }

  void _reloadIfMounted() {
    if (mounted) _loadTags();
  }

  void _keepUndo(UndoableMessage message) => _undoMessage = message;

  Future<void> _moveShelf(Tag tag) async {
    final moved = await showMoveShelfSheet(
      context,
      shelf: tag,
      allTags: _shownTags,
      onUndone: _reloadIfMounted,
      onUndoShown: _keepUndo,
    );
    if (moved && mounted) _loadTags();
  }

  /// Deletes [tag] in the tree at once and offers Undo; the write waits.
  ///
  /// It goes when the message closes (expired, dismissed, or replaced by
  /// another), when the reader leaves the tab or the app, or when a second
  /// deletion starts. Undo writes nothing, so nothing reaches a sync.
  void _deleteShelf(Tag tag) {
    _sendPendingDeletion();
    final pending = _PendingShelfDeletion(
      tag,
      Provider.of<TagRepository>(context, listen: false),
      _sortPreference,
    );
    final subShelfCount = _childrenOf(tag).length;
    setState(() {
      _pendingDeletion = pending;
      _hiddenShelves.add(_hideKey(tag));
      _shownCache = null;
    });
    final message = AppSnackBar.undoable(
      context,
      deletedShelfMessage(context, tag, subShelfCount: subShelfCount),
      onUndo: () => _undoDeletion(pending),
    );
    pending.message = message;
    message.closed.then((reason) {
      if (reason != SnackBarClosedReason.action) _sendDeletion(pending);
    });
  }

  void _undoDeletion(_PendingShelfDeletion pending) {
    if (!pending.settle()) return;
    if (identical(_pendingDeletion, pending)) _pendingDeletion = null;
    if (!mounted) return;
    setState(() {
      _hiddenShelves.remove(_hideKey(pending.shelf));
      _shownCache = null;
    });
  }

  /// Sends the deletion waiting on its Undo, if any, and takes the Undo
  /// off the screen: past this point it would undo nothing.
  void _sendPendingDeletion() {
    final pending = _pendingDeletion;
    if (pending == null) return;
    _sendDeletion(pending);
    pending.message?.dismiss();
  }

  void _sendDeletion(_PendingShelfDeletion pending) {
    if (!pending.settle()) return;
    if (identical(_pendingDeletion, pending)) _pendingDeletion = null;
    unawaited(_writeDeletion(pending));
  }

  /// The write itself. Started from `dispose` as well: nothing before its
  /// first await touches this state, nothing after it once unmounted.
  Future<void> _writeDeletion(_PendingShelfDeletion pending) async {
    final shelf = pending.shelf;
    try {
      // Row or not, the name has to leave the books: a shelf that only
      // exists in their subjects is deleted the same way (see deleteShelf).
      await pending.repo.deleteShelf(shelf);
      // The shelf's own order goes with it, only now that it is gone.
      await pending.sortPreference?.setShelfOrder(shelf.id, false);
    } catch (e) {
      debugPrint('ShelvesScreen: deleting a shelf failed: ${e.runtimeType}');
      if (!mounted) return;
      setState(() {
        _hiddenShelves.remove(_hideKey(shelf));
        _shownCache = null;
      });
      // Replacing the message of a deletion still waiting on its Undo
      // would send that one too: the error waits its turn.
      AppSnackBar.error(
        context,
        e.toString(),
        queue: _pendingDeletion != null,
      );
      return;
    }
    if (!mounted) return;
    _writtenDeletions[_hideKey(shelf)] = _loadGeneration;
    await _loadTags();
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
        onShown: _keepUndo,
      ),
    );
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

  // Methods for direct shelf creation (copied/adapted from ShelfManagementScreen)
  Future<void> _createShelf(String name, {String? parentId}) async {
    try {
      final api = Provider.of<TagRepository>(context, listen: false);
      await api.createTag(name, parentId: parentId);
      if (mounted) {
        // Replaces an Undo still up rather than queueing behind it.
        AppSnackBar.success(
          context,
          TranslationService.translate(context, 'shelf_created'),
        );
        _loadTags();
      }
    } catch (e) {
      if (mounted) AppSnackBar.error(context, e.toString());
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
                        _shownTags.isNotEmpty) ...[
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
                          ..._shownTags.map(
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

/// A deletion the tree already shows but has not written: it waits on its
/// Undo. Holds what the write needs, so that it can still go once the tab
/// is gone.
class _PendingShelfDeletion {
  _PendingShelfDeletion(this.shelf, this.repo, this.sortPreference);

  final Tag shelf;
  final TagRepository repo;
  final SortPreferenceProvider? sortPreference;
  UndoableMessage? message;
  bool _settled = false;

  /// True the first time only: a deletion is sent, or undone, once.
  bool settle() {
    if (_settled) return false;
    _settled = true;
    return true;
  }
}
