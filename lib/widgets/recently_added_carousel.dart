import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import 'book_cover_card.dart';

/// Scope of the carousel — controls which [ThemeProvider] flag backs its
/// visibility so the own-lib and peer-lib carousels can be toggled
/// independently.
enum RecentlyAddedCarouselScope { ownLib, peerLib }

/// Horizontal "Activité" strip displayed at the top of a library view.
/// Highlights the user's currently-reading books first, then recently-added
/// books (via [Book.isNew]). Reading books are sorted by startedReadingAt
/// desc (nulls last); new books by addedAt desc. Combined list capped at
/// [maxItems].
///
/// Three display states:
/// - **expanded**: full strip of covers (default, ~165 px tall)
/// - **collapsed**: single-row summary with count, auto-triggered when the
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
    this.maxItems = 20,
    this.onBookTap,
    this.headerTitle,
    this.bodyOverride,
    this.collapsedSummary,
  });

  final List<Book> books;
  final RecentlyAddedCarouselScope scope;
  final int maxItems;

  /// Replaces the default title in the header row, keeping the collapse
  /// chevron and its long-press-to-hide beside it. The library top slot
  /// (ADR-062) passes its segmented control here so the whole slot rides
  /// on this widget's hide/collapse machinery instead of duplicating it.
  final Widget? headerTitle;

  /// Replaces the strip of covers. When set, the Activity auto-hide
  /// heuristic no longer vetoes rendering: the caller has already decided
  /// the slot has something to show.
  final Widget? bodyOverride;

  /// Replaces the collapsed bar's summary line, so a collapsed slot does
  /// not describe recent additions while the reader is on another segment.
  final String? collapsedSummary;

  /// Optional override for tap handling. Defaults to GoRouter push to
  /// `/books/:id` (own-lib route). Peer lib screens should pass a custom
  /// handler because their detail route differs.
  final void Function(Book book)? onBookTap;

  // 2:3 matches the standard book cover aspect ratio (Inventaire /
  // OpenLibrary), so covers fit without cropping under BoxFit.cover. On
  // narrow devices (iPhone SE class, shortestSide < 360) we shrink further
  // so the strip takes less vertical room and fits more covers.
  static const double _coverWidthDefault = 80;
  static const double _coverHeightDefault = 120;
  static const double _coverWidthCompact = 64;
  static const double _coverHeightCompact = 96;
  static const double _compactBreakpoint = 360;

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

  /// Ordered selection: currently-reading books first (most recently started),
  /// then recently-added books that aren't already in the reading slice, then
  /// — if there's still room — padding with the most-recently-added books
  /// regardless of the isNew threshold so the strip stays useful in libraries
  /// that haven't been touched in the last [AppConstants.newBadgeDays] days.
  List<Book> _selectBooks() => _select(books, maxItems);

  static List<Book> _select(List<Book> books, int maxItems) {
    final reading = books.where((b) => b.readingStatus == 'reading').toList();
    reading.sort((a, b) {
      final aStarted = a.startedReadingAt;
      final bStarted = b.startedReadingAt;
      if (aStarted == null && bStarted == null) return 0;
      if (aStarted == null) return 1;
      if (bStarted == null) return -1;
      return bStarted.compareTo(aStarted);
    });

    final newOnly = books
        .where((b) => b.isNew && b.readingStatus != 'reading')
        .toList();
    newOnly.sort((a, b) => b.addedAt!.compareTo(a.addedAt!));

    final selected = [...reading, ...newOnly];
    // Only pad when the carousel already has a real anchor (reading or new).
    // Otherwise we'd surface the strip on libraries with no recent activity.
    if (selected.isEmpty || selected.length >= maxItems) {
      return selected.take(maxItems).toList();
    }

    final selectedIds = selected.map((b) => b.id).toSet();
    final padding = books
        .where((b) => b.addedAt != null && !selectedIds.contains(b.id))
        .toList();
    padding.sort((a, b) => b.addedAt!.compareTo(a.addedAt!));

    return [...selected, ...padding].take(maxItems).toList();
  }

  /// Hide when there is nothing to show. If the activity list is dominated
  /// by brand-new books in a small library, hide too: the carousel would
  /// duplicate the grid underneath and add no value.
  bool _shouldAutoHide(List<Book> selected) => _autoHide(books, selected);

  static bool _autoHide(List<Book> books, List<Book> selected) {
    if (selected.isEmpty) return true;
    final hasReading = selected.any((b) => b.readingStatus == 'reading');
    if (hasReading) return false;
    final newCount = books.where((b) => b.isNew).length;
    if (books.length < _minLibrarySize) return true;
    return newCount / books.length > _maxRecentRatio;
  }

  /// The Activity selection, empty when the strip has nothing worth
  /// showing. Public so the library top slot (ADR-062 section 4) can ask
  /// whether the Activity segment exists at all without copying the
  /// auto-hide heuristic, which would then drift from this one.
  static List<Book> activitySelection(List<Book> books, {int maxItems = 20}) {
    final selected = _select(books, maxItems);
    return _autoHide(books, selected) ? const [] : selected;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ThemeProvider>();
    if (_hidden(provider)) return const SizedBox.shrink();

    final selected = _selectBooks();
    // A caller supplying its own body owns the "is there anything to show"
    // decision (ADR-062 section 4): the Activity heuristic must not veto a
    // slot that is showing suggestions.
    if (bodyOverride == null && _shouldAutoHide(selected)) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final collapsed = _collapsed(provider);
    final compact =
        MediaQuery.sizeOf(context).shortestSide < _compactBreakpoint;
    final coverWidth = compact ? _coverWidthCompact : _coverWidthDefault;
    final coverHeight = compact ? _coverHeightCompact : _coverHeightDefault;

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
                  count: selected.length,
                  summaryOverride: collapsedSummary,
                  onExpand: () => _setCollapsed(provider, false),
                  onLongPress: () => _dismiss(context, provider),
                )
              : _ExpandedStrip(
                  key: const ValueKey('expanded'),
                  books: selected,
                  coverWidth: coverWidth,
                  coverHeight: coverHeight,
                  titleOverride: headerTitle,
                  bodyOverride: bodyOverride,
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
    this.summaryOverride,
  });

  final int count;
  final VoidCallback onExpand;
  final VoidCallback onLongPress;
  final String? summaryOverride;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final label =
        summaryOverride ??
        TranslationService.translate(
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
    this.titleOverride,
    this.bodyOverride,
  });

  final List<Book> books;
  final double coverWidth;
  final double coverHeight;
  final VoidCallback onCollapse;
  final VoidCallback onLongPress;
  final void Function(Book book) onTap;
  final Widget? titleOverride;
  final Widget? bodyOverride;

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
              if (titleOverride == null) ...[
                Icon(
                  Icons.auto_stories_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: AppDesign.spacingSm),
              ],
              Expanded(
                child:
                    titleOverride ??
                    Semantics(
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
          bodyOverride ??
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
    // Show a "NEW" badge only on books with no status tag. Any reading-status
    // badge (reading, loaned, borrowed, to_read, etc.) already occupies the
    // top-right corner; stacking NEW on the opposite corner would double the
    // tagging and clutter a small cover.
    final hasStatusBadge =
        book.readingStatus != null && book.readingStatus!.isNotEmpty;
    final showNewBadge = book.isNew && !hasStatusBadge;
    final daysLabel = _daysSinceStartLabel(context);

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          BookCoverCard(book: book, onTap: onTap),
          if (showNewBadge)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.shade700.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  TranslationService.translate(context, 'badge_new'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (daysLabel != null)
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  daysLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Returns a short localized label (e.g. "J+5", "D+99+") when the book is
  /// currently being read and has a known start date. Omits the label when:
  /// * the book is not reading,
  /// * startedReadingAt is null,
  /// * the start is today (would duplicate the status badge signal),
  /// * the start is in the future (clock drift safety).
  String? _daysSinceStartLabel(BuildContext context) {
    if (book.readingStatus != 'reading') return null;
    final started = book.startedReadingAt;
    if (started == null) return null;
    final startedDay = DateTime(started.year, started.month, started.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(startedDay).inDays;
    if (days <= 0) return null;
    final formatted = days >= 100 ? '99+' : days.toString();
    return TranslationService.translate(context, 'badge_days_since_start')
        .replaceAll('%s', formatted);
  }
}
