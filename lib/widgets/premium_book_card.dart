import 'package:provider/provider.dart';
import '../models/book.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../utils/book_status.dart';
import '../utils/ownership_mark.dart';
import 'cached_book_cover.dart';
import 'favorite_ribbon.dart';
import 'not_owned_treatment.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Whether the reader opens the card with a mouse click rather than a tap.
///
/// Read from the theme's platform, not the window width: a wide tablet is
/// still touched, and on the web the platform follows the browser's system.
bool _usesPointer(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};

/// Width of the cover on the list card, also the size it is decoded at.
const double _heroCoverWidth = 120;

/// Whether the card should mark this book as borrowed or lent.
bool showsLoanStateBadge(Book book) => book.isOnLoan;

/// Pill overlaid on a book card to name a state the cover cannot show.
///
/// [onCover] picks the treatment: translucent black over a cover image, where
/// theme colours cannot be trusted against arbitrary artwork, and an outlined
/// theme pill on the card surface.
class _CardPill extends StatelessWidget {
  /// Marks a book as borrowed or lent, alongside (never instead of) the
  /// reading-status pill: possession and reading are independent axes.
  ///
  /// A book can be both, when the user lent their copy and borrowed another of
  /// the same title. "Borrowed" wins the label: it names the copy physically on
  /// the shelf, which is the one the reader has in hand.
  const _CardPill.loanState({required bool borrowed, this.onCover = false})
    : labelKey = borrowed ? 'reading_status_borrowed' : 'reading_status_lent',
      icon = borrowed ? Icons.call_received : Icons.call_made;

  final String labelKey;
  final IconData icon;
  final bool onCover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = TranslationService.translate(context, labelKey);
    final foreground = onCover
        ? Colors.white
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      label: label,
      // The child Text repeats the label in upper case, which a screen reader
      // may spell out letter by letter. Announce the label once, in its natural
      // casing, and drop the decorative icon and text from the tree.
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: onCover
              ? Colors.black.withValues(alpha: 0.65)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: onCover
                ? Colors.white.withValues(alpha: 0.6)
                : theme.colorScheme.outline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: foreground),
            const SizedBox(width: 4),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: foreground,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PremiumBookCard extends StatefulWidget {
  final Book book;
  final double width;
  final double height;
  final bool isHero;
  final bool showStatus;
  final ValueChanged<String>? onStatusChanged;

  /// Favorite marker (ADR-064): the star-bookmark ribbon overhanging the
  /// top-right corner of the standard card. The PARENT computes membership
  /// from the FavoritesProvider set (one lookup per screen, not per card).
  final bool isFavorite;

  const PremiumBookCard({
    super.key,
    required this.book,
    this.width = 160,
    this.height = 240,
    this.isHero = false,
    this.showStatus = true,
    this.onStatusChanged,
    this.isFavorite = false,
  });

  @override
  State<PremiumBookCard> createState() => _PremiumBookCardState();
}

class _PremiumBookCardState extends State<PremiumBookCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isHero) {
      return _buildHeroCard(context);
    }
    return _buildStandardCard(context);
  }

  Color _generateRandomColor(String seed) {
    final hash = seed.hashCode;
    final colors = [
      Colors.blue.shade800,
      Colors.red.shade800,
      Colors.green.shade800,
      Colors.purple.shade800,
      Colors.orange.shade800,
      Colors.teal.shade800,
      Colors.indigo.shade800,
      Colors.brown.shade800,
    ];
    return colors[hash.abs() % colors.length];
  }

  Widget _buildFallbackCover(BuildContext context) {
    final color = _generateRandomColor(
      widget.book.title + (widget.book.id?.toString() ?? ''),
    );

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: color,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.6)],
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            widget.book.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14, // Adjusted for smaller standard cards
              shadows: [
                Shadow(
                  color: Colors.black26,
                  offset: Offset(0, 1),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
          if (widget.book.author != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.book.author!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Icon(
            Icons.auto_stories,
            color: Colors.white.withValues(alpha: 0.2),
            size: 24,
          ),
        ],
      ),
    );
  }

  /// The reading-status pill (tappable to edit) and the loan pill, stacked
  /// right after the list card's title; empty when the book wears neither.
  List<Widget> _buildHeroPills(BuildContext context) {
    final book = widget.book;
    final useInventoryStatuses = context
        .read<ThemeProvider>()
        .inventoryStatusesEnabled;
    final statusColors = hasReadingStatus(book.readingStatus)
        ? statusBadgeColors(
            getStatusFromValue(
              context,
              book.readingStatus!,
              useInventoryStatuses,
            ),
          )
        : null;
    final pills = <Widget>[
      if (statusColors != null)
        Semantics(
          label: TranslationService.translate(
            context,
            'reading_status_${book.readingStatus}',
          ),
          button: widget.onStatusChanged != null,
          child: GestureDetector(
            onTap: widget.onStatusChanged != null
                ? () async {
                    final picked = await showReadingStatusPicker(
                      context,
                      currentStatus: book.readingStatus,
                      useInventoryStatuses: useInventoryStatuses,
                    );
                    if (picked != null && picked != book.readingStatus) {
                      widget.onStatusChanged!(picked);
                    }
                  }
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusColors.background,
                borderRadius: BorderRadius.circular(20),
              ),
              // The wrapper above names the pill in its own case; the capitals
              // are only for the eye.
              child: ExcludeSemantics(
                child: Text(
                  TranslationService.translate(
                    context,
                    'reading_status_${book.readingStatus}',
                  ).toUpperCase(),
                  style: TextStyle(
                    color: statusColors.foreground,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      // Possession marker, independent of the status pill: a borrowed book
      // carries its own reading status like any other.
      if (showsLoanStateBadge(book))
        _CardPill.loanState(borrowed: book.isBorrowed ?? false),
    ];
    if (pills.isEmpty) return const [];
    return [
      const SizedBox(width: 12),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, pill) in pills.indexed) ...[
            if (index > 0) const SizedBox(height: 6),
            pill,
          ],
        ],
      ),
    ];
  }

  /// "Author · Gallimard · 1998 · 320 p." on the list card, the facts in a
  /// smaller type than the author; it may wrap to a second line on a narrow
  /// card rather than drop the facts. Null when there is neither.
  Widget? _authorAndFacts(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    final author = widget.book.author;
    final facts = _bookFacts().isEmpty ? null : _bookFactsLine(context);
    if (author == null && facts == null) return null;
    return Text.rich(
      key: const Key('premiumBookCardAuthorFacts'),
      TextSpan(
        children: [
          if (author != null)
            TextSpan(
              text: author,
              style: theme.textTheme.bodyLarge?.copyWith(color: muted),
            ),
          if (facts != null)
            TextSpan(
              text: author == null ? facts : ' · $facts',
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// The book facts the list card shows after the author, as (label key,
  /// value) pairs, leaving out what the record does not hold.
  List<(String, String)> _bookFacts() {
    final book = widget.book;
    final publisher = book.publisher?.trim();
    final year = book.publicationYear;
    final pages = book.pageCount;
    return [
      if (publisher != null && publisher.isNotEmpty)
        ('publisher_label', publisher),
      if (year != null && year > 0) ('year_label', '$year'),
      if (pages != null && pages > 0) ('page_count_label', '$pages'),
    ];
  }

  /// One line for the eye: "Gallimard · 1998 · 320 p.".
  String _bookFactsLine(BuildContext context) => _bookFacts()
      .map(
        (fact) => fact.$1 == 'page_count_label'
            ? '${fact.$2} ${TranslationService.translate(context, 'pages_suffix')}'
            : fact.$2,
      )
      .join(' · ');

  /// The summary folded to a single paragraph, so that its two visible lines
  /// are not spent on line breaks; null when there is nothing to show.
  String? _foldedSummary() {
    final folded = widget.book.summary?.replaceAll(RegExp(r'\s+'), ' ').trim();
    return folded == null || folded.isEmpty ? null : folded;
  }

  String _semanticLabel(BuildContext context) {
    final parts = [widget.book.title];
    if (widget.book.author != null) parts.add(widget.book.author!);
    if (widget.isHero) {
      // The facts shown on the list card, spelled out: "320 p." is for the
      // eye. The summary is too long for a label and stays on the book page.
      for (final (labelKey, value) in _bookFacts()) {
        parts.add('${TranslationService.translate(context, labelKey)}: $value');
      }
    }
    if (widget.isFavorite) {
      // Rule A1: the ribbon is shape-only, the state must still reach
      // screen readers through the composed card label.
      parts.add(
        TranslationService.translate(context, 'favorite_marker_label'),
      );
    }
    return parts.join(', ');
  }

  Widget _buildHeroCard(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: _semanticLabel(context),
      child: GestureDetector(
        onTap: () =>
            context.push('/books/${widget.book.id}', extra: widget.book),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovering = true),
          onExit: (_) => setState(() => _isHovering = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: theme.primaryColor.withValues(
                    alpha: _isHovering ? 0.3 : 0.15,
                  ),
                  blurRadius: _isHovering ? 30 : 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  // Gradient accent bar at top
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.primaryColor,
                            theme.colorScheme.secondary,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Main content
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Book cover thumbnail
                          Container(
                            width: _heroCoverWidth,
                            height: 180,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 15,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // Not-owned treatment (ADR-063): the cover
                                  // desaturates, the shared badge names it.
                                  OwnershipCoverTreatment(
                                    mark: ownershipMarkOf(widget.book),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        // Fallback always at bottom. Its
                                        // painted title is for the eye: the
                                        // card's label names the book.
                                        ExcludeSemantics(
                                          child: _buildFallbackCover(context),
                                        ),
                                        // Image on top
                                        if (widget.book.coverUrl != null &&
                                            widget.book.coverUrl!.isNotEmpty)
                                          // The card's own Semantics names
                                          // the book; without a
                                          // semanticLabel the cover stays
                                          // out of the tree.
                                          CachedBookCover(
                                            imageUrl: widget.book.coverUrl!,
                                            semanticLabel: null,
                                            width: _heroCoverWidth,
                                            fit: BoxFit.cover,
                                            // The fallback underneath shows
                                            // while loading and on error.
                                            placeholder:
                                                const SizedBox.shrink(),
                                            errorWidget:
                                                const SizedBox.shrink(),
                                          ),
                                      ],
                                    ),
                                  ),
                                  // The badge stands down for a wished book:
                                  // the wanting status pill in the info
                                  // column already shows the wish.
                                  if (badgeMarkOf(
                                        widget.book,
                                        statusBadgeShown: hasReadingStatus(
                                          widget.book.readingStatus,
                                        ),
                                      ) !=
                                      OwnershipMark.none)
                                    Positioned(
                                      top: 8,
                                      left: 8,
                                      child: OwnershipBadge(
                                        mark: ownershipMarkOf(widget.book),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          // Book info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title, the status and loan pills right
                                // after it (Flexible, not Expanded: a short
                                // title must not push them to the far edge).
                                // Title and author are in the card's label
                                // already.
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Flexible(
                                      child: ExcludeSemantics(
                                        child: Text(
                                          widget.book.title,
                                          key: const Key(
                                            'premiumBookCardTitle',
                                          ),
                                          style: theme.textTheme.headlineSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    ..._buildHeroPills(context),
                                  ],
                                ),
                                // Author, then publisher, year and pages,
                                // spelled out in the card's label.
                                if (_authorAndFacts(context)
                                    case final line?) ...[
                                  const SizedBox(height: 8),
                                  ExcludeSemantics(child: line),
                                ],
                                // The summary's opening, a foretaste: the
                                // book page reads it in full.
                                if (_foldedSummary() case final summary?) ...[
                                  const SizedBox(height: 8),
                                  ExcludeSemantics(
                                    child: Text(
                                      summary,
                                      key: const Key('premiumBookCardSummary'),
                                      style: theme.textTheme.bodyMedium,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                const Spacer(),
                                // Action hint
                                // "Tap to view" is advice for the eye; the button role says it.
                                // A desktop reader clicks rather than taps.
                                ExcludeSemantics(
                                  child: Row(
                                    children: [
                                      Icon(
                                        _usesPointer(context)
                                            ? Icons.mouse
                                            : Icons.touch_app,
                                        size: 16,
                                        color: theme.primaryColor,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        TranslationService.translate(
                                          context,
                                          _usesPointer(context)
                                              ? 'click_to_view'
                                              : 'tap_to_view',
                                        ),
                                        style: TextStyle(
                                          color: theme.primaryColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildStandardCard(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: _semanticLabel(context),
      child: GestureDetector(
        onTap: () =>
            context.push('/books/${widget.book.id}', extra: widget.book),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            _controller.forward();
            setState(() => _isHovering = true);
          },
          onExit: (_) {
            _controller.reverse();
            setState(() => _isHovering = false);
          },
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) => Transform.scale(
              scale: _scaleAnimation.value,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: widget.width,
                margin: const EdgeInsets.only(right: 16, bottom: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
                  boxShadow: _isHovering
                      ? AppDesign.glowShadow(theme.colorScheme.primary)
                      : AppDesign.cardShadow,
                ),
                child: Stack(
                  // The favorite ribbon overhangs the card's top edge
                  // (ADR-064): it must escape the rounded clip below, so it
                  // lives in this outer, non-clipping Stack.
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                  borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
                  child: Stack(
                    children: [
                      // Cover Image, desaturated when not owned (ADR-063)
                      SizedBox(
                        height: widget.height,
                        width: widget.width,
                        child: OwnershipCoverTreatment(
                          mark: ownershipMarkOf(widget.book),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // The card's label names the book; the
                              // painted title is for the eye.
                              ExcludeSemantics(
                                child: _buildFallbackCover(context),
                              ),
                              if (widget.book.coverUrl != null &&
                                  widget.book.coverUrl!.isNotEmpty)
                                // The card's own Semantics names the book;
                                // without a semanticLabel the cover stays
                                // out of the tree.
                                CachedBookCover(
                                  imageUrl: widget.book.coverUrl!,
                                  semanticLabel: null,
                                  width: widget.width,
                                  fit: BoxFit.cover,
                                  // The fallback underneath shows while
                                  // loading and on error.
                                  placeholder: const SizedBox.shrink(),
                                  errorWidget: const SizedBox.shrink(),
                                ),
                            ],
                          ),
                        ),
                      ),
                      // Gradient Overlay on Hover
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _isHovering ? 1.0 : 0.0,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                theme.colorScheme.primary.withValues(
                                  alpha: 0.5,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Possession badge, opposite the reading-status badge. The
                      // two never collide: the ownership mark stands down for a
                      // book on loan.
                      if (showsLoanStateBadge(widget.book))
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _CardPill.loanState(
                            borrowed: widget.book.isBorrowed ?? false,
                            onCover: true,
                          ),
                        ),
                      // Shared ownership badge (ADR-063). It stands down for
                      // a wished book when the wanting status badge is shown:
                      // that badge already carries the heart.
                      if (badgeMarkOf(
                            widget.book,
                            statusBadgeShown:
                                widget.showStatus &&
                                hasReadingStatus(widget.book.readingStatus),
                          ) !=
                          OwnershipMark.none)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: OwnershipBadge(
                            mark: ownershipMarkOf(widget.book),
                          ),
                        ),
                      // Status Badge (tappable to edit). Steps left of the
                      // favorite ribbon when it holds the corner (ADR-064).
                      if (widget.showStatus &&
                          hasReadingStatus(widget.book.readingStatus))
                        Positioned(
                          top: 8,
                          right: widget.isFavorite
                              ? 8 + FavoriteRibbon.boxWidthFor(12) + 4
                              : 8,
                          child: Builder(
                            builder: (context) {
                              final useInventoryStatuses = context
                                  .read<ThemeProvider>()
                                  .inventoryStatusesEnabled;
                              final statusInfo = getStatusFromValue(
                                context,
                                widget.book.readingStatus!,
                                useInventoryStatuses,
                              );
                              final badgeColors = statusBadgeColors(
                                statusInfo,
                              );
                              // The pill prints the status in capitals; the
                              // reader hears it in its own case, as a button
                              // when it opens the status picker.
                              return Semantics(
                                label: TranslationService.translate(
                                  context,
                                  'reading_status_${widget.book.readingStatus}',
                                ),
                                button: widget.onStatusChanged != null,
                                child: GestureDetector(
                                  onTap: widget.onStatusChanged != null
                                      ? () async {
                                          final picked =
                                              await showReadingStatusPicker(
                                                context,
                                                currentStatus:
                                                    widget.book.readingStatus,
                                                useInventoryStatuses:
                                                    useInventoryStatuses,
                                              );
                                          if (picked != null &&
                                              picked !=
                                                  widget.book.readingStatus) {
                                            widget.onStatusChanged!(picked);
                                          }
                                        }
                                      : null,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: badgeColors.background,
                                      borderRadius: BorderRadius.circular(12),
                                      border: statusPillCoverBorder,
                                    ),
                                    child: ExcludeSemantics(
                                      child: Text(
                                        TranslationService.translate(
                                          context,
                                          'reading_status_${widget.book.readingStatus}',
                                        ).toUpperCase(),
                                        style: TextStyle(
                                          color: badgeColors.foreground,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                    if (widget.isFavorite)
                      Positioned(
                        top: -FavoriteRibbon.overhangFor(12),
                        right: 8,
                        child: const FavoriteRibbon(width: 12),
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
