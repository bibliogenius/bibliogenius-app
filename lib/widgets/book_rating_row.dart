import 'package:flutter/material.dart';

import '../services/translation_service.dart';
import 'star_rating_widget.dart';

/// The "my rating" / "pages" pair at the bottom of the book detail metadata
/// card.
///
/// The five stars have a fixed intrinsic width ([starSize] plus padding, five
/// times over), so giving the rating exactly half the row left them wider than
/// their half on a phone and the last star painted over the page count. The
/// rating now takes the larger share, and the stars scale down when even that
/// is not enough - which also covers a raised system text size.
class BookRatingRow extends StatelessWidget {
  /// Rating on the 0-10 scale used by [StarRatingWidget], or null when unrated.
  final int? rating;

  /// Page count, or null when unknown: the column is then dropped entirely and
  /// the rating spans the full row.
  final int? pageCount;

  /// Called with the new rating on the 0-10 scale, or null when the user
  /// clears it by tapping the star already selected.
  final ValueChanged<int?> onRatingChanged;

  /// Star size when the row is wide enough to render the five stars unscaled.
  static const double starSize = 32;

  /// Gutter between the two columns. It belongs to the pages column so it
  /// never eats into the width the stars are measured against: the stars keep
  /// their natural size on a regular phone and the columns still never touch
  /// once a narrow layout has scaled them down to fill their own column.
  @visibleForTesting
  static const double gutter = 12;

  const BookRatingRow({
    super.key,
    required this.rating,
    required this.pageCount,
    required this.onRatingChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: _LabelledColumn(
            label: TranslationService.translate(context, 'rating_label'),
            // scaleDown keeps the stars at their natural size whenever they
            // fit and shrinks them only on the narrowest layouts, instead of
            // letting the row overflow into the neighbouring column.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: StarRatingWidget(
                rating: rating,
                onRatingChanged: onRatingChanged,
                size: starSize,
              ),
            ),
          ),
        ),
        if (pageCount != null)
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(left: gutter),
              child: _LabelledColumn(
                label: TranslationService.translate(
                  context,
                  'page_count_label',
                ),
                child: Text(
                  '$pageCount',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The caption style shared by every column of the book detail metadata card,
/// this row and `_buildMetadataItem` on the screen alike. Lives here so the two
/// cannot drift apart: they sit one divider away from each other, so any
/// divergence is immediately visible.
TextStyle bookMetadataCaptionStyle(BuildContext context) => TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.bold,
  letterSpacing: 1.0,
  color: Colors.grey[600],
);

/// One column of the row: an uppercase caption above its value.
class _LabelledColumn extends StatelessWidget {
  final String label;
  final Widget child;

  const _LabelledColumn({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: bookMetadataCaptionStyle(context)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
