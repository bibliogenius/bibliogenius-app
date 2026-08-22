import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import '../services/translation_service.dart';
import '../providers/theme_provider.dart';
import '../theme/app_design.dart';
import '../utils/book_color_seed.dart';
import '../utils/book_display.dart';
import '../utils/book_status.dart';
import '../utils/ownership_mark.dart';
import 'cached_book_cover.dart';
import 'new_corner_band.dart';
import 'not_owned_treatment.dart';
import 'wishlist_availability_badge.dart';

class BookCoverCard extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  final ValueChanged<String>? onStatusChanged;

  /// Routes the underlying [CachedBookCover] to the peer cover cache.
  /// The card is used in both local contexts (own library, collection
  /// stacks) and peer contexts (peer library grid), so the caller has to
  /// tell us which cache to hit.
  final bool isPeerCover;

  /// Already-translated label for the wishlist availability badge
  /// ("available from X"). Null (the default) renders no badge; only the
  /// wishlist filter passes it, and only for books with a provider.
  final String? availabilityLabel;

  /// Opt-in "new" badge for freshly added books. Off by default: the activity
  /// carousel and the peer screens overlay their own markers on top of this
  /// card, and a default-on badge would double-tag them. The covers grid,
  /// which had no marker at all, opts in.
  final bool showNewBadge;

  const BookCoverCard({
    super.key,
    required this.book,
    required this.onTap,
    this.onStatusChanged,
    this.isPeerCover = false,
    this.availabilityLabel,
    this.showNewBadge = false,
  });

  Color _getColorFromSeed(BuildContext context, int seed) {
    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).themeStyle == 'dark';
    // Golden-ratio hue distribution: consecutive seeds land ~137.5° apart on
    // the color wheel, so even sequential peer book seeds produce visually
    // distinct covers instead of clustering in one hue family.
    final hue = (seed.abs() * 137.508) % 360;
    return HSLColor.fromAHSL(1.0, hue, 0.55, isDark ? 0.40 : 0.55).toColor();
  }

  @override
  Widget build(BuildContext context) {
    // Not-owned treatment (ADR-063): partial desaturation at full opacity,
    // plus the shared badge. Badges stay in full color on top of it. The
    // badge (not the treatment) stands down for a wished book, whose heart
    // the status badge below already shows.
    final mark = ownershipMarkOf(book);
    final badgeMark = badgeMarkFor(
      mark,
      statusBadgeShown: book.readingStatus != null,
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
          boxShadow: AppDesign.subtleShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            fit: StackFit.expand,
            children: [
              OwnershipCoverTreatment(
                mark: mark,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background / Cover (Layered for robust fallback)
                    _buildFallbackCover(context),

                    if (book.coverUrl != null && book.coverUrl!.isNotEmpty)
                      CachedBookCover(
                        imageUrl: book.coverUrl!,
                        fit: BoxFit.cover,
                        placeholder:
                            const SizedBox.shrink(), // Show fallback while loading
                        errorWidget:
                            const SizedBox.shrink(), // Show fallback on error
                        semanticLabel: BookDisplay.coverLabelOf(context, book),
                        isPeerCover: isPeerCover,
                      ),
                  ],
                ),
              ),

              if (badgeMark != OwnershipMark.none)
                Positioned(
                  top: 8,
                  left: 8,
                  child: OwnershipBadge(mark: badgeMark),
                ),

              // "New" marker (opt-in): the shared rotated paper band, on the
              // free bottom-right corner so it never competes with the
              // status badge (top-right) or the ownership badge (top-left).
              if (showNewBadge && book.isNew)
                const Positioned(bottom: 12, right: -6, child: NewCornerBand()),

              // Reading Status Indicator (tappable to edit). A long
              // translated label cannot fit a narrow cover: below the width
              // threshold the badge is the status icon alone (tooltip and
              // semantics carry the label); above it the pill is width-capped
              // with an ellipsis so it can never overflow the cover.
              if (book.readingStatus != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Builder(
                    builder: (context) {
                      final useInventoryStatuses = Provider.of<ThemeProvider>(
                        context,
                        listen: false,
                      ).inventoryStatusesEnabled;
                      final statusInfo = getStatusFromValue(
                        context,
                        book.readingStatus!,
                        useInventoryStatuses,
                      );
                      final badgeColor = statusInfo?.color ?? Colors.black;
                      final label = TranslationService.translate(
                        context,
                        'reading_status_${book.readingStatus}',
                      );
                      final onBadgeTap = onStatusChanged != null
                          ? () async {
                              final picked = await showReadingStatusPicker(
                                context,
                                currentStatus: book.readingStatus,
                                useInventoryStatuses: useInventoryStatuses,
                              );
                              if (picked != null &&
                                  picked != book.readingStatus) {
                                onStatusChanged!(picked);
                              }
                            }
                          : null;

                      if (box.maxWidth < 120) {
                        // Icon-only: the label must still reach the screen
                        // reader (Rule A1); the tooltip serves pointer users.
                        return Semantics(
                          label: label,
                          button: onBadgeTap != null,
                          child: Tooltip(
                            message: label,
                            excludeFromSemantics: true,
                            child: GestureDetector(
                              onTap: onBadgeTap,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.85),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  statusInfo?.icon ?? Icons.menu_book,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      return GestureDetector(
                        onTap: onBadgeTap,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: box.maxWidth - 16,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              label.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // Wishlist availability badge (wanted book, provider found)
              if (availabilityLabel != null)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: WishlistAvailabilityBadge(label: availabilityLabel!),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackCover(BuildContext context) {
    final color = _getColorFromSeed(context, bookColorSeed(book));
    return Container(
      decoration: BoxDecoration(
        color: color,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.8), color],
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The card is reused at several sizes: carousel strip (130 px tall),
          // grid tiles (~180 px), catalog hero (~240 px). Drop a line and
          // tighten spacing on shorter tiles so a long title doesn't push
          // the author row past the bottom edge.
          final compact = constraints.maxHeight < 140;
          final titleMaxLines = compact ? 3 : 4;
          final spacing = compact ? 4.0 : 8.0;
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  // A book pushed without a title would otherwise render as a
                  // blank coloured tile: fall back to its ISBN, then to the
                  // translated placeholder.
                  BookDisplay.titleOf(context, book),
                  maxLines: titleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    shadows: [
                      Shadow(
                        offset: Offset(0, 1),
                        blurRadius: 2,
                        color: Colors.black45,
                      ),
                    ],
                  ),
                ),
              ),
              if (book.author != null) ...[
                SizedBox(height: spacing),
                Flexible(
                  child: Text(
                    book.author!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
