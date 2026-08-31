import 'package:flutter/material.dart';

import '../services/translation_service.dart';
import 'star_rating_widget.dart';

/// The "my rating" / "pages" pair at the bottom of the book detail metadata
/// card.
///
/// The five stars have a fixed intrinsic width ([_starSize] plus padding, five
/// times over), so giving the rating exactly half the row left them wider than
/// their half on a phone and the last star painted over the page count. The
/// rating now takes the larger share, and below [stackBelowWidth] the page
/// count moves underneath rather than squeezing the stars: they are tap
/// targets, and scaling them down to fit was buying the layout back out of
/// the one budget that could least afford it.
class BookRatingRow extends StatelessWidget {
  /// Rating on the 0-10 scale used by [StarRatingWidget], or null when unrated.
  final int? rating;

  /// Page count, or null when unknown: the column is then dropped entirely and
  /// the rating spans the full row.
  final int? pageCount;

  /// Called with the new rating on the 0-10 scale, or null when the user
  /// clears it by tapping the star already selected.
  final ValueChanged<int?> onRatingChanged;

  /// Star glyph size when the row is wide enough to render the five stars
  /// unscaled. The tap target around each one is larger, see [_starsWidth].
  static const double _starSize = 32;

  /// Intrinsic width of the five stars: each glyph sits at the centre of a
  /// [StarRatingWidget.interactiveTargetSize] square, which is what the row
  /// actually has to seat.
  static const double _starsWidth =
      5 * StarRatingWidget.interactiveTargetSize;

  /// Narrowest row width that still leaves the rating column (flex 3 of 5) the
  /// full [_starsWidth]. Below it the two columns stack rather than share the
  /// row: shrinking the stars shrinks their tap targets with them, and those
  /// now sit exactly on the 44pt floor with nothing to give.
  ///
  /// Since the targets grew to that floor, the five of them are 220px wide, so
  /// this threshold is above any phone's card width: phones stack, tablets and
  /// desktop keep the two columns side by side.
  @visibleForTesting
  static const double stackBelowWidth = _starsWidth * 5 / 3;

  /// Gutter between the two columns while they sit side by side. It belongs to
  /// the pages column so it never eats into the width the stars are measured
  /// against: the stars keep their natural size on a regular phone, and a row
  /// too narrow to seat them stacks instead of closing the gap.
  @visibleForTesting
  static const double gutter = 12;

  /// Gap between the two columns once they stack, standing in for [gutter] on
  /// the vertical axis. Wider than the gutter because the page count sits
  /// directly under the stars with no divider to separate them.
  static const double _stackedGap = 16;

  const BookRatingRow({
    super.key,
    required this.rating,
    required this.pageCount,
    required this.onRatingChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ratingColumn = _LabelledColumn(
      label: TranslationService.translate(context, 'rating_label'),
      // Safety net only, now that a narrow row stacks instead of squeezing:
      // it takes a width below the stars' own 180px to trigger, which no
      // supported screen produces. It stays because an overflow here paints
      // over the neighbouring column rather than failing visibly.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: StarRatingWidget(
          rating: rating,
          onRatingChanged: onRatingChanged,
          size: _starSize,
        ),
      ),
    );

    final pagesColumn = pageCount == null
        ? null
        : _LabelledColumn(
            label: TranslationService.translate(context, 'page_count_label'),
            child: Text(
              '$pageCount',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Too narrow to give the stars their full width beside the page count:
        // stack instead. The rating then gets the whole width, so the stars
        // keep their size and so do the tap targets on a small phone.
        if (pagesColumn != null && constraints.maxWidth < stackBelowWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ratingColumn,
              const SizedBox(height: _stackedGap),
              pagesColumn,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: ratingColumn),
            if (pagesColumn != null)
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.only(left: gutter),
                  child: pagesColumn,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The caption style shared by every column of the book detail metadata card,
/// this row and `_buildMetadataItem` on the screen alike. Lives here so the two
/// captions cannot drift apart: they sit one divider away from each other, so
/// any divergence is immediately visible.
///
/// It pins the caption STYLE only, not the layout around it: the gap below the
/// caption stays each column's own (8 here, 6 in `_buildMetadataItem`).
/// Aligning those would move pixels on a card that is otherwise unchanged.
final TextStyle bookMetadataCaptionStyle = TextStyle(
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
        Text(label.toUpperCase(), style: bookMetadataCaptionStyle),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
