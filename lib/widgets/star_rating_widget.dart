import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../utils/rating_format.dart';

/// A 5-star rating widget that can be interactive or display-only.
///
/// Supports half-star precision when [allowHalf] is true.
/// Stores rating internally on a 0-10 scale for precision.
class StarRatingWidget extends StatelessWidget {
  /// Current rating on 0-10 scale (will display as 0-5 stars)
  final int? rating;

  /// Callback when rating changes (provides 0-10 scale value)
  final ValueChanged<int?>? onRatingChanged;

  /// Size of each star icon
  final double size;

  /// Allow half-star ratings
  final bool allowHalf;

  /// Color for filled stars
  final Color activeColor;

  /// Color for empty stars
  final Color inactiveColor;

  /// Show as compact (smaller, no padding)
  final bool compact;

  const StarRatingWidget({
    super.key,
    this.rating,
    this.onRatingChanged,
    this.size = 28,
    this.allowHalf = false,
    this.activeColor = Colors.amber,
    this.inactiveColor = Colors.grey,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isInteractive = onRatingChanged != null;
    final starCount = 5;
    final displayRating = (rating ?? 0) / 2.0; // Convert 0-10 to 0-5

    return Semantics(
      // Rule A4: the announced value goes through the catalogues. It used to be
      // a hardcoded French string, announced as such to every reader whatever
      // their locale.
      label: TranslationService.translate(
        context,
        'rating_semantic_label',
        // Same locale source as the catalogue lookup above, so the number and
        // the sentence around it never disagree.
        params: {
          'rating': formatStarRating(
            displayRating,
            Provider.of<ThemeProvider>(context, listen: false).localeTag,
          ),
        },
      ),
      slider: isInteractive,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(starCount, (index) {
          final starValue = index + 1;

          // Determine fill level for this star
          IconData icon;
          Color color;

          if (displayRating >= starValue) {
            // Full star
            icon = Icons.star_rounded;
            color = activeColor;
          } else if (displayRating >= starValue - 0.5) {
            // Half star
            icon = Icons.star_half_rounded;
            color = activeColor;
          } else {
            // Empty star
            icon = Icons.star_outline_rounded;
            color = inactiveColor.withValues(alpha: 0.4);
          }

          final star = Icon(
            icon,
            size: compact ? size * 0.7 : size,
            color: color,
          );

          if (!isInteractive) {
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 1 : 2),
              child: star,
            );
          }

          // Interactive: tap to set rating
          return GestureDetector(
            onTap: () {
              // Convert star position (1-5) to 0-10 scale
              final newRating = starValue * 2;
              // If tapping same star, toggle off
              if (rating == newRating) {
                onRatingChanged!(null);
              } else {
                onRatingChanged!(newRating);
              }
            },
            onHorizontalDragUpdate: allowHalf
                ? (details) {
                    // Allow half-star precision via drag
                    final box = context.findRenderObject() as RenderBox?;
                    if (box != null) {
                      final localPos = box.globalToLocal(
                        details.globalPosition,
                      );
                      final starWidth =
                          (compact ? size * 0.7 : size) + (compact ? 2 : 4);
                      final rawRating = (localPos.dx / starWidth).clamp(
                        0.0,
                        5.0,
                      );
                      final roundedRating = (rawRating * 2)
                          .round(); // 0-10 scale
                      onRatingChanged!(roundedRating);
                    }
                  }
                : null,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 1 : 2),
              child: star,
            ),
          );
        }),
      ),
    );
  }
}
