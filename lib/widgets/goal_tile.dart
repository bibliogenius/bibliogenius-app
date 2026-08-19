import 'package:flutter/material.dart';

/// A goal-oriented shortcut tile: an action icon over a short label, with an
/// optional check badge when the underlying capability is already enabled.
///
/// Presentation-only (caller supplies the already-translated [label] and the
/// [onTap] behaviour) so it can be reused by the Settings springboard and the
/// Dashboard "discover more" section without duplicating the look.
class GoalTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  /// When set, the tile shows a close affordance that dismisses this tile only.
  /// Used by the Dashboard suggestions, where each tile is independently
  /// dismissible; the Settings springboard leaves it null.
  final VoidCallback? onDismiss;

  /// Already-translated tooltip / semantic label for the dismiss affordance.
  /// Required whenever [onDismiss] is set, so the button is never unlabelled
  /// for screen readers.
  final String? dismissTooltip;

  const GoalTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.onDismiss,
    this.dismissTooltip,
  }) : assert(
         onDismiss == null || dismissTooltip != null,
         'a dismissible tile needs a translated dismissTooltip',
       );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Semantics(
          button: true,
          label: label,
          // width:infinity so the Card fills its slot (e.g. an Expanded in a
          // two-column grid); otherwise the Stack passes loose constraints and
          // the Card shrinks to its content width.
          child: SizedBox(
            width: double.infinity,
            child: Card(
              margin: EdgeInsets.zero,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap,
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 12,
                    ),
                    child: Column(
                      children: [
                        Icon(icon, size: 28, color: cs.primary),
                        const SizedBox(height: 8),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
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
        if (active)
          const Positioned(
            top: 6,
            right: 6,
            child: Icon(Icons.check_circle, size: 16, color: Colors.green),
          ),
        // A tile is never both "already enabled" and "suggested", so the badge
        // and the dismiss button cannot collide in the same corner.
        if (onDismiss != null)
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.close, size: 16),
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: dismissTooltip,
              color: cs.onSurfaceVariant,
              onPressed: onDismiss,
            ),
          ),
      ],
    );
  }
}
