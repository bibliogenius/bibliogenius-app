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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = recommendationReasonChipLabel(
      context,
      reason,
      compact: compact,
    );

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppDesign.radiusRound),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            recommendationReasonIcon(reason),
            size: 13,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.3,
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
