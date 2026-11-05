import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../data/repositories/tag_repository.dart';
import '../models/tag.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/shelf_actions.dart';
import '../services/to_shelve_dismissal_store.dart';
import '../widgets/scaffold_with_nav.dart';
import '../widgets/shelf_card.dart';
import '../widgets/shelf_fan_flight.dart';
import '../widgets/shelf_or_collection_note.dart';
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

class ShelvesScreen extends StatefulWidget {
  final bool isTabView;
  final ValueNotifier<int>? refreshNotifier;

  /// The waiting deletion of a shelf page, when it lands here.
  /// Without it the screen keeps its own, and leaving it sends the deletion.
  final ShelfActionsController? actions;

  /// Told each listing, for the page of a shelf opened next to start from.
  final ValueChanged<List<Tag>>? onTagsLoaded;

  /// What a card sends its fan off with.
  final ShelfFanFlight? fanFlight;

  const ShelvesScreen({
    super.key,
    this.isTabView = false,
    this.refreshNotifier,
    this.actions,
    this.onTagsLoaded,
    this.fanFlight,
  });

  @override
  State<ShelvesScreen> createState() => _ShelvesScreenState();
}

class _ShelvesScreenState extends State<ShelvesScreen> {
  /// The side margin of the grid and of what heads it.
  static const double _gridMargin = 16;

  /// Three columns start here, and the add button leaves its floating spot.
  static const double _wideRowWidth = 600;

  /// A card must announce what the tap will open, and what it opens is the
  /// reader's remembered ownership axis (ADR-063): watched in [_aggregatedCount]
  /// because changing the axis from the library screen has to repaint these.
  List<Tag> _allTags = [];

  late final ShelfActionsController _actions =
      widget.actions ?? ShelfActionsController(() => mounted ? context : null);

  bool get _ownsActions => widget.actions == null;

  /// What the tree shows: [_allTags] without the shelves waiting on a
  /// deletion. Kept as one list instance between changes, the tree index is
  /// cached per instance.
  List<Tag>? _shownCache;
  List<Tag> get _shownTags => _shownCache ??= _actions.shown(_allTags);

  /// Off while a page opened over the tab hides it. Another library tab is
  /// another route: going there disposes this screen.
  ValueListenable<bool>? _tickerMode;

  /// Books in the default view on no shelf: drives the "to shelve" card.
  int _unshelvedCount = 0;

  /// The count at which the reader hid the "to shelve" line: it stays hidden
  /// up to that number.
  int _toShelveDismissedAt = 0;
  bool _isLoading = true;
  String? _error;
  BookRefreshNotifier? _bookRefreshNotifier;

  /// Where the focus goes when the cross takes itself off the screen.
  final FocusNode _organizeFocus = FocusNode(debugLabel: 'organizeShelves');

  @override
  void initState() {
    super.initState();
    _actions.addListener(_onActionsChanged);
    widget.refreshNotifier?.addListener(_loadTags);
    // The tab stays mounted behind whatever the reader pushes on top of it
    // (a book form, a scan), so a shelf created or filled there has to reach
    // this grid through the global notifier, or it only shows after leaving
    // the tab and coming back.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final refresh = context.read<BookRefreshNotifier>();
      _bookRefreshNotifier = refresh;
      refresh.addListener(_loadTags);
      if (_ownsActions) _actions.onWritten = refresh.refresh;
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
    if (_tickerMode?.value == false && _ownsActions) _actions.leave();
  }

  void _onActionsChanged() {
    if (!mounted) return;
    setState(() => _shownCache = null);
  }

  @override
  void dispose() {
    _actions.removeListener(_onActionsChanged);
    // Leaving the tab sends a waiting deletion, unless it outlives this
    // screen. Its write runs on the repository captured when it started and
    // touches no state from here.
    if (_ownsActions) _actions.dispose();
    _tickerMode?.removeListener(_onTickerModeChanged);
    widget.refreshNotifier?.removeListener(_loadTags);
    _bookRefreshNotifier?.removeListener(_loadTags);
    _organizeFocus.dispose();
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
      final repo = Provider.of<TagRepository>(context, listen: false);
      // Both in flight at once; the count never throws, so a failed tag
      // load still reaches the error state with its own message.
      final unshelvedLoad = _loadUnshelvedCount(repo);
      final dismissedLoad = ToShelveDismissalStore.load();
      final tags = await repo.getTags();
      final unshelved = await unshelvedLoad;
      final dismissedAt = await dismissedLoad;
      if (!mounted || generation != _actions.generation) return;
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
      widget.onTagsLoaded?.call(tags);
      setState(() {
        _allTags = tags;
        _actions.listingLanded(generation);
        _shownCache = null;
        _unshelvedCount = unshelved;
        _toShelveDismissedAt = dismissedAt;
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

  /// Own books plus every descendant's, each once: the number the head of the
  /// shelf's page says. Its grid holds only the books filed right there.
  int _aggregatedCount(Tag tag) => aggregatedCountForScope(
    tag,
    _shownTags,
    resolveOwnershipScope(
      explicit: context.watch<OwnershipPreferenceProvider>().scope,
      status: null,
    ),
  );

  /// The page of a shelf.
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
      return LayoutBuilder(
        builder: (context, constraints) => Scaffold(
          backgroundColor: Colors.transparent,
          // From this width the button sits in the row above the grid.
          floatingActionButton:
              constraints.maxWidth < _wideRowWidth
              ? FloatingActionButton(
                  heroTag: 'shelf_add_fab_tab',
                  onPressed: _showCreateShelfDialog,
                  child: Icon(
                    Icons.add,
                    semanticLabel: TranslationService.translate(
                      context,
                      'create_shelf',
                    ),
                  ),
                )
              : null,
          body: Container(
            decoration: BoxDecoration(
              gradient: AppDesign.pageGradientForTheme(themeStyle),
            ),
            child: SafeArea(top: false, child: _buildBody(context)),
          ),
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
    final showToShelve = _unshelvedCount > _toShelveDismissedAt;

    if (_shownTags.isEmpty) {
      // Books scanned before any shelf exists: the card is where to start.
      if (!showToShelve) return _buildEmptyState(context);
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _gridMargin),
            child: _buildToShelveLine(context),
          ),
          Expanded(child: _buildEmptyState(context)),
        ],
      );
    }

    return _buildCards(context, showToShelve);
  }

  /// The first-level shelves as cards to walk into, under the "to shelve"
  /// line and the row that leads to organizing them.
  Widget _buildCards(BuildContext context, bool showToShelve) {
    final roots = Tag.getRootTags(_shownTags);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = shelfGridColumns(
          width: width,
          textScale: MediaQuery.textScalerOf(context).scale(1),
        );
        final horizontal = columns == 1;
        final spacing = width >= _wideRowWidth ? 16.0 : 12.0;
        return RefreshIndicator(
          onRefresh: _loadTags,
          child: CustomScrollView(
            key: const Key('shelfCardsScroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: _gridMargin),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showToShelve) _buildToShelveLine(context),
                      _buildGridHead(context, wide: width >= _wideRowWidth),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  _gridMargin,
                  0,
                  _gridMargin,
                  96,
                ),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    mainAxisExtent: ShelfCard.extentFor(
                      context,
                      horizontal: horizontal,
                    ),
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final tag = roots[index];
                    return ShelfCard(
                      key: ValueKey('shelfCard:${tag.name}'),
                      shelfId: tag.id,
                      name: tag.name,
                      books: _aggregatedCount(tag),
                      subShelves: _childrenOf(tag).length,
                      coverPaths: tag.coverPaths,
                      horizontal: horizontal,
                      flight: widget.fanFlight,
                      onTap: () => _openShelfBooks(tag),
                    );
                  }, childCount: roots.length),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// "Organize" at the right; from [_wideRowWidth] the add button, otherwise
  /// floating, at its left.
  Widget _buildGridHead(BuildContext context, {required bool wide}) {
    return Padding(
      // As far from the cards as the cards from each other.
      padding: EdgeInsets.only(top: 8, bottom: wide ? 16 : 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (wide) ...[
            Flexible(
              child: OutlinedButton.icon(
                onPressed: _showCreateShelfDialog,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
                icon: const Icon(Icons.add),
                label: Text(
                  TranslationService.translate(context, 'create_shelf'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: TextButton.icon(
              focusNode: _organizeFocus,
              onPressed: _openOrganize,
              style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.tune),
              label: Text(
                TranslationService.translate(context, 'organize'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What changes there reaches this grid through the global notifier.
  void _openOrganize() => context.push('/shelves-management');

  /// The books on no shelf, in one sober line: a tap lists them in this tab
  /// with selection armed, ready for the bulk shelving sheet; the cross hides
  /// the line until there are more of them. Coming back to the grid remounts
  /// this screen, which reloads the count.
  Widget _buildToShelveLine(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final title = TranslationService.translate(context, 'to_shelve_title');
    final radius = BorderRadius.circular(12);
    return Padding(
      key: const Key('toShelveCard'),
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: AppDesign.subtleShadow,
        ),
        child: Material(
          color: shelfSurfaceColor(Theme.of(context)),
          shape: shelfSurfaceShape(Theme.of(context), 12),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              Expanded(
                // One button, read as the whole sentence.
                child: MergeSemantics(
                  child: Semantics(
                    button: true,
                    label:
                        '$title, ${_plural(context, 'to_shelve_count', _unshelvedCount)}',
                    child: InkWell(
                      onTap: () => context.go(toShelveLocation),
                      child: ExcludeSemantics(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.move_to_inbox_outlined,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        TextSpan(
                                          text:
                                              ' · ${_plural(context, 'displayed_books_count', _unshelvedCount)}',
                                        ),
                                      ],
                                    ),
                                    style: textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: const Icon(Icons.close),
                tooltip: TranslationService.translate(
                  context,
                  'to_shelve_hide',
                ),
                onPressed: _hideToShelveLine,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _hideToShelveLine() {
    final count = _unshelvedCount;
    setState(() => _toShelveDismissedAt = count);
    _organizeFocus.requestFocus();
    unawaited(ToShelveDismissalStore.dismissAt(count));
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

  /// Creates a shelf at the first level.
  void _showCreateShelfDialog() => showNewShelfDialog(
    context,
    shownTags: _shownTags,
    onCreated: _loadTags,
  );
}
