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

  const GoalTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: Stack(
        children: [
          // width:infinity so the Card fills its slot (e.g. an Expanded in a
          // two-column grid); otherwise the Stack passes loose constraints and
          // the Card shrinks to its content width.
          SizedBox(
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
          if (active)
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(Icons.check_circle, size: 16, color: Colors.green),
            ),
        ],
      ),
    );
  }
}
