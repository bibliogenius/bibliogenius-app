import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/book.dart';
import '../models/collection.dart';
import '../services/translation_service.dart';
import 'book_cover_card.dart';
import 'cached_book_cover.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// Groups books by their collection for display in the library grid.
/// [collection] is null for books that belong to no collection.
class CollectionGroup {
  final Collection? collection;
  final List<Book> books;

  const CollectionGroup({
    required this.collection,
    required this.books,
  });

  /// Up to 4 cover URLs for the stack display (books with a cover, front first).
  List<String?> get stackCoverUrls {
    return books
        .where((b) => b.coverUrl != null && b.coverUrl!.isNotEmpty)
        .map((b) => b.coverUrl)
        .take(4)
        .toList();
  }

  int get ownedCount => books.where((b) => b.owned).length;
}

// ---------------------------------------------------------------------------
// CollectionStackWidget
// ---------------------------------------------------------------------------

/// Displays a collection as a fan of stacked book covers.
///
/// Tapping opens [CollectionGroupBottomSheet] with the full book list
/// and a link to the collection detail page.
class CollectionStackWidget extends StatefulWidget {
  final CollectionGroup group;

  /// Called when the user navigates to the collection page from the bottom
  /// sheet. If null, the widget navigates via GoRouter automatically.
  final VoidCallback? onCollectionTap;

  const CollectionStackWidget({
    super.key,
    required this.group,
    this.onCollectionTap,
  });

  @override
  State<CollectionStackWidget> createState() => _CollectionStackWidgetState();
}

class _CollectionStackWidgetState extends State<CollectionStackWidget> {
  bool _pressed = false;

  void _onTapDown(TapDownDetails _) => setState(() => _pressed = true);
  void _onTapUp(TapUpDetails _) => setState(() => _pressed = false);
  void _onTapCancel() => setState(() => _pressed = false);

  void _onTap() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CollectionGroupBottomSheet(
        group: widget.group,
        onCollectionTap: widget.onCollectionTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final name = group.collection?.name ??
        TranslationService.translate(context, 'collection_group_uncollected');
    final bookCount = group.books.length;

    final booksLabel =
        TranslationService.translate(context, 'collection_group_books_count');
    final tapHint =
        TranslationService.translate(context, 'collection_group_tap_hint');
    final semanticLabel = '$name, $bookCount $booksLabel. $tapHint';

    final ownedLabel = TranslationService.translate(
      context,
      'collection_owned_count',
    ).replaceAll('{n}', '${group.ownedCount}');
    final tooltipMessage = '$name\n$bookCount $booksLabel - $ownedLabel';

    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltipMessage,
        preferBelow: false,
        child: GestureDetector(
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          onTap: _onTap,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedScale(
              scale: _pressed ? 0.93 : 1.0,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: _StackedCovers(
                covers: group.stackCoverUrls,
                bookCount: bookCount,
                ownedCount: group.ownedCount,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _StackedCovers
// ---------------------------------------------------------------------------

// Layer config: [rotation in deg, x offset, y offset]
// Listed back to front (index 0 = furthest back, last index = front).
const _kLayerConfigs = [
  [-11.0, -15.0, -5.0], // furthest back
  [-5.0, -7.0, -3.0], // second
  [6.0, 8.0, -1.0], // third
  [0.0, 0.0, 0.0], // front
];

class _StackedCovers extends StatelessWidget {
  final List<String?> covers;
  final int bookCount;
  final int ownedCount;

  const _StackedCovers({
    required this.covers,
    required this.bookCount,
    this.ownedCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleCount = math.min(
      covers.isEmpty ? 1 : covers.length,
      _kLayerConfigs.length,
    );
    // Slice the layer configs from the back, keeping `visibleCount` entries.
    final activeLayers = _kLayerConfigs.sublist(
      _kLayerConfigs.length - visibleCount,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth;
        final availH = constraints.maxHeight;

        // When stacking multiple covers, the front cover uses 82% of the width
        // to leave room for the fan effect. A single cover fills more space.
        final widthRatio = visibleCount == 1 ? 0.94 : 0.82;
        final coverW = availW * widthRatio;
        final coverH = math.min(availH * 0.94, coverW / 0.67);

        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Render layers back to front.
            for (int i = 0; i < visibleCount; i++)
              _CoverLayer(
                coverUrl: covers.length > i ? covers[i] : null,
                config: activeLayers[i],
                coverW: coverW,
                coverH: coverH,
                isTop: i == visibleCount - 1,
                theme: theme,
              ),

            // "Collection" tag, anchored to the top-right of the front cover.
            Positioned(
              top: (availH - coverH) / 2 + 4,
              right: (availW - coverW) / 2 + 4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  TranslationService.translate(context, 'collection_tag')
                      .toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    height: 1,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),

            // Book count badge, anchored to the top-right of the front cover.
            if (bookCount > 1)
              Positioned(
                top: (availH - coverH) / 2,
                right: (availW - coverW) / 2 - 6,
                child: _CountBadge(count: bookCount),
              ),

            // Progress bar overlay (always visible).
            if (bookCount > 0)
              Positioned(
                bottom: (availH - coverH) / 2,
                left: 0,
                right: 0,
                child: _ProgressOverlay(
                  owned: ownedCount,
                  total: bookCount,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CoverLayer extends StatelessWidget {
  final String? coverUrl;
  final List<double> config; // [rotDeg, xOffset, yOffset]
  final double coverW;
  final double coverH;
  final bool isTop;
  final ThemeData theme;

  const _CoverLayer({
    required this.coverUrl,
    required this.config,
    required this.coverW,
    required this.coverH,
    required this.isTop,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final rotation = config[0] * math.pi / 180;
    final xOffset = config[1];
    final yOffset = config[2];

    return Transform.translate(
      offset: Offset(xOffset, yOffset),
      child: Transform.rotate(
        angle: rotation,
        child: Container(
          width: coverW,
          height: coverH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isTop ? 0.28 : 0.14),
                blurRadius: isTop ? 14 : 6,
                spreadRadius: isTop ? 0 : -1,
                offset: Offset(isTop ? 2 : 1, isTop ? 5 : 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CachedBookCover(
              imageUrl: coverUrl,
              width: coverW,
              height: coverH,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _CountBadge
// ---------------------------------------------------------------------------

class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.4),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CollectionGroupBottomSheet
// ---------------------------------------------------------------------------

/// Bottom sheet shown when a [CollectionStackWidget] is tapped.
///
/// Displays a horizontal cover strip, a list of books, and a button
/// linking to the full collection page.
class CollectionGroupBottomSheet extends StatelessWidget {
  final CollectionGroup group;
  final VoidCallback? onCollectionTap;

  const CollectionGroupBottomSheet({
    super.key,
    required this.group,
    this.onCollectionTap,
  });

  void _navigateToCollection(BuildContext context) {
    Navigator.of(context).pop();
    if (onCollectionTap != null) {
      onCollectionTap!();
    } else if (group.collection != null) {
      context.push('/collections/${group.collection!.id}', extra: group.collection);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final collectionName = group.collection?.name ??
        TranslationService.translate(context, 'collection_group_uncollected');
    final viewAllLabel =
        TranslationService.translate(context, 'collection_view_all');
    final ownedLabel = TranslationService.translate(
      context,
      'collection_owned_count',
    ).replaceAll('{n}', '${group.ownedCount}');
    final booksLabel =
        TranslationService.translate(context, 'collection_group_books_count');

    return DraggableScrollableSheet(
      initialChildSize: 0.58,
      minChildSize: 0.38,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return _SheetContent(
          theme: theme,
          collectionName: collectionName,
          viewAllLabel: viewAllLabel,
          ownedLabel: ownedLabel,
          booksLabel: booksLabel,
          group: group,
          scrollController: scrollController,
          onNavigateToCollection: group.collection != null
              ? () => _navigateToCollection(context)
              : null,
        );
      },
    );
  }
}

class _SheetContent extends StatelessWidget {
  final ThemeData theme;
  final String collectionName;
  final String viewAllLabel;
  final String ownedLabel;
  final String booksLabel;
  final CollectionGroup group;
  final ScrollController scrollController;
  final VoidCallback? onNavigateToCollection;

  const _SheetContent({
    required this.theme,
    required this.collectionName,
    required this.viewAllLabel,
    required this.ownedLabel,
    required this.booksLabel,
    required this.group,
    required this.scrollController,
    required this.onNavigateToCollection,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHandle(),
          _buildHeader(context),
          _buildCoverStrip(),
          const SizedBox(height: 4),
          Divider(height: 1, color: theme.dividerColor),
          Expanded(
            child: _buildBookList(context),
          ),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: theme.dividerColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    collectionName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (onNavigateToCollection != null) ...[
                const SizedBox(width: 12),
                Semantics(
                  button: true,
                  label: viewAllLabel,
                  child: _ViewAllButton(
                    label: viewAllLabel,
                    onTap: onNavigateToCollection!,
                    theme: theme,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$ownedLabel  -  ${group.books.length} $booksLabel',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverStrip() {
    return SizedBox(
      height: 116,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        itemCount: group.books.length,
        separatorBuilder: (context, i) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final book = group.books[index];
          return Semantics(
            image: true,
            label: '${book.title}, ${book.author ?? ''}',
            child: CachedBookCover(
              imageUrl: book.coverUrl,
              width: 68,
              height: 102,
              borderRadius: BorderRadius.circular(6),
              fit: BoxFit.cover,
            ),
          );
        },
      ),
    );
  }

  Widget _buildBookList(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      itemCount: group.books.length,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemBuilder: (context, index) {
        return _BookTile(
          book: group.books[index],
          onTap: () {
            Navigator.of(context).pop();
            final id = group.books[index].id;
            if (id != null) context.push('/books/$id');
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// _ViewAllButton
// ---------------------------------------------------------------------------

class _ViewAllButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final ThemeData theme;

  const _ViewAllButton({
    required this.label,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.28),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_forward_rounded,
              size: 14,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _BookTile
// ---------------------------------------------------------------------------

class _BookTile extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;

  const _BookTile({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '${book.title}, ${book.author ?? ''}',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          child: Row(
            children: [
              CachedBookCover(
                imageUrl: book.coverUrl,
                width: 36,
                height: 54,
                borderRadius: BorderRadius.circular(4),
                fit: BoxFit.cover,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (book.author != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        book.author!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.28),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CollectionCoverCard - used in collection_list_screen.dart
// ---------------------------------------------------------------------------

/// Displays a collection as stacked book covers with the collection name
/// below in dark text.
///
/// When the collection has no book covers, a colored placeholder is shown
/// (matching the default library fallback style).
/// Tapping navigates to the collection detail page.
class CollectionCoverCard extends StatefulWidget {
  final Collection collection;
  final List<String?> coverUrls;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const CollectionCoverCard({
    super.key,
    required this.collection,
    required this.coverUrls,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<CollectionCoverCard> createState() => _CollectionCoverCardState();
}

class _CollectionCoverCardState extends State<CollectionCoverCard> {
  bool _pressed = false;

  /// Generate a stable color from the collection name.
  Color _colorFromName(String name) {
    final hash = name.hashCode.abs();
    return Color.fromARGB(
      255,
      60 + (hash % 140),
      60 + ((hash >> 8) % 140),
      60 + ((hash >> 16) % 140),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bookCount = widget.collection.totalBooks;
    final booksLabel =
        TranslationService.translate(context, 'collection_group_books_count');
    final semanticLabel =
        '${widget.collection.name}, $bookCount $booksLabel';

    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedScale(
            scale: _pressed ? 0.93 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Covers area
                Expanded(
                  child: widget.coverUrls.isEmpty
                      ? _buildColoredFallback(theme)
                      : _StackedCovers(
                          covers: widget.coverUrls,
                          bookCount: bookCount,
                          ownedCount: widget.collection.ownedBooks,
                        ),
                ),
              const SizedBox(height: 2),
              // Collection name below
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  widget.collection.name,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                    height: 1.15,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  /// Colored placeholder for collections without book covers.
  Widget _buildColoredFallback(ThemeData theme) {
    final color = _colorFromName(widget.collection.name);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth * 0.94;
        final h = math.min(constraints.maxHeight * 0.94, w / 0.67);
        return Center(
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: 0.8), color],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.collections_bookmark,
                color: Colors.white70,
                size: 32,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// _ProgressOverlay - always visible on collection teasers
// ---------------------------------------------------------------------------

class _ProgressOverlay extends StatelessWidget {
  final int owned;
  final int total;

  const _ProgressOverlay({required this.owned, required this.total});

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? owned.toDouble() / total : 0.0;
    final isComplete = owned == total && total > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                  width: 0.5,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 48,
                    child: _buildBar(progress, isComplete),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$owned/$total',
                    style: TextStyle(
                      color: isComplete
                          ? const Color(0xFF6EE7B7)
                          : Colors.white.withValues(alpha: 0.88),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBar(double progress, bool isComplete) {
    return SizedBox(
      height: 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.white.withValues(alpha: 0.22)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              heightFactor: 1.0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isComplete
                        ? const [Color(0xFF34D399), Color(0xFF10B981)]
                        : const [Color(0xFFE0E7FF), Color(0xFFA5B4FC)],
                  ),
                  boxShadow: isComplete
                      ? [
                          BoxShadow(
                            color:
                                const Color(0xFF10B981).withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CollectionGroupGrid - usage in book_list_screen.dart
// ---------------------------------------------------------------------------

/// Drop-in replacement for [BookCoverGrid] when group-by-collection is active.
///
/// Displays a mixed grid of collection stacks (for books in collections) and
/// individual book covers (for uncollected books). Uncollected books behave
/// identically to the default library: tap navigates to the book page.
class CollectionGroupGrid extends StatelessWidget {
  final List<CollectionGroup> groups;
  final Function(Book) onBookTap;

  const CollectionGroupGrid({
    super.key,
    required this.groups,
    required this.onBookTap,
  });

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const _EmptyState();
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 0.72,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        // Uncollected single book: render as a regular cover card.
        if (group.collection == null && group.books.length == 1) {
          final book = group.books.first;
          return BookCoverCard(book: book, onTap: () => onBookTap(book));
        }
        // Collection with books: render as stacked covers.
        return CollectionStackWidget(group: group);
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.collections_bookmark, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            TranslationService.translate(
              context,
              'collection_group_empty',
            ),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}
