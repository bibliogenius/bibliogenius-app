import 'package:flutter/material.dart';

/// Hint button shown during a hangman game: a lightbulb and the number of
/// hints left.
///
/// The visible content is small (16 px icon), so the tappable area is padded
/// to the 48 px minimum touch target. A bare [GestureDetector] around the icon
/// only reacted to taps landing on the painted glyphs, which a mouse hits but a
/// finger on a tablet mostly misses.
class HangmanHintButton extends StatelessWidget {
  /// Hints still available to spend.
  final int remaining;

  /// Called on tap; null disables the button (no hint left to reveal).
  final VoidCallback? onPressed;

  /// Accessible label, e.g. the translated "Hints".
  final String label;

  const HangmanHintButton({
    super.key,
    required this.remaining,
    required this.onPressed,
    required this.label,
  });

  static const double minTapTarget = kMinInteractiveDimension;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label: $remaining',
      // excludeSemantics also drops the InkWell's tap action, so the node
      // declares it itself.
      onTap: onPressed,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(minTapTarget / 2),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: minTapTarget,
            minHeight: minTapTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 16,
                  color: enabled
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Text(
                  '$remaining',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
