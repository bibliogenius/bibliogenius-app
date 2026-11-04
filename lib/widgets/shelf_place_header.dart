import 'package:flutter/material.dart';

import '../models/tag.dart';
import '../services/translation_service.dart';
import 'shelf_card.dart';
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
    return SliverMainAxisGroup(
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
              onTap: () => place.actions.onOpen(tag),
            );
          }, childCount: place.subShelves.length),
        );
      },
    );
  }
}

/// The way back, where the reader is, the shelf's name in large, its counts,
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
              _PlaceMenu(place: place),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (place.ancestors.isNotEmpty)
                        _PathChip(place: place),
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
                const SizedBox(width: 12),
                ShelfThumbnail(
                  key: const Key('shelfPlaceFan'),
                  size: ShelfThumbnailSize.xl,
                  hasBooks: place.books > 0,
                  coverPaths: shelf.coverPaths,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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

/// "in Genre › Polar", and "… › Genre › Polar" further down: a tap goes up to
/// the parent.
class _PathChip extends StatelessWidget {
  final ShelfPlace place;

  const _PathChip({required this.place});

  @override
  Widget build(BuildContext context) {
    final ancestors = place.ancestors;
    final parent = ancestors.last;
    final last = ancestors.length >= 2
        ? ancestors.sublist(ancestors.length - 2)
        : ancestors;
    final path = last.map((t) => t.name).join(' › ');
    final label = ancestors.length >= 3
        ? '… › $path'
        : TranslationService.translate(
            context,
            'shelf_in_path',
          ).replaceAll('{path}', path);
    final theme = Theme.of(context);
    // Drawn 32 pt high, inside a 44 pt target.
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          key: const Key('shelfPlaceChip'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => place.actions.onOpen(parent),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: 1,
              heightFactor: 1,
              child: Container(
                constraints: const BoxConstraints(minHeight: 32),
                padding: const EdgeInsetsDirectional.only(start: 6, end: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShelfThumbnail(
                      size: ShelfThumbnailSize.xs,
                      hasBooks: place.booksOf(parent) > 0,
                      coverPaths: parent.coverPaths,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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
