import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import '../services/translation_service.dart';
import '../providers/theme_provider.dart';
import '../theme/app_design.dart';
import '../utils/book_color_seed.dart';
import '../utils/book_status.dart';
import 'cached_book_cover.dart';

class BookCoverCard extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  final ValueChanged<String>? onStatusChanged;

  const BookCoverCard({
    super.key,
    required this.book,
    required this.onTap,
    this.onStatusChanged,
  });

  Color _getColorFromSeed(BuildContext context, int seed) {
    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).themeStyle ==
        'dark';
    // Golden-ratio hue distribution: consecutive seeds land ~137.5° apart on
    // the color wheel, so even sequential peer book seeds produce visually
    // distinct covers instead of clustering in one hue family.
    final hue = (seed.abs() * 137.508) % 360;
    return HSLColor.fromAHSL(
      1.0,
      hue,
      0.55,
      isDark ? 0.40 : 0.55,
    ).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final isOwned = book.owned;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isOwned ? 1.0 : 0.5,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
            boxShadow: AppDesign.subtleShadow,
          ),
          clipBehavior: Clip.antiAlias,
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
                  semanticLabel: book.author != null && book.author!.isNotEmpty
                      ? '${book.title}, ${book.author}'
                      : book.title,
                ),

              // Gradient overlay for text readability (only if using fallback or if needed)
              if (book.coverUrl == null || book.coverUrl!.isEmpty)
                Container(
                  // Fallback cover already has color, but we can add specific styling here if needed
                ),

              // Reading Status Indicator (tappable to edit)
              if (book.readingStatus != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Builder(builder: (context) {
                    final isLibrarian =
                        Provider.of<ThemeProvider>(context, listen: false)
                            .isLibrarian;
                    final statusInfo = getStatusFromValue(
                        context, book.readingStatus!, isLibrarian);
                    final badgeColor =
                        statusInfo?.color ?? Colors.black;
                    return GestureDetector(
                      onTap: onStatusChanged != null
                          ? () async {
                              final picked = await showReadingStatusPicker(
                                context,
                                currentStatus: book.readingStatus,
                                isLibrarian: isLibrarian,
                              );
                              if (picked != null &&
                                  picked != book.readingStatus) {
                                onStatusChanged!(picked);
                              }
                            }
                          : null,
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
                          TranslationService.translate(
                            context,
                            'reading_status_${book.readingStatus}',
                          ).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }),
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
                  book.title,
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
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
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
