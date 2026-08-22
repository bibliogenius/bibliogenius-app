import 'package:flutter/material.dart';

import '../models/recommendation.dart';
import '../theme/app_design.dart';
import '../utils/recommendation_display.dart';

/// One "why this book" pill: the reason icon plus its label, tinted with the
/// theme primary. Shared by every recommendation surface so the explainability
/// vocabulary (ADR-059) looks the same on the dashboard and on a book page.
///
/// [compact] drops the sentence prefix and keeps the payload only ("Albert
/// Camus" instead of "Same author: Albert Camus"), for the narrow carousel
/// cards where the icon already carries the meaning; the full sentence stays
/// available as a tooltip.
class ReasonChip extends StatelessWidget {
  const ReasonChip({super.key, required this.reason, this.compact = false});

  final RecommendationReason reason;
  final bool compact;

  static const double _iconSize = 13;
  static const double _fontSize = 11;
  static const double _lineHeight = 1.3;
  static const double _verticalPadding = 4;
  static const double _borderWidth = 1;

  /// Laid-out height of the chip at the current text scale.
  ///
  /// A caller that reserves room for the chip (the similar-books carousel
  /// aligns every card's chip on one line) needs the exact figure, and the
  /// chip is the only place that knows its own metrics. Deterministic
  /// because the label pins its line height instead of relying on the
  /// font's own.
  static double height(BuildContext context) {
    // Rounded up like the text engine rounds a laid-out line, so the figure
    // is never a fraction of a pixel short of the real chip.
    final textLine =
        (MediaQuery.textScalerOf(context).scale(_fontSize) * _lineHeight)
            .ceilToDouble();
    final content = textLine > _iconSize ? textLine : _iconSize;
    return content + (_verticalPadding + _borderWidth) * 2;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = recommendationReasonChipLabel(
      context,
      reason,
      compact: compact,
    );

    final chip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: _verticalPadding,
      ),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppDesign.radiusRound),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.16),
          width: _borderWidth,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            recommendationReasonIcon(reason),
            size: _iconSize,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _fontSize,
                height: _lineHeight,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );

    // Whenever the chip drops the sentence prefix, keep the full wording
    // reachable on hover / long-press. The author reason needs no tooltip --
    // what it drops is printed on the card itself.
    final full = recommendationReasonLabel(context, reason);
    return label != full && !recommendationReasonRepeatsCard(reason)
        ? Tooltip(message: full, child: chip)
        : chip;
  }
}
