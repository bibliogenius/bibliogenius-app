import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../utils/book_status.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Values the backend writes into `readingStatus` that are NOT reading statuses.
///
/// `book_service.rs` overlays the possession axis onto the reading one: when a
/// copy is borrowed or lent, it replaces the stored status before serialising.
/// So `readingStatus` conflates two unrelated things, and Flutter has no other
/// source for the loan state. Reading them here is deliberate, and confined to
/// this file: when the DTO grows a proper loan-state field, this set is the only
/// thing that has to change.
const _loanStateOverlay = {'borrowed', 'lent'};

/// Whether the card should mark this book as not owned.
///
/// A borrowed or lent book already wears a badge that says where it stands, and a
/// wished-for book (`wanting`, a genuine reading status) already reads as one. A
/// second badge on any of them would be noise. The marker is for the case nothing
/// else names: a book read, or simply held, without being owned.
bool showsNotOwnedBadge(Book book) {
  if (book.owned) return false;
  final status = book.readingStatus;
  if (_loanStateOverlay.contains(status)) return false;
  return status != 'wanting';
}

/// Pill marking a book the user does not own.
///
/// [onCover] picks the treatment: translucent black over a cover image, where
/// theme colours cannot be trusted against arbitrary artwork, and an outlined
/// theme pill on the card surface.
class _NotOwnedPill extends StatelessWidget {
  const _NotOwnedPill({this.onCover = false});

  final bool onCover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = TranslationService.translate(context, 'not_owned');
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
            Icon(Icons.bookmark_remove_outlined, size: 11, color: foreground),
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

  const PremiumBookCard({
    super.key,
    required this.book,
    this.width = 160,
    this.height = 240,
    this.isHero = false,
    this.showStatus = true,
    this.onStatusChanged,
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

  String get _semanticLabel {
    final parts = [widget.book.title];
    if (widget.book.author != null) parts.add(widget.book.author!);
    return parts.join(', ');
  }

  Widget _buildHeroCard(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: _semanticLabel,
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
                            width: 120,
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
                                  // Fallback always at bottom
                                  _buildFallbackCover(context),
                                  // Image on top
                                  if (widget.book.coverUrl != null &&
                                      widget.book.coverUrl!.isNotEmpty)
                                    CachedNetworkImage(
                                      imageUrl: widget.book.coverUrl!,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) =>
                                          const SizedBox.shrink(),
                                      errorWidget: (context, url, error) =>
                                          const SizedBox.shrink(),
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
                                // Continue Reading badge (tappable to edit)
                                if (widget.book.readingStatus != null) ...[
                                  GestureDetector(
                                    onTap: widget.onStatusChanged != null
                                        ? () async {
                                            final useInventoryStatuses = context
                                                .read<ThemeProvider>()
                                                .inventoryStatusesEnabled;
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
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            theme.primaryColor,
                                            theme.colorScheme.secondary,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        TranslationService.translate(
                                          context,
                                          'reading_status_${widget.book.readingStatus}',
                                        ).toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                // Ownership marker, independent of the status pill
                                // above: a book can be read without being owned.
                                if (showsNotOwnedBadge(widget.book)) ...[
                                  const _NotOwnedPill(),
                                  const SizedBox(height: 12),
                                ],
                                // Title
                                Text(
                                  widget.book.title,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                // Author
                                if (widget.book.author != null)
                                  Text(
                                    widget.book.author!,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: theme.textTheme.bodySmall?.color,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                const Spacer(),
                                // Action hint
                                Row(
                                  children: [
                                    Icon(
                                      Icons.touch_app,
                                      size: 16,
                                      color: theme.primaryColor,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      TranslationService.translate(
                                        context,
                                        'tap_to_view',
                                      ),
                                      style: TextStyle(
                                        color: theme.primaryColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
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
      label: _semanticLabel,
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
                  child: Stack(
                    children: [
                      // Cover Image
                      SizedBox(
                        height: widget.height,
                        width: widget.width,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildFallbackCover(context),
                            if (widget.book.coverUrl != null &&
                                widget.book.coverUrl!.isNotEmpty)
                              CachedNetworkImage(
                                imageUrl: widget.book.coverUrl!,
                                fit: BoxFit.cover,
                                placeholder: (context, url) =>
                                    const SizedBox.shrink(),
                                errorWidget: (context, url, error) =>
                                    const SizedBox.shrink(),
                              ),
                          ],
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
                      // Ownership badge, opposite the reading-status badge. A book
                      // read but not owned is otherwise indistinguishable from the
                      // rest of the shelf.
                      if (showsNotOwnedBadge(widget.book))
                        const Positioned(
                          top: 8,
                          left: 8,
                          child: _NotOwnedPill(onCover: true),
                        ),
                      // Status Badge (tappable to edit)
                      if (widget.showStatus &&
                          widget.book.readingStatus != null)
                        Positioned(
                          top: 8,
                          right: 8,
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
                              final badgeColor =
                                  statusInfo?.color ?? Colors.blueAccent;
                              return GestureDetector(
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
                                    color: badgeColor.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    TranslationService.translate(
                                      context,
                                      'reading_status_${widget.book.readingStatus}',
                                    ).toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}
