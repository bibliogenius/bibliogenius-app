import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/tag.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import 'shelf_card.dart';
import 'shelf_fan_flight.dart';
import 'shelf_thumbnail.dart';

/// What the page of a shelf says about it, published by the list of its books
/// for the head that scrolls with them.
class ShelfPlace {
  /// The name the route asked for: a place for another name is an old one.
  final String requestedName;
  final Tag shelf;

  /// From the first level down to the parent.
  final List<Tag> ancestors;
  final List<Tag> subShelves;

  /// The books of the shelf and of its sub-shelves, as a card counts them.
  final int books;
  final String? lastAddedTitle;
  final int Function(Tag) booksOf;
  final int Function(Tag) subShelvesOf;

  /// Out of the way while the books of the shelf are being reordered.
  final bool hidden;

  /// Whether the shelf is known from a listing that landed on this page. Before
  /// that nothing can be done to it safely: deleting a shelf taken for one with
  /// no row would strip its name from the books and keep the row.
  final bool canAct;

  /// The fan on its way here, if any, and what the sub-shelf cards send off.
  final ShelfFanFlight? flight;
  final ShelfPlaceActions actions;

  const ShelfPlace({
    required this.requestedName,
    required this.shelf,
    required this.ancestors,
    required this.subShelves,
    required this.books,
    required this.lastAddedTitle,
    required this.booksOf,
    required this.subShelvesOf,
    required this.hidden,
    required this.canAct,
    this.flight,
    required this.actions,
  });
}

/// What the head of a shelf's page can ask for.
class ShelfPlaceActions {
  final VoidCallback onBack;
  final ValueChanged<Tag> onOpen;
  final VoidCallback onRename;
  final VoidCallback onAddSubShelf;
  final VoidCallback onMove;
  final VoidCallback onDelete;
  final VoidCallback onOrganize;

  const ShelfPlaceActions({
    required this.onBack,
    required this.onOpen,
    required this.onRename,
    required this.onAddSubShelf,
    required this.onMove,
    required this.onDelete,
    required this.onOrganize,
  });
}

/// The head of a shelf's page and its sub-shelves, as slivers: they scroll
/// with the books, whichever way those are laid out.
class ShelfPlaceSlivers extends StatelessWidget {
  final ShelfPlace place;

  const ShelfPlaceSlivers({super.key, required this.place});

  @override
  Widget build(BuildContext context) {
    // The first colour of the gradient the books below are painted on, so the
    // page reads as one ground: the scaffold's colour would show a seam.
    final ground = AppDesign.pageGradientForTheme(
      context.select<ThemeProvider, String>((p) => p.themeStyle),
    ).colors.first;
    return DecoratedSliver(
      decoration: BoxDecoration(color: ground),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(child: ShelfPlaceHeader(place: place)),
          if (place.subShelves.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Semantics(
                  header: true,
                  child: Text(
                    TranslationService.translate(context, 'sub_categories'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              sliver: _SubShelfGrid(place: place),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubShelfGrid extends StatelessWidget {
  final ShelfPlace place;

  const _SubShelfGrid({required this.place});

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = shelfGridColumns(
          // The rule reads the width of the page, margins included.
          width: constraints.crossAxisExtent + 32,
          textScale: MediaQuery.textScalerOf(context).scale(1),
        );
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: ShelfCard.compactExtentFor(context),
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final tag = place.subShelves[index];
            return ShelfCard.compact(
              key: ValueKey('subShelfCard:${tag.name}'),
              name: tag.name,
              books: place.booksOf(tag),
              subShelves: place.subShelvesOf(tag),
              coverPaths: tag.coverPaths,
              flight: place.flight,
              onTap: () => place.actions.onOpen(tag),
            );
          }, childCount: place.subShelves.length),
        );
      },
    );
  }
}

/// The way back, named after the parent, the shelf's name in large, its counts,
/// what last arrived and its covers in large.
class ShelfPlaceHeader extends StatelessWidget {
  final ShelfPlace place;

  const ShelfPlaceHeader({super.key, required this.place});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shelf = place.shelf;
    final counts = shelfCountLabels(
      context,
      books: place.books,
      subShelves: place.subShelves.length,
    );
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _BackButton(place: place),
                ),
              ),
              if (place.canAct) _PlaceMenu(place: place),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _FadeIn(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            shelf.name,
                            key: const Key('shelfHeaderTitle'),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          counts.join(' · '),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: muted,
                          ),
                        ),
                        if (place.lastAddedTitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: _LastAdded(title: place.lastAddedTitle!),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _LandingFan(
                  name: shelf.name,
                  flight: place.flight,
                  child: ShelfThumbnail(
                    key: const Key('shelfPlaceFan'),
                    size: ShelfThumbnailSize.xl,
                    hasBooks: place.books > 0,
                    coverPaths: shelf.coverPaths,
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

/// What the head says appears as the fan arrives: only the fan travels.
class _FadeIn extends StatelessWidget {
  final Widget child;

  const _FadeIn({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : ShelfFanFlight.duration,
      builder: (context, value, child) => Opacity(
        opacity: value,
        // Announced and touchable from the start: a fade costs no one a second.
        alwaysIncludeSemantics: true,
        child: child,
      ),
      child: child,
    );
  }
}

/// The fan of the head, out of sight while the one from the card flies here.
class _LandingFan extends StatefulWidget {
  final String name;
  final ShelfFanFlight? flight;
  final Widget child;

  const _LandingFan({
    required this.name,
    required this.flight,
    required this.child,
  });

  @override
  State<_LandingFan> createState() => _LandingFanState();
}

class _LandingFanState extends State<_LandingFan> {
  bool _waiting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final flight = widget.flight;
    if (flight == null) return;
    // Hidden from this frame: the flight is up by the time this head builds.
    _waiting = !MediaQuery.disableAnimationsOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      final landed = box == null
          ? null
          : flight.land(widget.name, box.localToGlobal(Offset.zero) & box.size);
      if (landed == null) {
        if (_waiting) setState(() => _waiting = false);
        return;
      }
      landed.then((_) {
        if (mounted) setState(() => _waiting = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) =>
      Opacity(opacity: _waiting ? 0 : 1, child: widget.child);
}

/// "‹ Living room": a way back that says where it leads.
class _BackButton extends StatelessWidget {
  final ShelfPlace place;

  const _BackButton({required this.place});

  @override
  Widget build(BuildContext context) {
    final target = place.ancestors.isEmpty
        ? TranslationService.translate(context, 'shelves')
        : place.ancestors.last.name;
    final back = TranslationService.translate(context, 'back');
    return Semantics(
      label: '$back, $target',
      button: true,
      excludeSemantics: true,
      onTap: place.actions.onBack,
      child: TextButton.icon(
        key: const Key('shelfBackButton'),
        style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
        onPressed: place.actions.onBack,
        icon: Icon(Icons.adaptive.arrow_back),
        label: Text(target, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// "Last arrived here: *title*".
class _LastAdded extends StatelessWidget {
  final String title;

  const _LastAdded({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = TranslationService.translate(
      context,
      'last_added_here',
    ).split('{title}');
    return Text.rich(
      key: const Key('shelfPlaceLastAdded'),
      TextSpan(
        children: [
          TextSpan(text: parts.first),
          TextSpan(
            text: title,
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
          if (parts.length > 1) TextSpan(text: parts[1]),
        ],
      ),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _PlaceMenu extends StatelessWidget {
  final ShelfPlace place;

  const _PlaceMenu({required this.place});

  @override
  Widget build(BuildContext context) {
    final actions = place.actions;
    PopupMenuItem<VoidCallback> item(VoidCallback action, String key) =>
        PopupMenuItem<VoidCallback>(
          value: action,
          child: Text(TranslationService.translate(context, key)),
        );
    return PopupMenuButton<VoidCallback>(
      key: const Key('shelfPlaceMenu'),
      tooltip: TranslationService.translate(
        context,
        'shelf_actions_named',
      ).replaceAll('{name}', place.shelf.name),
      icon: const Icon(Icons.more_horiz),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        item(actions.onRename, 'rename'),
        item(actions.onAddSubShelf, 'add_sub_shelf'),
        item(actions.onMove, 'move_shelf_to'),
        item(actions.onDelete, 'delete'),
        const PopupMenuDivider(),
        item(actions.onOrganize, 'organize_shelves'),
      ],
    );
  }
}
