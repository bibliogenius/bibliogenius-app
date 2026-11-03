import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../models/tag.dart';
import '../services/shelf_tree_collapse_store.dart';
import '../services/translation_service.dart';
import 'shelf_tree_rows.dart';

/// Above this many shelves the tree gets a search field.
const int shelfTreeSearchThreshold = 15;

/// How long the tint of a shelf that just moved takes to fade out.
const Duration shelfTreeFlashDuration = Duration(milliseconds: 200);

/// The shelves tab as one tree: every level in one lazy list, folded by a
/// chevron, rearranged by dragging a shelf onto another one (it goes inside)
/// or onto the first-level zone a drag shows at the head of the tree.
///
/// A shelf can never be dropped on itself or on one of its sub-shelves:
/// that branch greys out while it is in hand and refuses the drop. The drag
/// handle is also a button, "Move Polar", the way to move a shelf without
/// dragging (screen readers, keyboard).
class ShelfTreeView extends StatefulWidget {
  final List<Tag> allTags;

  /// The books a shelf's list shows, its sub-shelves' included.
  final int Function(Tag tag) bookCount;

  /// Scrolls with the tree, above its first row.
  final Widget? header;

  /// A tap on a row: the shelf's books.
  final ValueChanged<Tag> onOpen;

  /// A tap on a row's handle.
  final ValueChanged<Tag> onMoveRequested;

  /// A drop of [shelf] on [parent], null for the first level. Resolves to
  /// true once the shelf has moved and the tree has been reloaded.
  final Future<bool> Function(Tag shelf, Tag? parent) onDrop;

  /// The "…" menu of a row.
  final Widget Function(BuildContext context, Tag tag) menuBuilder;

  final Future<void> Function() onRefresh;

  const ShelfTreeView({
    super.key,
    required this.allTags,
    required this.bookCount,
    this.header,
    required this.onOpen,
    required this.onMoveRequested,
    required this.onDrop,
    required this.menuBuilder,
    required this.onRefresh,
  });

  @override
  State<ShelfTreeView> createState() => _ShelfTreeViewState();
}

class _ShelfTreeViewState extends State<ShelfTreeView> {
  /// The list's scroll position, read from its rows. The list keeps the
  /// controller it inherits: in the library tab that is the inner one of a
  /// NestedScrollView, which a controller of its own would detach.
  ScrollPosition? _position;
  final _filterController = TextEditingController();
  final _listKey = GlobalKey();
  final _flashKey = GlobalKey();
  Timer? _debounce;
  Timer? _autoScroll;
  double _autoScrollStep = 0;
  String _filter = '';
  Set<String> _collapsed = {};

  /// The shelf in hand, while a drag lasts.
  Tag? _dragged;

  /// Set the moment a drag starts and ends, where [_dragged] follows only
  /// after the frame.
  bool _dragActive = false;

  /// The pointer that drags. The drag is followed through it, never
  /// through the Draggable, which stops reporting once the lazy list
  /// unmounts its row. Each row remembers the pointer last put down on it:
  /// a long press starts from a timer, when another finger may have moved
  /// since, so the drag pointer is the one on the row being picked up.
  int? _dragPointer;
  final _rowPointers = <String, int>{};
  final _pointerPositions = <int, Offset>{};

  /// The edge scroll waits until the pointer has been out of both edge
  /// bands once: a shelf picked up inside one must not set the list moving
  /// under the finger that holds it.
  bool _edgesArmed = false;

  /// Room made above the first row while a drag holds at the top of a list
  /// already scrolled to its start, so that the rows the zone covers can
  /// come out from under it. [_hiddenTop] is how much of the list the zone
  /// and the pinned headers cover.
  double _topGap = 0;
  double _hiddenTop = 0;

  /// How much of the top of the tree pinned headers cover: where the
  /// first-level zone goes, so that it shows in sight.
  double _coveredTop = 0;

  /// The shelf that just moved, tinted until it is in view, then fading.
  String? _flashId;
  bool _flashFading = false;

  /// Touch screens pick a shelf up by a long press on its row as well;
  /// a mouse drags by the handle only.
  bool get _longPressPicksUp =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    ShelfTreeCollapseStore.load().then((ids) {
      if (!mounted) return;
      setState(() {
        _collapsed = ids;
        _forgetEmptyFolds();
      });
    });
  }

  @override
  void didUpdateWidget(ShelfTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.allTags, widget.allTags)) _forgetEmptyFolds();
  }

  /// Forgets the fold of a shelf left with no sub-shelf: kept, it would
  /// hide the next sub-shelf filed there.
  void _forgetEmptyFolds() {
    final children = Tag.childrenIndex(widget.allTags);
    final before = _collapsed.length;
    _collapsed.removeWhere((id) => children[id]?.isEmpty ?? true);
    if (_collapsed.length != before) ShelfTreeCollapseStore.save(_collapsed);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _autoScroll?.cancel();
    _filterController.dispose();
    super.dispose();
  }

  bool get _searchShown => widget.allTags.length > shelfTreeSearchThreshold;

  bool get _filtering => _searchShown && _filter.isNotEmpty;

  void _onFilterChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _filter = shelfNameKey(value));
    });
  }

  void _toggle(Tag tag) {
    setState(() {
      if (!_collapsed.remove(tag.id)) _collapsed.add(tag.id);
    });
    ShelfTreeCollapseStore.save(_collapsed);
  }

  /// The rows to draw: the folded branches left out, or, while searching,
  /// the matches and the shelves above them.
  List<ShelfTreeEntry> _visibleEntries(Map<String?, List<Tag>> children) {
    final entries = flattenShelfTree(widget.allTags);
    if (_filtering) {
      final parents = Tag.effectiveParentIds(widget.allTags);
      final kept = <String>{};
      for (final entry in entries) {
        if (!shelfNameKey(entry.tag.name).contains(_filter)) continue;
        String? id = entry.tag.id;
        while (id != null && kept.add(id)) {
          id = parents[id];
        }
      }
      return [
        for (final e in entries)
          if (kept.contains(e.tag.id)) e,
      ];
    }
    final shown = <ShelfTreeEntry>[];
    int? foldedDepth;
    for (final entry in entries) {
      if (foldedDepth != null && entry.depth > foldedDepth) continue;
      foldedDepth = null;
      shown.add(entry);
      final hasChildren = children[entry.tag.id]?.isNotEmpty ?? false;
      if (hasChildren && _collapsed.contains(entry.tag.id)) {
        foldedDepth = entry.depth;
      }
    }
    return shown;
  }

  /// The shelf in hand and its whole branch: never a place to drop it.
  Set<String> get _forbiddenIds {
    final dragged = _dragged;
    if (dragged == null) return const {};
    return {dragged.id, ...Tag.getDescendantIds(dragged.id, widget.allTags)};
  }

  bool _accepts(Tag shelf, Tag? parent) {
    final forbidden =
        parent != null &&
        (parent.id == shelf.id ||
            Tag.getDescendantIds(shelf.id, widget.allTags).contains(parent.id));
    if (forbidden) {
      HapticFeedback.lightImpact();
      return false;
    }
    // Where it already is: dropping there would change nothing.
    return Tag.effectiveParentId(shelf, widget.allTags) != parent?.id;
  }

  // Every state change of a drag waits for the end of the frame: on macOS,
  // a list rebuilt while the mouse tracker dispatches the pointer event that
  // ended the drag trips its `!_debugDuringDeviceUpdate` assertion.
  void _afterFrame(VoidCallback change) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(change);
    });
  }

  void _onDragStarted(Tag tag) {
    _dragActive = true;
    _dragPointer = _rowPointers[tag.id];
    _edgesArmed = false;
    // The event that started the drag came before it: where it left the
    // pointer decides whether the edges are armed already.
    final at = _pointerPositions[_dragPointer];
    if (at != null) _followDrag(at);
    final covered = _overlappedTop();
    _afterFrame(() {
      // Let go before the frame: the drag is already over.
      if (!_dragActive) return;
      _dragged = tag;
      _coveredTop = covered;
    });
  }

  /// In the library tab the tree is the body of a NestedScrollView: once
  /// its header has scrolled away, the pinned tabs cover the top of the
  /// body. The sliver that holds the body is told by how much, the figure a
  /// SliverOverlapAbsorber would read. Zero anywhere else. The tree is
  /// assumed to start at the top of that body, as it does in the tab.
  double _overlappedTop() {
    RenderObject? node = context.findRenderObject();
    while (node != null && node is! RenderSliver) {
      node = node.parent;
    }
    if (node is RenderSliver && node.geometry != null) {
      return node.constraints.overlap;
    }
    return 0;
  }

  void _onDragEnded() {
    _dragActive = false;
    _dragPointer = null;
    _stopAutoScroll();
    _afterFrame(() {
      _dragged = null;
      _topGap = 0;
    });
  }

  void _onPointerSeen(PointerEvent event) {
    _pointerPositions[event.pointer] = event.position;
    if (_dragActive && event.pointer == _dragPointer) {
      _followDrag(event.position);
    }
  }

  /// Ends a drag whatever became of the row it started from: a Draggable
  /// that the lazy list or a reload has unmounted never reports its end.
  /// Another finger lifting leaves it alone.
  void _onPointerGone(PointerEvent event) {
    _pointerPositions.remove(event.pointer);
    if (_dragActive && event.pointer == _dragPointer) _onDragEnded();
  }

  /// Writes at once, redraws after the frame. The target was judged when
  /// the pointer entered it: a reload since may have made it a sub-shelf of
  /// the shelf in hand, so it is judged again.
  ///
  /// The shelf in hand was captured when the drag started: it is read again
  /// from the tree as it is now, so that a rename synced meanwhile is not
  /// written back over.
  void _drop(Tag picked, Tag? target) {
    final shelf = _current(picked);
    final parent = target == null ? null : _current(target);
    if (shelf == null ||
        (target != null && parent == null) ||
        !_accepts(shelf, parent)) {
      _onDragEnded();
      return;
    }
    final moved = widget.onDrop(shelf, parent);
    _onDragEnded();
    moved.then((ok) {
      if (!ok || !mounted) return;
      // The reload that followed the write rebuilds this tree at the end of
      // the frame: the shelf is looked for there, by name, since a shelf
      // given its row on the way has a new id.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reveal(shelf.name);
      });
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  /// [tag] as the tree holds it now, or null once it is gone. A shelf known
  /// only from the books' subjects has no stable id: it is found by name.
  Tag? _current(Tag tag) {
    for (final t in widget.allTags) {
      if (tag.isPersisted ? t.id == tag.id : t.name == tag.name) return t;
    }
    return null;
  }

  /// Brings the shelf that just moved into view, its new parents unfolded,
  /// then lets its tint fade.
  void _reveal(String name) {
    final shelf = widget.allTags.where((t) => t.name == name).firstOrNull;
    if (shelf == null) return;
    final id = shelf.id;
    final parents = Tag.effectiveParentIds(widget.allTags);
    var unfolded = false;
    for (var p = parents[id]; p != null; p = parents[p]) {
      unfolded = _collapsed.remove(p) || unfolded;
    }
    if (unfolded) ShelfTreeCollapseStore.save(_collapsed);
    setState(() {
      _flashId = id;
      _flashFading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _scrollTo(id);
      if (mounted && _flashId == id) setState(() => _flashFading = true);
    });
  }

  Future<void> _scrollTo(String id) async {
    final position = _position;
    if (!mounted || position == null || !position.hasPixels) return;
    var target = _flashKey.currentContext;
    if (target == null) {
      // Not built yet: jump close to it, the lazy list builds it, then
      // finish the way.
      final index = _visibleEntries(
        Tag.childrenIndex(widget.allTags),
      ).indexWhere((e) => e.tag.id == id);
      if (index < 0) return;
      position.jumpTo(
        (index * _estimatedRowHeight).clamp(0, position.maxScrollExtent),
      );
      await WidgetsBinding.instance.endOfFrame;
      target = _flashKey.currentContext;
    }
    if (target == null || !target.mounted) return;
    await Scrollable.ensureVisible(
      target,
      alignment: 0.5,
      duration: shelfTreeFlashDuration,
    );
  }

  /// Scrolls while a drag hovers near the top or the bottom of the list, so
  /// a shelf can be dropped on a row off screen.
  void _followDrag(Offset globalPosition) {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    final position = _position;
    if (box == null || !box.hasSize || position == null) return;
    // The headers may scroll back during the drag: the zone follows.
    final covered = _overlappedTop();
    if (covered != _coveredTop) _afterFrame(() => _coveredTop = covered);
    final y = box.globalToLocal(globalPosition).dy;
    final listTop = box.localToGlobal(Offset.zero).dy;
    final viewTop = (context.findRenderObject() as RenderBox)
        .localToGlobal(Offset.zero)
        .dy;
    // The visible top of the list: below the zone, which sits below the
    // pinned headers. Over the zone itself nothing scrolls.
    final top = (viewTop + covered + _zoneExtent - listTop).clamp(
      0.0,
      box.size.height,
    );
    _hiddenTop = top;
    final inTopBand = y >= top && y < top + _autoScrollEdge;
    final inBottomBand = y > box.size.height - _autoScrollEdge;
    if (!inTopBand && !inBottomBand) _edgesArmed = true;
    double step = 0;
    if (_edgesArmed &&
        inTopBand &&
        (position.pixels > position.minScrollExtent || _topGap < top)) {
      step = -_autoScrollSpeed;
    } else if (_edgesArmed &&
        inBottomBand &&
        position.pixels < position.maxScrollExtent) {
      step = _autoScrollSpeed;
    }
    _autoScrollStep = step;
    if (step == 0) {
      _stopAutoScroll();
    } else {
      _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
        final p = _position;
        if (p == null || !p.hasPixels) return _stopAutoScroll();
        if (_autoScrollStep < 0 && p.pixels <= p.minScrollExtent) {
          // At the start already: grow the room above the first row, at
          // the pace of the scroll.
          if (_topGap >= _hiddenTop) return _stopAutoScroll();
          setState(() {
            _topGap = (_topGap + _autoScrollSpeed).clamp(0.0, _hiddenTop);
          });
          return;
        }
        final next = (p.pixels + _autoScrollStep).clamp(
          p.minScrollExtent,
          p.maxScrollExtent,
        );
        if (next == p.pixels) return _stopAutoScroll();
        p.jumpTo(next);
      });
    }
  }

  void _stopAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  String _t(String key) => TranslationService.translate(context, key);

  String _plural(String key, int count) =>
      _t(count == 1 ? key : '${key}_plural').replaceAll('%d', '$count');

  @override
  Widget build(BuildContext context) {
    final children = Tag.childrenIndex(widget.allTags);
    final entries = _visibleEntries(children);
    final forbidden = _forbiddenIds;
    final headerCount = widget.header == null ? 0 : 1;
    // Each item keyed by its shelf, so that a reload during a drag keeps
    // the element of the row in hand instead of handing it another shelf.
    final indexOfKey = <String, int>{
      if (headerCount > 0) _itemKey(null): 0,
      for (var i = 0; i < entries.length; i++)
        _itemKey(entries[i].tag.id): i + headerCount,
    };

    // The zone lies over the tree rather than in it: a list that made room
    // for it would move the rows under the finger that just picked one up.
    return Listener(
      onPointerDown: _onPointerSeen,
      onPointerMove: _onPointerSeen,
      onPointerUp: _onPointerGone,
      onPointerCancel: _onPointerGone,
      child: Stack(
        children: [
          Column(
            children: [
              if (_searchShown) _buildSearchField(),
              Expanded(
                child: KeyedSubtree(
                  key: _listKey,
                  child: RefreshIndicator(
                    onRefresh: widget.onRefresh,
                    child: ListView.builder(
                      key: const Key('shelfTreeList'),
                      padding: EdgeInsets.fromLTRB(8, _topGap, 8, 96),
                      itemCount: entries.length + headerCount,
                      findChildIndexCallback: (key) => key is ValueKey<String>
                          ? indexOfKey[key.value]
                          : null,
                      itemBuilder: (context, index) {
                        _position = Scrollable.maybeOf(context)?.position;
                        if (index < headerCount) {
                          return KeyedSubtree(
                            key: ValueKey(_itemKey(null)),
                            child: widget.header!,
                          );
                        }
                        final entry = entries[index - headerCount];
                        return KeyedSubtree(
                          key: ValueKey(_itemKey(entry.tag.id)),
                          child: _buildRow(
                            entry,
                            hasChildren:
                                children[entry.tag.id]?.isNotEmpty ?? false,
                            subShelves: children[entry.tag.id]?.length ?? 0,
                            forbidden: forbidden.contains(entry.tag.id),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_dragged != null)
            Positioned(
              top: _coveredTop,
              left: 0,
              right: 0,
              child: _buildFirstLevelZone(),
            ),
        ],
      ),
    );
  }

  static String _itemKey(String? shelfId) =>
      shelfId == null ? 'shelfTreeItem:header' : 'shelfTreeItem:$shelfId';

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        key: const Key('shelfTreeSearch'),
        controller: _filterController,
        onChanged: _onFilterChanged,
        decoration: InputDecoration(
          // A label, not a hint: it stays readable once the reader types.
          labelText: _t('filter_shelves_hint'),
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildFirstLevelZone() {
    final scheme = Theme.of(context).colorScheme;
    // One node: a screen reader user moves shelves with the handle's button,
    // the zone only needs to say what it is.
    return Semantics(
      container: true,
      label: _t('first_level'),
      excludeSemantics: true,
      child: DragTarget<Tag>(
        key: const Key('shelfTreeFirstLevelZone'),
        onWillAcceptWithDetails: (details) => _accepts(details.data, null),
        onAcceptWithDetails: (details) => _drop(details.data, null),
        builder: (context, candidates, _) {
          final hovered = candidates.isNotEmpty;
          return Container(
            height: _zoneExtent - 16,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            decoration: BoxDecoration(
              color: hovered ? scheme.primaryContainer : scheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.primary, width: 2),
              boxShadow: kElevationToShadow[4],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.arrow_upward, color: scheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _t('first_level'),
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// "12 books · 2 sub-shelves": computed once per row, for its second
  /// line and for the card a drag carries.
  String _counts(Tag tag, int subShelves) => [
    _plural('displayed_books_count', widget.bookCount(tag)),
    if (subShelves > 0) _plural('sub_shelves_count', subShelves),
  ].join(' · ');

  String _subtitle(
    ShelfTreeEntry entry,
    String counts, {
    required bool hovered,
  }) {
    final tag = entry.tag;
    if (tag.id == _dragged?.id) return _t('shelf_being_moved');
    if (hovered) return _t('shelf_drop_into').replaceAll('{name}', tag.name);
    // Past the indentation cap the row no longer shows its level: it names
    // its parents instead.
    final path = entry.depth > shelfTreeMaxIndentDepth
        ? shelfParentPath(context, entry.ancestors)
        : null;
    return [?path, counts].join(' · ');
  }

  Widget _buildRow(
    ShelfTreeEntry entry, {
    required bool hasChildren,
    required int subShelves,
    required bool forbidden,
  }) {
    final tag = entry.tag;
    final foldable = hasChildren && !_filtering;
    final counts = _counts(tag, subShelves);
    return DragTarget<Tag>(
      onWillAcceptWithDetails: (details) => _accepts(details.data, tag),
      onAcceptWithDetails: (details) => _drop(details.data, tag),
      builder: (context, candidates, _) {
        final hovered = candidates.isNotEmpty;
        Widget row = ShelfTreeRow(
          key: ValueKey('shelfTreeRow:${tag.name}'),
          name: tag.name,
          depth: entry.depth,
          subtitle: _subtitle(entry, counts, hovered: hovered),
          highlighted: hovered,
          legibleSubtitle: tag.id == _dragged?.id,
          onTap: forbidden ? null : () => widget.onOpen(tag),
          leading: foldable ? _buildChevron(tag) : const SizedBox.shrink(),
          actions: [
            _buildHandle(tag, counts),
            widget.menuBuilder(context, tag),
          ],
        );
        // The same wrappers whether a drag is on or not: a change of shape
        // would rebuild the row's Draggable mid-drag, and a Draggable gone
        // from the tree never reports the end of its drag.
        row = MouseRegion(
          cursor: forbidden ? SystemMouseCursors.forbidden : MouseCursor.defer,
          child: _FadingTint(
            key: tag.id == _flashId ? _flashKey : null,
            tinted: tag.id == _flashId,
            fading: _flashFading,
            child: row,
          ),
        );
        if (_longPressPicksUp) {
          row = LongPressDraggable<Tag>(
            data: tag,
            feedback: _buildFeedback(tag, counts),
            dragAnchorStrategy: (_, _, _) => Offset(_feedbackWidth / 2, 30),
            // One shelf in hand at a time.
            maxSimultaneousDrags: _dragActive ? 0 : 1,
            onDragStarted: () => _onDragStarted(tag),
            onDragEnd: (_) => _onDragEnded(),
            child: row,
          );
        }
        return Listener(
          onPointerDown: (event) => _rowPointers[tag.id] = event.pointer,
          child: row,
        );
      },
    );
  }

  Widget _buildChevron(Tag tag) {
    final collapsed = _collapsed.contains(tag.id);
    final key = collapsed ? 'shelf_expand_named' : 'shelf_collapse_named';
    // One node: the button, its name and whether the branch is open.
    return MergeSemantics(
      child: Semantics(
        expanded: !collapsed,
        child: IconButton(
          constraints: const BoxConstraints.tightFor(
            width: shelfTreeLeadingWidth,
            height: shelfTreeLeadingWidth,
          ),
          padding: EdgeInsets.zero,
          icon: Icon(collapsed ? Icons.chevron_right : Icons.expand_more),
          tooltip: _t(key).replaceAll('{name}', tag.name),
          onPressed: () => _toggle(tag),
        ),
      ),
    );
  }

  Widget _buildHandle(Tag tag, String counts) {
    return Draggable<Tag>(
      data: tag,
      feedback: _buildFeedback(tag, counts),
      // The card hangs from the handle, at its right end, as if held there.
      dragAnchorStrategy: (_, _, _) => Offset(_feedbackWidth - 24, 30),
      maxSimultaneousDrags: _dragActive ? 0 : 1,
      onDragStarted: () => _onDragStarted(tag),
      onDragEnd: (_) => _onDragEnded(),
      child: IconButton(
        key: ValueKey('shelfTreeHandle:${tag.name}'),
        icon: const Icon(Icons.drag_indicator),
        tooltip: _t('move_shelf_named').replaceAll('{name}', tag.name),
        onPressed: () => widget.onMoveRequested(tag),
      ),
    );
  }

  double get _feedbackWidth =>
      (MediaQuery.sizeOf(context).width - 32).clamp(200.0, 360.0);

  /// The shelf as it follows the pointer: its name and what it holds.
  Widget _buildFeedback(Tag tag, String summary) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      color: theme.colorScheme.surface,
      child: SizedBox(
        width: _feedbackWidth,
        height: 60,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.shelves, color: theme.colorScheme.onSurface),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tag.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.drag_indicator, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// Height of the first-level zone, its margins included.
const double _zoneExtent = 68;

// Auto-scroll: how close to an edge a drag starts scrolling, and how far
// each tick goes.
const double _autoScrollEdge = 56;
const double _autoScrollSpeed = 12;

/// Rough height of a row, to jump near one the lazy list has not built.
const double _estimatedRowHeight = 56;

/// A tint over [child] while [tinted], held until [fading], then faded out.
class _FadingTint extends StatelessWidget {
  final bool tinted;
  final bool fading;
  final Widget child;

  const _FadingTint({
    super.key,
    required this.tinted,
    required this.fading,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primaryContainer;
    return Stack(
      children: [
        // First and always there: the row keeps its state when the tint
        // comes and goes.
        child,
        if (tinted)
          Positioned.fill(
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 1, end: fading ? 0 : 1),
                duration: shelfTreeFlashDuration,
                builder: (context, opacity, _) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: opacity * 0.8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
