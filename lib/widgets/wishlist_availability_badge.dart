import 'package:flutter/material.dart';

/// Small overlay pill flagging a wanted book as available from the
/// user's network (paired peers / followed libraries).
///
/// [label] is the already-translated accessibility/tooltip text (e.g.
/// "Disponible chez Marie"). The badge only exists when there is at
/// least one provider: no empty state by design.
class WishlistAvailabilityBadge extends StatelessWidget {
  final String label;

  const WishlistAvailabilityBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      child: Tooltip(
        message: label,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.9),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.people, size: 14, color: cs.onPrimary),
        ),
      ),
    );
  }
}
