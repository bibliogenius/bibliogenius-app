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
  final int Function(Tag) booksOf;
  final int Function(Tag) subShelvesOf;

  /// Out of the way while the books of the shelf are being reordered.
  final bool hidden;

  /// The sub-shelf cards, not their count, while a search runs.
  final bool subShelvesHidden;

  /// Whether the shelf is known from a listing that landed on this page. Before
  /// that nothing can be done to it safely: deleting a shelf taken for one with
  /// no row would strip its name from the books and keep the row.
  final bool canAct;

  /// The colour of the page in the palette, from [ShelfCard.placeTintSlot]. None
  /// until a listing knows the shelf.
  final int? tintSlot;

  /// The fan on its way here, if any, and what the sub-shelf cards send off.
  final ShelfFanFlight? flight;
  final ShelfPlaceActions actions;

  const ShelfPlace({
    required this.requestedName,
    required this.shelf,
    required this.ancestors,
    required this.subShelves,
    required this.books,
    required this.booksOf,
    required this.subShelvesOf,
    required this.hidden,
    this.subShelvesHidden = false,
    required this.canAct,
    this.tintSlot,
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
          if (place.subShelves.isNotEmpty && !place.subShelvesHidden) ...[
            // The section's landmark for screen readers, with nothing on screen:
            // the head announces the sub-shelves and the cards speak for
            // themselves. A sliver with no height, or a node with no surface,
            // would never reach the platform: it keeps a sliver of the gap.
            SliverToBoxAdapter(
              child: Semantics(
                key: const Key('subShelvesMarker'),
                container: true,
                header: true,
                label: TranslationService.translate(context, 'sub_categories'),
                child: const SizedBox(height: 4, width: double.infinity),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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

/// The way back, named after the parent, the shelf's name in large with its
/// actions, its counts; at the top right, its covers in large, on a ground with
/// the colour and the rounding of the card the shelf was entered by. The ground
/// hangs from the angle of the page and takes what the text leaves, as far as
/// the proportions of the band of a card.
class ShelfPlaceHeader extends StatelessWidget {
  /// The air between the covers and the edge of the ground, above and under:
  /// what the lowest tip of a leaning cover leaves on the band of a card.
  static const double _coverMargin = 12.44;

  /// Where the covers of the fan start and end in its frame: the centre one at
  /// the top, the lowest tip of a leaning one at the bottom.
  static const double _coversTop = 7;
  static const double _coversBottom = 74.02;

  static const double _fanTop = _coverMargin - _coversTop;
  static const double _groundHeight =
      _coversBottom - _coversTop + 2 * _coverMargin;

  /// The air above the ground: it is a card laid against the side of the page.
  static const double _groundTop = 12;

  /// The rounding of the two angles that face the page.
  static const BorderRadius _groundRadius = BorderRadius.horizontal(
    left: Radius.circular(20),
  );

  /// The fan and its margins: what a long name leaves the ground at least.
  static const double _groundMinWidth = 148;

  /// Past this, the ground would stop reading as the band of a card and become
  /// a strip across the page.
  static const double _groundMaxWidth = 300;

  /// The margin of the fan from the angle of the page.
  static const double _fanRight = 18;

  /// The air between the text and the ground.
  static const double _textGap = 12;

  /// What the menu asks to be touched. Its room is kept before it comes with the
  /// listing, for neither the name nor the ground to move then.
  static const double _menuTarget = 44;

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
    final slot = place.tintSlot;
    final tint = slot == null
        ? null
        : AppDesign.shelfTint(slot, theme.brightness);
    final text = Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, _textGap, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BackButton(place: place),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: _FadeIn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: _menuTarget),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Semantics(
                            header: true,
                            child: Text(
                              shelf.name,
                              key: const Key('shelfHeaderTitle'),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        if (place.canAct)
                          _PlaceMenu(place: place)
                        else
                          const SizedBox(width: _menuTarget),
                      ],
                    ),
                  ),
                  Text(
                    counts.join(' · '),
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    // Decorative. With no colour known yet it takes the same room with no
    // ground, so the page does not move when the listing lands.
    final ground = SizedBox(
      width: double.infinity,
      height: _groundHeight,
      child: DecoratedBox(
        key: const Key('shelfPlaceCorner'),
        decoration: BoxDecoration(
          gradient: tint == null
              ? null
              : AppDesign.shelfGradient(tint.ground, theme.brightness),
          borderRadius: _groundRadius,
        ),
        child: ClipRRect(
          borderRadius: _groundRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Across from the fan, as on a card: behind it, it would not show.
              if (tint != null)
                Positioned(
                  top: -20,
                  left: -20,
                  child: ExcludeSemantics(
                    child: Icon(
                      Icons.shelves,
                      key: const Key('shelfPlaceWatermark'),
                      size: 100,
                      color: AppDesign.shelfWatermarkColor,
                    ),
                  ),
                ),
              Positioned(
                top: _fanTop,
                right: _fanRight,
                child: _LandingFan(
                  name: shelf.name,
                  flight: place.flight,
                  child: ShelfThumbnail(
                    key: const Key('shelfPlaceFan'),
                    size: ShelfThumbnailSize.xl,
                    hasBooks: place.books > 0,
                    coverPaths: shelf.coverPaths,
                    ghostColor: tint == null
                        ? null
                        : AppDesign.shelfBandGhostColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth - _groundMinWidth,
              ),
              child: text,
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _groundMaxWidth),
                  child: Padding(
                    padding: const EdgeInsets.only(top: _groundTop),
                    child: ground,
                  ),
                ),
              ),
            ),
          ],
        ),
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

/// The actions on this shelf, behind its "…".
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
    // Discreet beside the name, and still 44 pt under a finger: the circle is
    // drawn smaller than the button.
    final circle = AppDesign.tintedCircleButtonStyle(
      Theme.of(context).colorScheme,
    );
    return PopupMenuButton<VoidCallback>(
      key: const Key('shelfPlaceMenu'),
      tooltip: TranslationService.translate(
        context,
        'shelf_actions_named',
      ).replaceAll('{name}', place.shelf.name),
      icon: DecoratedBox(
        key: const Key('shelfPlaceMenuDisc'),
        decoration: BoxDecoration(
          color: circle.backgroundColor?.resolve(const {}),
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(
          dimension: 30,
          child: Icon(
            Icons.more_horiz,
            size: 20,
            color: circle.foregroundColor?.resolve(const {}),
          ),
        ),
      ),
      style: circle.copyWith(
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
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
