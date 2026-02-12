import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import 'dart:math';
import '../services/translation_service.dart';
import '../providers/theme_provider.dart';
import '../theme/app_design.dart';
import '../utils/book_status.dart';
import 'cached_book_cover.dart';

class BookCoverCard extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;

  const BookCoverCard({super.key, required this.book, required this.onTap});

  // Autumn/vintage palette for Sorbonne theme
  static const List<Color> _autumnColors = [
    Color(0xFF8B4513), // Saddle brown
    Color(0xFFCD853F), // Peru/tan
    Color(0xFFD2691E), // Chocolate
    Color(0xFFA0522D), // Sienna
    Color(0xFF6B4423), // Dark brown
    Color(0xFFCC7722), // Ochre
    Color(0xFF8B6914), // Bronze
    Color(0xFF704214), // Sepia
  ];

  Color _getColorFromId(BuildContext context, int id) {
    final isSorbonne =
        Provider.of<ThemeProvider>(context, listen: false).themeStyle ==
        'sorbonne';
    if (isSorbonne) {
      return _autumnColors[id % _autumnColors.length];
    }
    final random = Random(id);
    return Color.fromARGB(
      255,
      random.nextInt(200),
      random.nextInt(200),
      random.nextInt(200),
    );
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
                ),

              // Gradient overlay for text readability (only if using fallback or if needed)
              if (book.coverUrl == null || book.coverUrl!.isEmpty)
                Container(
                  // Fallback cover already has color, but we can add specific styling here if needed
                ),

              // Reading Status Indicator
              if (book.readingStatus != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Builder(builder: (context) {
                    final statusInfo = getStatusFromValue(
                        context, book.readingStatus!, false);
                    final badgeColor =
                        statusInfo?.color ?? Colors.black;
                    return Container(
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
    final color = _getColorFromId(context, book.id ?? 0);
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            book.title,
            maxLines: 4,
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
          if (book.author != null) ...[
            const SizedBox(height: 8),
            Text(
              book.author!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
