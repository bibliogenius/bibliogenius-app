import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import 'cached_book_cover.dart';

/// Scope of the carousel — controls which [ThemeProvider] flag backs its
/// visibility so the own-lib and peer-lib carousels can be toggled
/// independently.
enum RecentlyAddedCarouselScope { ownLib, peerLib }

/// Horizontal strip of recently added books displayed at the top of a library
/// view. Books are filtered via [Book.isNew] (addedAt within the "new badge"
/// threshold).
///
/// Three display states:
/// - **expanded**: full strip of covers (default, ~165 px tall)
/// - **collapsed**: single-row summary with count — auto-triggered when the
///   list below is scrolled, or via the chevron toggle
/// - **hidden**: widget is gone; long-press on the chevron dismisses durably
///
/// Collapsed state is session-local (lives in [ThemeProvider] but not
/// persisted); hidden state persists to SharedPreferences so the choice
/// survives across navigation and can be restored from settings.
class RecentlyAddedCarousel extends StatelessWidget {
  const RecentlyAddedCarousel({
    super.key,
    required this.books,
    required this.scope,
    this.maxItems = 5,
    this.onBookTap,
  });

  final List<Book> books;
  final RecentlyAddedCarouselScope scope;
  final int maxItems;

  /// Optional override for tap handling. Defaults to GoRouter push to
  /// `/books/:id` (own-lib route). Peer lib screens should pass a custom
  /// handler because their detail route differs.
  final void Function(Book book)? onBookTap;

  static const double _coverWidth = 100;
  static const double _coverHeight = 130;

  /// Auto-hide thresholds: below this library size, or above this ratio of
  /// recent-to-total, the carousel duplicates the grid below and is hidden.
  static const int _minLibrarySize = 10;
  static const double _maxRecentRatio = 0.6;

  bool _hidden(ThemeProvider provider) => switch (scope) {
    RecentlyAddedCarouselScope.ownLib => provider.carouselHiddenOwnLib,
    RecentlyAddedCarouselScope.peerLib => provider.carouselHiddenPeerLib,
  };

  bool _collapsed(ThemeProvider provider) => switch (scope) {
    RecentlyAddedCarouselScope.ownLib => provider.carouselCollapsedOwnLib,
    RecentlyAddedCarouselScope.peerLib => provider.carouselCollapsedPeerLib,
  };

  Future<void> _setHidden(ThemeProvider provider, bool hidden) =>
      switch (scope) {
        RecentlyAddedCarouselScope.ownLib => provider.setCarouselHiddenOwnLib(
          hidden,
        ),
        RecentlyAddedCarouselScope.peerLib => provider.setCarouselHiddenPeerLib(
          hidden,
        ),
      };

  void _setCollapsed(ThemeProvider provider, bool collapsed) {
    switch (scope) {
      case RecentlyAddedCarouselScope.ownLib:
        provider.setCarouselCollapsedOwnLib(collapsed);
      case RecentlyAddedCarouselScope.peerLib:
        provider.setCarouselCollapsedPeerLib(collapsed);
    }
  }

  void _dismiss(BuildContext context, ThemeProvider provider) {
    _setHidden(provider, true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          TranslationService.translate(context, 'carousel_hidden_snackbar'),
        ),
        action: SnackBarAction(
          label: TranslationService.translate(context, 'action_undo'),
          onPressed: () => _setHidden(provider, false),
        ),
      ),
    );
  }

  List<Book> _recentBooks() {
    final recent = books.where((b) => b.isNew).toList();
    recent.sort((a, b) => b.addedAt!.compareTo(a.addedAt!));
    return recent.take(maxItems).toList();
  }

  bool _shouldAutoHide(int newCount) {
    if (books.length < _minLibrarySize) return true;
    return newCount / books.length > _maxRecentRatio;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ThemeProvider>();
    if (_hidden(provider)) return const SizedBox.shrink();

    final newCount = books.where((b) => b.isNew).length;
    if (newCount == 0 || _shouldAutoHide(newCount)) {
      return const SizedBox.shrink();
    }
    final recent = _recentBooks();

    final colorScheme = Theme.of(context).colorScheme;
    final collapsed = _collapsed(provider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesign.spacingMd,
        AppDesign.spacingXs,
        AppDesign.spacingMd,
        AppDesign.spacingSm,
      ),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.5),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: collapsed
              ? _CollapsedBar(
                  key: const ValueKey('collapsed'),
                  count: recent.length,
                  onExpand: () => _setCollapsed(provider, false),
                  onLongPress: () => _dismiss(context, provider),
                )
              : _ExpandedStrip(
                  key: const ValueKey('expanded'),
                  books: recent,
                  coverWidth: _coverWidth,
                  coverHeight: _coverHeight,
                  onCollapse: () => _setCollapsed(provider, true),
                  onLongPress: () => _dismiss(context, provider),
                  onTap: (book) {
                    if (onBookTap != null) {
                      onBookTap!(book);
                    } else {
                      context.push('/books/${book.id}', extra: book);
                    }
                  },
                ),
        ),
      ),
    );
  }
}

class _CollapsedBar extends StatelessWidget {
  const _CollapsedBar({
    super.key,
    required this.count,
    required this.onExpand,
    required this.onLongPress,
  });

  final int count;
  final VoidCallback onExpand;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final label = TranslationService.translate(
      context,
      'carousel_collapsed_label',
      params: {'count': count.toString()},
    );
    final expandHint = TranslationService.translate(
      context,
      'carousel_expand_tooltip',
    );

    return Semantics(
      button: true,
      label: '$label. $expandHint',
      child: InkWell(
        onTap: onExpand,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesign.spacingMd,
            vertical: AppDesign.spacingSm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.auto_stories_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: AppDesign.spacingSm),
              Expanded(
                child: Text(
                  label,
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                size: 20,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandedStrip extends StatelessWidget {
  const _ExpandedStrip({
    super.key,
    required this.books,
    required this.coverWidth,
    required this.coverHeight,
    required this.onCollapse,
    required this.onLongPress,
    required this.onTap,
  });

  final List<Book> books;
  final double coverWidth;
  final double coverHeight;
  final VoidCallback onCollapse;
  final VoidCallback onLongPress;
  final void Function(Book book) onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final collapseTooltip = TranslationService.translate(
      context,
      'carousel_collapse_tooltip',
    );
    final longPressHint = TranslationService.translate(
      context,
      'carousel_hide_long_press_tooltip',
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesign.spacingMd,
        AppDesign.spacingXs,
        AppDesign.spacingSm,
        AppDesign.spacingSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    TranslationService.translate(
                      context,
                      'recently_added_title',
                    ),
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Tooltip(
                message: '$collapseTooltip · $longPressHint',
                child: Semantics(
                  button: true,
                  label: '$collapseTooltip. $longPressHint',
                  child: InkWell(
                    onTap: onCollapse,
                    onLongPress: onLongPress,
                    borderRadius: BorderRadius.circular(AppDesign.radiusRound),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.expand_less_rounded,
                        size: 20,
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesign.spacingSm),
          SizedBox(
            height: coverHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: books.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: AppDesign.spacingSm),
              itemBuilder: (context, index) {
                final book = books[index];
                return _CarouselCover(
                  book: book,
                  width: coverWidth,
                  height: coverHeight,
                  onTap: () => onTap(book),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CarouselCover extends StatelessWidget {
  const _CarouselCover({
    required this.book,
    required this.width,
    required this.height,
    required this.onTap,
  });

  final Book book;
  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final semanticLabel = [
      book.title,
      if (book.author != null && book.author!.isNotEmpty) book.author!,
    ].join(' — ');

    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
          child: CachedBookCover(
            imageUrl: book.coverUrl,
            width: width,
            height: height,
            fit: BoxFit.cover,
            semanticLabel: semanticLabel,
          ),
        ),
      ),
    );
  }
}
